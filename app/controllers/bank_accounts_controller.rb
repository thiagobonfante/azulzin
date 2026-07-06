# Add / list / remove bank accounts. Used both inside the onboarding wizard (accounts
# step) and afterwards from the sidebar ("Contas"). Create/destroy answer Turbo Streams
# so the list updates in place, with an HTML redirect fallback for no-JS.
class BankAccountsController < ApplicationController
  layout "app"
  before_action :require_onboarding, only: :index

  def index
    @bank_accounts = Current.account.bank_accounts.kept.includes(:institution).order(:created_at)
    @bank_account  = BankAccount.new
  end

  def create
    @bank_account = Current.account.bank_accounts.build(bank_account_params)
    saved = @bank_account.save
    respond_to do |format|
      # 422 on failure so Turbo's submit-end reports failure and the form is NOT reset
      # (the create.turbo_stream branches on persisted? to append the row or show errors).
      format.turbo_stream { render :create, status: (saved ? :ok : :unprocessable_entity) }
      format.html do
        if saved
          redirect_to after_change_path, notice: t(".created")
        else
          redirect_to after_change_path, alert: @bank_account.errors.full_messages.to_sentence
        end
      end
    end
  end

  # Full-page edit — nickname, kind and balance. Editing the balance re-anchors it (model).
  def edit
    @bank_account = Current.account.bank_accounts.kept.find(params[:id])
  end

  def update
    @bank_account = Current.account.bank_accounts.kept.find(params[:id])
    if @bank_account.update(bank_account_params)
      redirect_to bank_accounts_path, notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @bank_account = Current.account.bank_accounts.kept.find(params[:id])
    @bank_account.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to after_change_path, notice: t(".removed") }
    end
  end

  private
    def bank_account_params
      params.expect(bank_account: %i[institution_id nickname agency account_number balance_reais kind])
    end

    # Where the no-JS fallback lands: back to the wizard step mid-onboarding, else the
    # management list.
    def after_change_path
      Current.user.onboarded? ? bank_accounts_path : onboarding_step_path("accounts")
    end
end
