# Metas — financial goals (.plans/goals 02). draft → choose (recompute + guarded activate) → active.
# The engine does every number; this controller is thin: create the draft, analyze on view (so a
# freshly-added income re-scores the plans), and hand choose to Goals::Activate (tamper-proof —
# it recomputes from the frozen baseline and never trusts a plan number from params).
class GoalsController < AppController
  before_action :set_goal, only: %i[show update destroy choose abandon]

  def index
    @active = Current.account.goals.active.includes(:bank_account).order(created_at: :desc)
    @closed = Current.account.goals.where(status: %w[achieved abandoned]).order(created_at: :desc)
  end

  def new
    redirect_to goals_path, alert: t(".limit_reached") and return if at_active_cap?
    @goal = Current.account.goals.new(kind: "purchase")
  end

  def create
    @goal = Current.account.goals.new(create_params.merge(status: "draft"))
    if @goal.save
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
      @progress = Goals::Progress.new(@goal)
      render :show
    end
  end

  # Draft edit — counter-offer taps (new date / amount) and manual tweaks; re-scored on next view.
  def update
    if @goal.draft? && @goal.update(update_params)
      redirect_to goal_path(@goal)
    else
      redirect_to goal_path(@goal), alert: @goal.errors.full_messages.to_sentence.presence
    end
  end

  def choose
    analyze! if @goal.baseline["median_capacity_base_cents"].blank?
    result = Goals::Activate.call(@goal, template: params[:template],
                                  bank_account_id: params[:bank_account_id],
                                  source_bank_account_id: params[:source_bank_account_id])
    if result.ok?
      redirect_to goal_path(@goal), notice: t(".activated")
    else
      redirect_to goal_path(@goal), alert: t(".errors.#{result.error}")
    end
  end

  def abandon
    Goals::Abandon.call(@goal)
    redirect_to goals_path, notice: t(".abandoned"), status: :see_other
  end

  def destroy
    @goal.destroy! if @goal.draft?
    redirect_to goals_path, notice: t(".discarded"), status: :see_other
  end

  private
    def set_goal = @goal = Current.account.goals.find(params[:id])

    def at_active_cap? = Current.account.goals.active.count >= Goal::MAX_ACTIVE

    def analyze! = @goal.update!(baseline: Goals::Analyzer.call(Current.account).to_snapshot)

    def create_params
      params.expect(goal: %i[name kind target_reais target_date initial_saved_reais])
    end

    def update_params
      params.expect(goal: %i[target_reais target_date monthly_target_reais])
    end
end
