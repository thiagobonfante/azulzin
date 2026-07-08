# Recurring incomes (R1). Serves both the onboarding "incomes" step and the post-onboarding
# management page (after_change_path branches on onboarded?), mirroring BankAccountsController.
# create/destroy only (v1) — an income raise is remove + re-add, parity with accounts/cards.
class IncomesController < ApplicationController
  layout "app"
  before_action :require_onboarding, only: %i[index receive]
  helper_method :viewed_month, :summary, :month_ledger

  def index
    @incomes = Current.account.incomes.kept.active.includes(:bank_account).order(:created_at)
    @income  = Income.new
  end

  def create
    @income = Current.account.incomes.build(sanitized_income_params)
    saved = @income.save
    respond_to do |format|
      format.turbo_stream { render :create, status: (saved ? :ok : :unprocessable_entity) }
      format.html do
        redirect_to after_change_path, notice: (saved ? t(".created") : nil),
                    alert: (saved ? nil : @income.errors.full_messages.to_sentence)
      end
    end
  end

  # Full-page edit — name, amount, destination account and schedule.
  def edit
    @income = Current.account.incomes.kept.find(params[:id])
  end

  def update
    @income = Current.account.incomes.kept.find(params[:id])
    if @income.update(sanitized_income_params)
      redirect_to incomes_path, notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @income = Current.account.incomes.kept.find(params[:id])
    @income.soft_delete!(by: Current.user)   # receipts keep income_id
    # Remove lives on the edit page (not the list rows), so a redirect is the only response.
    redirect_to after_change_path, notice: t(".removed"), status: :see_other
  end

  # Hub card "A receber no mês": mark this month's expected deposit received — one posted
  # income transaction (income_id link), so it joins the account balance and the entradas.
  def receive
    @income = Current.account.incomes.kept.active.find(params[:id])
    Incomes::MarkReceived.call(@income, viewed_month) unless summary.income_received?(@income)
    @summary = MonthSummary.new(Current.account, viewed_month)   # rebuild: the receipt changes the figures
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to transactions_path(month: viewed_month.strftime("%Y-%m")), notice: t(".received") }
    end
  end

  private
    def income_params
      params.expect(income: %i[name amount_reais bank_account_id schedule_kind schedule_day])
    end

    # Reject a forged bank_account_id pointing at another user's account (belongs_to then fails).
    def sanitized_income_params
      attrs = income_params.to_h
      if attrs["bank_account_id"].present? && !Current.account.bank_accounts.kept.exists?(attrs["bank_account_id"])
        attrs["bank_account_id"] = nil
      end
      attrs
    end

    def after_change_path
      Current.user.onboarded? ? incomes_path : onboarding_step_path("incomes")
    end

    # Hub-month plumbing for receive's turbo_stream — mirrors CommitmentOccurrencesController.
    def viewed_month
      @viewed_month ||= (parse_month(params[:month]) || Date.current.in_time_zone("America/Sao_Paulo").to_date.beginning_of_month)
    end

    def summary = @summary ||= MonthSummary.new(Current.account, viewed_month)

    def month_ledger
      Current.account.transactions.posted_in(viewed_month)
             .includes(:bank_account, :credit_card, :category, :transfer_to_bank_account, :commitment)
             .order(occurred_on: :desc, id: :desc)
    end

    def parse_month(param)
      return nil unless param.to_s.match?(/\A\d{4}-(0[1-9]|1[0-2])\z/)
      Date.strptime(param, "%Y-%m").beginning_of_month
    rescue ArgumentError
      nil
    end
end
