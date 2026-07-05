# Recurring incomes (R1). Serves both the onboarding "incomes" step and the post-onboarding
# management page (after_change_path branches on onboarded?), mirroring BankAccountsController.
# create/destroy only (v1) — an income raise is remove + re-add, parity with accounts/cards.
class IncomesController < ApplicationController
  layout "app"
  before_action :require_onboarding, only: :index

  def index
    @incomes = Current.user.incomes.active.includes(:bank_account).order(:created_at)
    @income  = Income.new
  end

  def create
    attrs = income_params.to_h
    # Reject a forged bank_account_id pointing at another user's account (belongs_to then fails).
    if attrs["bank_account_id"].present? && !Current.user.bank_accounts.exists?(attrs["bank_account_id"])
      attrs["bank_account_id"] = nil
    end
    @income = Current.user.incomes.build(attrs)
    saved = @income.save
    respond_to do |format|
      format.turbo_stream { render :create, status: (saved ? :ok : :unprocessable_entity) }
      format.html do
        redirect_to after_change_path, notice: (saved ? t(".created") : nil),
                    alert: (saved ? nil : @income.errors.full_messages.to_sentence)
      end
    end
  end

  def destroy
    @income = Current.user.incomes.find(params[:id])
    @income.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to after_change_path, notice: t(".removed") }
    end
  end

  private
    def income_params
      params.expect(income: %i[name amount_reais bank_account_id schedule_kind schedule_day])
    end

    def after_change_path
      Current.user.onboarded? ? incomes_path : onboarding_step_path("incomes")
    end
end
