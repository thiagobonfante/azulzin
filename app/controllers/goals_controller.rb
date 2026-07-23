# Metas — financial goals (.plans/goals 02). draft → choose (recompute + guarded activate) → active.
# The engine does every number; this controller is thin: create the draft, analyze on view (so a
# freshly-added income re-scores the plans), and hand choose to Goals::Activate (tamper-proof —
# it recomputes from the frozen baseline and never trusts a plan number from params).
class GoalsController < AppController
  before_action :set_goal, only: %i[show update destroy choose abandon caps contribute replan]

  def index
    @active = Current.account.goals.active.includes(:bank_account).order(created_at: :desc)
    @closed = Current.account.goals.where(status: %w[achieved abandoned]).order(created_at: :desc)
  end

  def new
    redirect_to goals_path, alert: t(".limit_reached") and return if at_active_cap?
    @goal = Current.account.goals.new(kind: "purchase")
    @saved_baseline_cents = Goals::Analyzer.call(Current.account).median_saved_cents
  end

  # The baseline is analyzed IN-REQUEST here (not lazily on first view) so the NarrativeJob —
  # which fires milliseconds later on the async adapter — never races an empty snapshot.
  def create
    @goal = Current.account.goals.new(create_params.merge(status: "draft"))
    @goal.baseline = Goals::Analyzer.call(Current.account).to_snapshot
    @saved_baseline_cents = @goal.baseline["median_guardado_cents"].to_i
    if @goal.valid? && savings_target_not_above_saved_baseline?
      @goal.errors.add(:target_cents, :below_current_guardado, saved: helpers.brl_whole(@saved_baseline_cents, mode: :floor))
      render :new, status: :unprocessable_entity
    elsif @goal.save
      Goals::ClassifyJob.perform_later(Current.account.id)             # exempt from the session quota
      Goals::NarrativeJob.perform_later(@goal.id) if ai_sessions_available?
      redirect_to goal_path(@goal)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    if @goal.draft?
      analyze!                                  # re-score on every draft view (handles income-return)
      @build = Goals::Recompute.call(@goal)
      render :draft
    else
      Goals::Achieve.call(@goal) if Goals::Progress.new(@goal).achieved?   # auto-conclude on render
      # One-shot celebration (ADR 0012): the first achieved render fires the party and stamps
      # celebrated_at — guarded flip, same idiom as Achieve, so it never re-fires.
      @celebrate = @goal.achieved? &&
                   Goal.where(id: @goal.id, celebrated_at: nil)
                       .update_all(celebrated_at: Time.current, updated_at: Time.current).positive?
      @progress = Goals::Progress.new(@goal)
      @speed_up = Goals::SpeedUpOffer.for(@goal)
      @replan_offer = Goals::ReplanOffer.for(@goal)   # nil unless active purchase with a way out
      render :show
    end
  end

  # Reorganizar (round 4): rewrite the plan on today's numbers — the option is re-derived
  # inside Goals::Replan (never a number from params; only the mode word crosses the wire).
  def replan
    result = Goals::Replan.call(@goal, mode: params[:mode])
    if result.ok?
      redirect_to goal_path(@goal), notice: t(".replanned",
        monthly: helpers.brl_whole(@goal.monthly_target_cents),
        month: l(@goal.target_date, format: :month_year))
    else
      redirect_to goal_path(@goal, anchor: "replan"), alert: t(".errors.#{result.error}")
    end
  end

  # Speed-up (round 3 decision 6): an extra transfer into the caixinha, bounded by this month's
  # sobra. The offer is RE-DERIVED here — the render-time sobra is never trusted at POST time.
  def contribute
    offer = Goals::SpeedUpOffer.for(@goal)
    cents = Money.to_cents(params[:amount_reais])
    if offer && cents.to_i.positive? && cents <= offer.sobra_cents
      Current.account.transactions.create!(
        direction: "transfer", status: "posted", confirmed_at: Time.current, source: "manual",
        amount_cents: cents, occurred_on: sp_today,
        bank_account_id: offer.source_bank_account_id,
        transfer_to_bank_account_id: offer.destination_bank_account_id
      )
      # No commitment_id: a second payment row for the month would trip the paid-once index.
      projected = Goals::Progress.new(@goal).projected_done_on
      redirect_to goal_path(@goal), notice: t(".contributed", month: l(projected, format: :month_year))
    else
      redirect_to goal_path(@goal), alert: t(".rejected")
    end
  end

  # Draft edit — counter-offer taps (new date / amount) and manual tweaks; re-scored on next view.
  def update
    if @goal.draft? && @goal.update(update_params)
      Goals::NarrativeJob.perform_later(@goal.id) if ai_sessions_available?   # re-narrate the new plans (call cap guards)
      redirect_to goal_path(@goal)
    else
      redirect_to goal_path(@goal), alert: @goal.errors.full_messages.to_sentence.presence
    end
  end

  def choose
    analyze! if @goal.baseline["median_capacity_base_cents"].blank?
    result = Goals::Activate.call(@goal, template: params[:template],
                                  bank_account_id: params[:bank_account_id],
                                  source_bank_account_id: params[:source_bank_account_id],
                                  created_by: Current.user)
    if result.ok?
      redirect_to goal_path(@goal), notice: t(".activated")
    else
      redirect_to goal_path(@goal), alert: t(".errors.#{result.error}")
    end
  end

  # Diagnóstico orçamento sliders (draft only): store the caps, recompute, and Turbo-swap just the
  # plan area — the sliders themselves stay live in the DOM so a drag never loses its position.
  def caps
    redirect_to goal_path(@goal), status: :see_other and return unless @goal.draft?
    @goal.update!(user_caps: sanitized_caps)
    @build = Goals::Recompute.call(@goal)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to goal_path(@goal), status: :see_other }
    end
  end

  def abandon
    if Goals::Abandon.call(@goal)
      redirect_to goals_path, notice: t(".abandoned"), status: :see_other
    else
      # Achieved/closed goals can't be abandoned (Abandon's guard) — the UI hides the button,
      # so this is the raw-request path; never flash success over a no-op.
      redirect_to goal_path(@goal), alert: t(".errors.not_active"), status: :see_other
    end
  end

  def destroy
    @goal.destroy! if @goal.draft?
    redirect_to goals_path, notice: t(".discarded"), status: :see_other
  end

  private
    def set_goal = @goal = Current.account.goals.find(params[:id])

    def at_active_cap? = Current.account.goals.active.count >= Goal::MAX_ACTIVE

    def sp_today = Date.current.in_time_zone(Goals::TZ).to_date

    # Re-score on view, but keep any async coach narratives (they're keyed by template, stable).
    def analyze!
      snapshot = Goals::Analyzer.call(Current.account).to_snapshot
      snapshot["narratives"] = @goal.baseline["narratives"] if @goal.baseline["narratives"].present?
      @goal.update!(baseline: snapshot)
    end

    # ≤5 AI-assisted sessions/account/billing-month (07 §2) — a draft created this month IS a session.
    def ai_sessions_available?
      month_start = Date.current.in_time_zone(Goals::TZ).beginning_of_month
      Current.account.goals.where(created_at: month_start..).count <= Goals::MAX_AI_SESSIONS_PER_MONTH
    end

    # Normalizes kind-inapplicable fields the browser always submits (round 3 P1): the date
    # select has include_blank:false so even a no-JS savings_rate submission carries one, and
    # a blank "já guardado" must keep the DB default 0 (dropped, never assigned — the _reais=
    # setter would write nil cents and trip numericality on this NOT NULL column).
    def create_params
      p = params.expect(goal: %i[name kind target_reais target_date initial_saved_reais initial_saved_bank_account_id])
      p = p.except(:target_date, :initial_saved_reais, :initial_saved_bank_account_id) if p[:kind] == "savings_rate"
      p.delete(:initial_saved_reais) if p[:initial_saved_reais].blank?
      p.delete(:initial_saved_bank_account_id) if p[:initial_saved_bank_account_id].blank?
      p
    end

    def update_params
      params.expect(goal: %i[target_reais target_date monthly_target_reais])
    end

    # A "guardar mais" total at or below what the household already puts away plans nothing.
    def savings_target_not_above_saved_baseline?
      @goal.savings_rate? && @goal.target_cents.to_i <= @saved_baseline_cents
    end

    # Slider caps come as { category_id => cents }. Only the frozen baseline's flexible categories
    # are read (anything else in params is simply never looked at), values are clamped to
    # [median − trimmable, median], and no-op caps (== median) are dropped. `reset` clears everything.
    def sanitized_caps
      return {} if params[:reset].present?
      flexibles = (@goal.baseline["categories"] || [])
                    .select { |c| c["flexibility"] == "flexible" && c["trimmable_median_cents"].to_i.positive? }
      flexibles.each_with_object({}) do |cat, caps|
        cid = cat["category_id"].to_s
        cents = Integer(params.dig(:caps, cid).to_s, exception: false) or next
        median = cat["median_cents"].to_i
        cap = cents.clamp(median - cat["trimmable_median_cents"].to_i, median)
        caps[cid] = cap if cap < median
      end
    end
end
