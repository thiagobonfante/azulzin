# Add / list / remove bank accounts. Used both inside the onboarding wizard (accounts
# step) and afterwards from the sidebar ("Contas"). Create/destroy answer Turbo Streams
# so the list updates in place, with an HTML redirect fallback for no-JS.
class BankAccountsController < ApplicationController
  layout "app"
  before_action :require_onboarding, only: :index

  def index
    @bank_accounts = Current.user.bank_accounts.includes(:institution).order(:created_at)
    @bank_account  = BankAccount.new
  end

  def create
    @bank_account = Current.user.bank_accounts.build(bank_account_params)
    @bank_account.save
    respond_to do |format|
      format.turbo_stream          # create.turbo_stream.erb branches on persisted?
      format.html do
        if @bank_account.persisted?
          redirect_to after_change_path, notice: t(".created")
        else
          redirect_to after_change_path, alert: @bank_account.errors.full_messages.to_sentence
        end
      end
    end
  end

  def destroy
    @bank_account = Current.user.bank_accounts.find(params[:id])
    @bank_account.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to after_change_path, notice: t(".removed") }
    end
  end

  private
    def bank_account_params
      params.expect(bank_account: %i[institution_id nickname agency account_number balance_reais])
    end

    # Where the no-JS fallback lands: back to the wizard step mid-onboarding, else the
    # management list.
    def after_change_path
      Current.user.onboarded? ? bank_accounts_path : onboarding_step_path("accounts")
    end
end
