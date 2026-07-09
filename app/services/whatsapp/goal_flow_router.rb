module Whatsapp
  # Routes every reply inside an open goal-creation conversation (round 3 decision 8).
  # 100% deterministic — Money.to_cents / GoalMonthPhrase / pick; ZERO LLM calls after the
  # trigger message. The REAL draft Goal is created only when the slots are complete (offer
  # time), with the Analyzer baseline computed in-job BEFORE save — the same race fix as
  # GoalsController#create. Accept is ALWAYS-LINKED (decision 4): no caixinha or no distinct
  # source blocks activation with a friendly nudge, and the draft is destroyed (an invisible
  # draft would leak the monthly AI-session quota).
  class GoalFlowRouter
    include HandlerHelpers

    CANCEL_RE = /\A(cancelar?|cancel|deixa( pra la)?|esquece|parar?|sair)\z/
    YES_RE    = /\A(sim|s|quero|pode|bora|fechou|fechado|ok|yes|y)\z/
    NO_RE     = /\A(nao|n|agora nao|melhor nao|no|not now)\z/
    NONE_RE   = /\A(nao|nada|zero|0|no|nothing)\z/

    def initialize(conversation, msg, text)
      @conv = conversation
      @msg  = msg
      @text = text.to_s
    end

    def call
      norm = Whatsapp.normalize(@text)
      return cancel! if CANCEL_RE.match?(norm)
      # The alert-advertised keyword must work even mid-creation-chat (its 24h TTL would
      # otherwise swallow it as a slot answer) — but it only supersedes this chat when there
      # IS a goal to reorganize; with none, answer and keep the half-built draft (review fix:
      # a first-goal creator must never lose their draft to a keyword with nothing to act on).
      if Interpreter::REPLAN_RE.match?(norm) && !@conv.status.start_with?("replan")
        return reply("goal_replan.none") unless account.goals.active.where(kind: "purchase").exists?
        discard_draft!
        close!
        return GoalReplanHandler.new(@msg).call
      end
      case @conv.status
      when "collecting"          then resolve_slot
      when "offered"             then resolve_offer_reply
      when "picking_caixinha"    then resolve_caixinha_pick
      when "picking_source"      then resolve_source_pick
      when "replan_picking_goal" then resolve_replan_goal_pick
      when "replan_offered"      then resolve_replan_reply
      end
    end

    # Ask the next missing slot, or move to the offer when the slots are complete. Public:
    # GoalFlowHandler calls it right after seeding the conversation from the trigger.
    def ask_next
      slot = next_slot
      return offer! if slot.nil?
      # Every (re-)ask refreshes the TTL — a chained question must not be born expired.
      @conv.update!(data: @conv.data.merge("pending_slot" => slot),
                    expires_at: GoalConversation::TTL.from_now)
      ask(slot)
    end

    # Public: GoalReplanHandler jumps straight here when the account has one candidate (round
    # 4). The option NUMBERS are display-only — applying re-derives inside Goals::Replan.
    def present_replan_offer(goal)
      offer = Goals::ReplanOffer.for(goal)
      if offer.nil?
        close!
        return reply("goal_replan.unavailable")
      end
      lines = replan_option_lines(offer)
      @conv.update!(status: "replan_offered", goal: goal,
                    data: @conv.data.merge("modes" => offer.options.map(&:mode), "option_lines" => lines),
                    expires_at: GoalConversation::TTL.from_now)
      reply("goal_replan.offer", name: goal.name, saved: whole_floor(offer.saved_cents), options: lines)
    end

    private

    # ---- slot Q&A (collecting) -----------------------------------------------------------

    # purchase: name → amount → month → initial saved. savings_rate: just the monthly TOTAL
    # (the name defaults to the localized kind title at draft time — saves a question).
    def next_slot
      data = @conv.data
      return "kind" if data["kind"].blank?
      if data["kind"] == "purchase"
        return "name"          if data["name"].blank?
        return "amount"        if data["target_cents"].blank?
        return "month"         if data["target_month"].blank?
        return "initial_saved" unless data.key?("initial_saved_cents")
      else
        return "amount" if data["target_cents"].blank?
      end
      nil
    end

    def resolve_slot
      case @conv.data["pending_slot"]
      when "kind"          then resolve_kind
      when "name"          then resolve_name
      when "amount"        then resolve_amount
      when "month"         then resolve_month
      when "initial_saved" then resolve_initial_saved
      else ask_next
      end
    end

    def resolve_kind
      chosen = pick(kind_options) { |_kind, label| label }
      return re_ask("goal_flow.ask_kind", options: kind_prompt) unless chosen
      store("kind" => chosen.first)
    end

    def resolve_name
      name = @text.strip.first(80)   # goals.name caps at 80
      return re_ask("goal_flow.ask_name") if name.blank?
      store("name" => name)
    end

    def resolve_amount
      cents = Money.to_cents(@text)
      return re_ask("goal_flow.reask_amount") unless cents&.positive?
      store("target_cents" => cents)
    end

    def resolve_month
      date = GoalMonthPhrase.parse(@text, reference: sp_today)
      return re_ask("goal_flow.reask_month") unless date
      store("target_month" => date.iso8601)
    end

    def resolve_initial_saved
      cents = NONE_RE.match?(Whatsapp.normalize(@text)) ? 0 : Money.to_cents(@text)
      return re_ask("goal_flow.reask_initial_saved") if cents.nil? || cents.negative?
      # Mirrors Goal#initial_below_target — a purchase already fully saved isn't a goal.
      return re_ask("goal_flow.reask_initial_saved_high") if cents >= @conv.data["target_cents"].to_i
      store("initial_saved_cents" => cents)
    end

    def store(patch)
      @conv.update!(data: @conv.data.merge(patch))
      ask_next
    end

    def ask(slot)
      case slot
      when "kind"          then reply("goal_flow.ask_kind", options: kind_prompt)
      when "name"          then reply("goal_flow.ask_name")
      when "amount"        then ask_amount
      when "month"         then reply("goal_flow.ask_month")
      when "initial_saved" then reply("goal_flow.ask_initial_saved")
      end
    end

    # The savings question anchors on the LIVE guardado, exactly like GoalsController#new
    # (floored whole reais — never overstate a ledger figure, round 3 decision 1).
    def ask_amount
      return reply("goal_flow.ask_amount_purchase", name: @conv.data["name"]) if purchase?
      guardado = Goals::Analyzer.call(account).median_guardado_cents
      if guardado.positive?
        reply("goal_flow.ask_amount_savings", guardado: whole_floor(guardado))
      else
        reply("goal_flow.ask_amount_savings_zero")
      end
    end

    def kind_options
      I18n.with_locale(user.locale) do
        %w[purchase savings_rate].map { |k| [ k, I18n.t("goals.kinds.#{k}") ] }
      end
    end

    def kind_prompt
      kind_options.each_with_index.map { |(_, label), i| "#{i + 1}. #{label}" }.join("\n")
    end

    # ---- offer (slots complete) ------------------------------------------------------------

    def offer!
      goal = @conv.goal || build_draft
      return if goal.nil?   # the savings guard (or a seed conflict) re-asked a slot
      build = Goals::Recompute.call(goal)
      build.feasible? ? present_plan(goal, build) : counter_offer(goal, build)
    end

    # The REAL draft Goal, exactly like the web path: baseline analyzed in-job BEFORE save so
    # nothing races an empty snapshot. No NarrativeJob from WA — the offer speaks in the
    # deterministic plan numbers only (saves the AI session).
    def build_draft
      data = @conv.data
      goal = account.goals.new(
        name: data["name"].presence || default_name, kind: data["kind"],
        target_cents: data["target_cents"], initial_saved_cents: data["initial_saved_cents"].to_i,
        target_date: (Date.iso8601(data["target_month"]) if data["kind"] == "purchase"),
        status: "draft", created_by: user
      )
      goal.baseline = Goals::Analyzer.call(account).to_snapshot
      guardado = goal.baseline["median_guardado_cents"].to_i
      # Same guard as the web create: a "guardar mais" total at or below today's guardado
      # plans nothing — re-ask the amount instead of saving a doomed draft.
      if goal.savings_rate? && goal.target_cents.to_i <= guardado
        re_ask_slot("amount", "goal_flow.below_current_guardado", guardado: whole_floor(guardado))
        return nil
      end
      # The "já guardado" head start needs a home when a caixinha exists (decision 7);
      # re-pointed to the picked caixinha at accept time.
      goal.initial_saved_bank_account = caixinhas.first if goal.initial_saved_cents.positive?
      if goal.save
        @conv.update!(goal: goal)
        goal
      else
        # Only reachable combo: a seeded initial ≥ the target. Drop it and re-ask.
        @conv.update!(data: @conv.data.except("initial_saved_cents"))
        re_ask_slot("initial_saved", "goal_flow.reask_initial_saved_high")
        nil
      end
    end

    def default_name
      I18n.with_locale(user.locale) { I18n.t("goals.kinds.savings_rate") }
    end

    def present_plan(goal, build)
      plan = build.plans.find { |p| p.template == "recomendado" }
      @conv.update!(status: "offered", expires_at: GoalConversation::TTL.from_now)
      reply("goal_flow.offer", name: goal.name, monthly: whole_ceil(plan.monthly_target_cents),
            reaches_line: reaches_line(goal, plan), cuts_block: cuts_block(plan))
    end

    def reaches_line(goal, plan)
      return "" unless goal.purchase? && plan.projected_done_on
      t_locale("goal_flow.offer_reaches", month: month_label(plan.projected_done_on)) + "\n"
    end

    # Mirrors goals.plans.trim_line framing (whole reais, ceil — same as the web plan card).
    def cuts_block(plan)
      return t_locale("goal_flow.offer_no_cuts") + "\n" if plan.cuts.empty?
      lines = plan.cuts.map do |c|
        t_locale("goal_flow.offer_cut_line", amount: whole_ceil(c.cut_cents),
                 category: c.name, current: whole_ceil(c.baseline_cents))
      end
      t_locale("goal_flow.offer_cuts_title") + "\n" + lines.join("\n") + "\n"
    end

    # ONE honest counter-offer (goals.states.offer_* framing; FLOOR family — decision 1).
    # "sim" auto-applies it to the draft and re-presents the now-feasible plan.
    def counter_offer(goal, build)
      co = build.counter_offers
      if goal.purchase?
        achievable = Money.floor_to_real(co.achievable_monthly_cents).to_i
        return too_tight!(goal) if achievable <= 0 || co.feasible_date.nil?
        stash_counter("target_date" => co.feasible_date.iso8601)
        reply("goal_flow.counter_offer_date", amount: whole_floor(co.achievable_monthly_cents),
              month: month_label(co.feasible_date))
      else
        feasible = Money.floor_to_real(co.feasible_target_cents).to_i
        return too_tight!(goal) if feasible <= 0
        stash_counter("target_cents" => feasible)   # store the FLOORED figure shown
        reply("goal_flow.counter_offer_savings", amount: whole_floor(co.feasible_target_cents))
      end
    end

    def stash_counter(counter)
      @conv.update!(status: "offered", data: @conv.data.merge("counter" => counter),
                    expires_at: GoalConversation::TTL.from_now)
    end

    def too_tight!(goal)
      goal.destroy!
      close!
      reply("goal_flow.too_tight")
    end

    # ---- offered: sim / não ----------------------------------------------------------------

    def resolve_offer_reply
      norm = Whatsapp.normalize(@text)
      return decline! if NO_RE.match?(norm)
      return re_ask("goal_flow.offer_reprompt") unless YES_RE.match?(norm)
      counter = @conv.data["counter"]
      counter ? apply_counter(counter) : accept!
    end

    # "sim" on a counter-offer applies the feasible date/target and re-presents — one
    # round-trip, the user never restates a number.
    def apply_counter(counter)
      goal = @conv.goal
      if counter["target_date"]
        goal.update!(target_date: Date.iso8601(counter["target_date"]))
      else
        goal.update!(target_cents: counter["target_cents"])
      end
      @conv.update!(status: "collecting", data: @conv.data.except("counter"))
      offer!
    end

    def decline!
      discard_draft!
      close!
      reply("goal_flow.discarded")
    end

    # ---- accept: always-linked activation (decision 4) --------------------------------------

    def accept!
      list = caixinhas
      return block_no_caixinha! if list.empty?
      return with_caixinha(list.first.id) if list.size == 1
      moved = @conv.guarded_transition("offered", status: "picking_caixinha",
                data: @conv.data.merge("options" => list.map(&:id)),
                expires_at: GoalConversation::TTL.from_now)
      return unless moved
      reply("goal_flow.ask_caixinha_pick", options: numbered_options(list))
    end

    def resolve_caixinha_pick
      options = account.bank_accounts.kept.savings.in_order_of(:id, @conv.data["options"]).to_a
      chosen = pick(options) { |a| a.display_name }
      return re_ask("goal_flow.ask_caixinha_pick", options: numbered_options(options)) unless chosen
      with_caixinha(chosen.id)
    end

    def with_caixinha(caixinha_id)
      sources = source_accounts(caixinha_id)
      return block_no_caixinha! if sources.empty?   # no distinct source → same friendly block
      return activate!(caixinha_id, sources.first.id) if sources.size == 1
      moved = @conv.guarded_transition(%w[offered picking_caixinha], status: "picking_source",
                data: @conv.data.merge("caixinha_id" => caixinha_id, "options" => sources.map(&:id)),
                expires_at: GoalConversation::TTL.from_now)
      return unless moved
      reply("goal_flow.ask_source_pick", options: numbered_options(sources))
    end

    def resolve_source_pick
      options = account.bank_accounts.kept.in_order_of(:id, @conv.data["options"]).to_a
      chosen = pick(options) { |a| a.display_name }
      return re_ask("goal_flow.ask_source_pick", options: numbered_options(options)) unless chosen
      activate!(@conv.data["caixinha_id"], chosen.id)
    end

    def activate!(caixinha_id, source_id)
      goal = @conv.goal
      # The head start lives in the caixinha the goal links to (earmark consistency, P3).
      if goal.initial_saved_cents.positive? && goal.initial_saved_bank_account_id != caixinha_id
        goal.update!(initial_saved_bank_account_id: caixinha_id)
      end
      # Guarded close BEFORE Activate: a double "sim" matches zero rows and never runs
      # Activate twice (Activate's own draft guard is the second lock).
      return unless @conv.guarded_transition(%w[offered picking_caixinha picking_source], status: "closed")
      result = Goals::Activate.call(goal, template: "recomendado",
                                    bank_account_id: caixinha_id, source_bank_account_id: source_id)
      if result.ok?
        goal.reload
        reply("goal_flow.activated", name: goal.name, monthly: whole_ceil(goal.monthly_target_cents),
              month: month_label(goal.starts_on))
      else
        goal.destroy! if goal.reload.draft?   # an invisible draft leaks the AI-session quota
        key = result.error == :too_many_active ? "goal_flow.limit_reached" : "goal_flow.activation_failed"
        reply(key)
      end
    end

    def block_no_caixinha!
      discard_draft!
      close!
      reply("goal_flow.no_caixinha")
    end

    # ---- reorganizar (round 4) ---------------------------------------------------------------

    def resolve_replan_goal_pick
      options = account.goals.active.in_order_of(:id, @conv.data["options"]).to_a
      chosen = pick(options) { |g| g.name }
      return re_ask("goal_replan.pick", options: numbered_names(options)) unless chosen
      present_replan_offer(chosen)
    end

    # "1"/"2" picks an option ("sim" takes the first — it's the recommended one), "não" keeps
    # the plan as is. The guarded close makes a double reply apply exactly once.
    def resolve_replan_reply
      norm = Whatsapp.normalize(@text)
      if NO_RE.match?(norm)
        close!
        return reply("goal_replan.kept")
      end
      modes = Array(@conv.data["modes"])
      idx   = @text.strip[/\A\d+/]&.to_i
      mode  = (modes[idx - 1] if idx&.between?(1, modes.size))
      mode ||= modes.first if YES_RE.match?(norm)
      return re_ask("goal_replan.reprompt", options: @conv.data["option_lines"].to_s) unless mode
      goal = @conv.goal
      return unless @conv.guarded_transition("replan_offered", status: "closed")
      result = Goals::Replan.call(goal, mode: mode)
      if result.ok?
        goal.reload
        reply("goal_replan.applied", name: goal.name,
              monthly: whole_ceil(goal.monthly_target_cents), month: month_label(goal.target_date))
      else
        # The chat is already closed (double-reply protection), so "tenta de novo" would be a
        # dead end — the unavailable copy points to the app instead (review fix).
        reply("goal_replan.unavailable")
      end
    end

    def replan_option_lines(offer)
      offer.options.each_with_index.map { |option, index|
        key = option.mode == "extend" ? "goal_replan.option_extend" : "goal_replan.option_hold"
        "#{index + 1}. " + t_locale(key, monthly: whole_ceil(option.plan.monthly_target_cents),
                                    month: month_label(option.target_date))
      }.join("\n")
    end

    def numbered_names(records)
      records.each_with_index.map { |r, i| "#{i + 1}. #{r.name}" }.join("\n")
    end

    # ---- cancel / shared ---------------------------------------------------------------------

    def cancel!
      discard_draft!
      close!
      reply("goal_flow.cancelled")
    end

    def discard_draft!
      goal = @conv.goal
      goal.destroy! if goal&.draft?
    end

    def close! = @conv.update!(status: "closed")

    def purchase? = @conv.data["kind"] == "purchase"

    def caixinhas = account.bank_accounts.kept.savings.order(created_at: :asc).to_a

    # Any kept account distinct from the caixinha, mirroring the web source select
    # (Activate's whitelist is the backstop).
    def source_accounts(caixinha_id)
      account.bank_accounts.kept.where.not(id: caixinha_id).order(created_at: :asc).to_a
    end

    def re_ask_slot(slot, key, **args)
      @conv.update!(data: @conv.data.merge("pending_slot" => slot),
                    expires_at: GoalConversation::TTL.from_now)
      reply(key, **args)
    end

    def re_ask(key, **args)
      @conv.update!(expires_at: GoalConversation::TTL.from_now)
      reply(key, **args)
    end

    # Whole reais (round 3 decision 1): CEIL what the user is asked to save; FLOOR the
    # capacity/ledger family (pre-floored so the whole:true ceil is a no-op).
    def whole_ceil(cents)  = WhatsappReply.currency(cents, locale: user.locale, whole: true)
    def whole_floor(cents) = WhatsappReply.currency(Money.floor_to_real(cents), locale: user.locale, whole: true)

    def t_locale(key, **args) = I18n.with_locale(user.locale) { I18n.t("whatsapp.replies.#{key}", **args) }
  end
end
