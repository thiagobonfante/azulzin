module Goals
  # One member's weekly goals sweep (.plans/goals 03, re-scoped by 06 §2). For each active goal:
  # auto-conclude if achieved (records goal_achieved), else compute the deterministic check, write
  # the idempotent goal_checks row (the dashboard widget reads it), and — only on an alert-worthy
  # moment (delta-gate + 14-day cooldown) — record a goal_alert. The dashboard banner always shows
  # (record! is unconditional); WhatsApp is opt-in and adds one more gate: goal_alert passes the
  # weekly-one-per-user guard then Notifications::Deliver (consent/channel/quiet-hours/daily-cap/
  # atomic-claim); goal_achieved delivers through Deliver too, exempt from the weekly guard.
  #
  # MUST share the "proactive_notify" concurrency group (key user_id) with reminders/budgets/
  # summaries so Deliver's daily-cap read-then-act stays race-free once Phase 3 turns the push on.
  class NotifyMemberJob < ApplicationJob
    queue_as :default

    limits_concurrency to: 1, group: "proactive_notify", key: ->(_account_id, user_id, *) { user_id }

    discard_on ActiveRecord::RecordNotFound

    COOLDOWN_DAYS = 14
    SEVERITY = { "on_track" => 0, "insufficient_data" => 0, "at_risk" => 1, "off_track" => 2 }.freeze
    # Worst first — the banner/message renders exactly ONE finding (the lead), so merged
    # findings are kept in this order (round 4 decision 1).
    FINDING_PRIORITY = %w[missed_month red_month next_month_red budget_raised pace big_purchase].freeze

    def perform(account_id, user_id, as_of = Date.current)
      @account = Account.find(account_id)
      @user    = User.find(user_id)
      return unless @user.account == @account          # membership revoked mid-flight

      @as_of = as_of.to_date
      week   = @as_of.beginning_of_week                # ISO Monday
      @risk  = Goals::RiskScan.call(@account, as_of: @as_of)

      @account.goals.active.find_each do |goal|
        if Goals::Progress.new(goal, as_of: @as_of).achieved?
          notify_all_members_of_achievement(goal, week) if Goals::Achieve.call(goal)
          next
        end
        check = upsert_check(goal, week, merged_result(goal))
        alert(goal, check, week) if check.status.in?(%w[at_risk off_track])
      end
    end

    private
      # The DB unique [goal_id, period_start] index is the referee: the first member's job computes
      # and writes; a later member's job for the same week loads the existing row (03 §2).
      def upsert_check(goal, week, result)
        @account.goal_checks.create!(goal: goal, period_start: week, status: result.status,
                                     expected_cents: result.expected_cents, actual_cents: result.actual_cents,
                                     findings: result.findings)
      rescue ActiveRecord::RecordNotUnique
        goal.checks.find_by!(period_start: week)
      end

      # Checker findings + RiskScan findings, worst first; risk findings escalate the status —
      # any risk ⇒ at least at_risk, a consummated miss or a red CURRENT month ⇒ off_track.
      # Risk findings deliberately ignore the activation grace (they're predictive protection,
      # not behavior judgment — round 4 decision 6).
      def merged_result(goal)
        base  = Goals::Checker.call(goal, as_of: @as_of)
        extra = @risk[goal.id]
        return base if extra.blank?
        findings = (base.findings + extra).sort_by { |f| FINDING_PRIORITY.index(f["finding"]) || FINDING_PRIORITY.size }
        off = base.status == "off_track" || findings.any? { |f| f["finding"].in?(%w[missed_month red_month]) }
        Goals::Checker::Result.new(status: off ? "off_track" : "at_risk", findings: findings,
                                   expected_cents: base.expected_cents, actual_cents: base.actual_cents)
      end

      # Delta-gate (worsened status OR a new (finding, category, month) cause) + 14-day cooldown
      # run BEFORE record! — a persistent, already-reported problem never re-fires. The lead
      # finding — the worst NEW cause — is the one the banner/message renders; urgent leads
      # (missed_month / red_month / next_month_red) bypass the cooldown, never the delta-gate,
      # the weekly WA guard or the spine's daily cap. Idempotent per (user, goal, week).
      def alert(goal, check, week)
        prev     = goal.checks.where(period_start: ...week).order(period_start: :desc).first
        new_keys = check.findings.map { |f| cause_key(f) } - previous_keys(prev)
        worsened = prev.nil? || SEVERITY.fetch(check.status) > SEVERITY.fetch(prev.status)
        return if new_keys.empty? && !worsened
        lead = check.findings.find { |f| new_keys.include?(cause_key(f)) } || check.findings.first
        return if in_cooldown?(goal) && !lead&.dig("urgent")
        notification = Notification.record!(user: @user, account: @account, kind: "goal_alert",
                                            subject: goal, period_key: week, payload: lead || {})
        return if goals_wa_sent_this_week?(week)   # ≤1 goals message/user/week — dashboard-only past that
        Notifications::Deliver.call(notification)
      end

      def cause_key(finding) = finding.values_at("finding", "category_id", "month")

      def previous_keys(prev) = (prev&.findings || []).map { |f| cause_key(f) }

      # Race-free under the shared "proactive_notify" concurrency group: the read-then-Deliver is
      # serialized per user, and Deliver stamps whatsapp_sent_at synchronously before the next goal.
      def goals_wa_sent_this_week?(week)
        Notification.where(user: @user, kind: "goal_alert")
                    .where.not(whatsapp_sent_at: nil)
                    .where(whatsapp_sent_at: week.beginning_of_day..).exists?
      end

      def in_cooldown?(goal)
        last = Notification.where(user: @user, kind: "goal_alert", subject: goal).order(created_at: :desc).first
        last && last.created_at.to_date > @as_of - COOLDOWN_DAYS
      end

      # The goal flips out of `active` here, so later members' jobs won't see it — the flipping job
      # notifies EVERY member (D8: household notifications reach every opted-in member). record! is
      # idempotent per (user, goal, period); Deliver respects each member's own consent.
      def notify_all_members_of_achievement(goal, week)
        payload = { "goal" => goal.name, "amount_cents" => goal.target_cents }
        @account.memberships.includes(:user).each do |membership|
          notification = Notification.record!(user: membership.user, account: @account,
                                              kind: "goal_achieved", subject: goal, period_key: week, payload: payload)
          Notifications::Deliver.call(notification)
        end
      end
  end
end
