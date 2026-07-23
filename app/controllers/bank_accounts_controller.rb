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
    # Blank balance = the account starts empty. Anchors 0 at creation so every movement
    # from here on counts — a nil balance would ignore transfers until one was informed.
    @bank_account.balance_cents ||= 0
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
      # Native shells present /edit as a modal (path configuration) — recede closes it;
      # web behavior is the plain redirect, unchanged. Same on the sibling controllers.
      recede_or_redirect_to bank_accounts_path, notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Ajustar saldo (edit page): the informed "saldo de hoje" becomes a LEDGER row for the
  # delta against the derived balance — visible in the ledger and deletable, which is the
  # rollback (soft-deleting the row unspends it, so the derived balance reverts). Never a
  # silent re-anchor. First-ever balance (none informed yet) anchors instead — there is no
  # delta against nothing.
  def adjust_balance
    @bank_account = Current.account.bank_accounts.kept.find(params[:id])
    target = Money.to_cents(params[:balance_reais])
    if target.nil?
      redirect_to edit_bank_account_path(@bank_account), alert: t("bank_accounts.adjust.invalid")
    elsif !@bank_account.balance_informed?
      @bank_account.update!(balance_cents: target)
      redirect_to edit_bank_account_path(@bank_account), notice: t("bank_accounts.update.updated")
    elsif (delta = target - @bank_account.derived_balance_cents).zero?
      redirect_to edit_bank_account_path(@bank_account), notice: t("bank_accounts.adjust.no_change")
    else
      Current.account.transactions.create!(
        created_by: Current.user, bank_account: @bank_account,
        merchant: t("bank_accounts.adjust.transaction_merchant"),
        direction: (delta.positive? ? "income" : "expense"),
        status: "posted", confirmed_at: Time.current, source: "manual",
        amount_cents: delta.abs, occurred_on: Date.current)
      signed = "#{delta.positive? ? "+" : "−"}#{helpers.brl(delta.abs)}"
      redirect_to edit_bank_account_path(@bank_account), notice: t("bank_accounts.adjust.adjusted", amount: signed)
    end
  end

  def destroy
    @bank_account = Current.account.bank_accounts.kept.find(params[:id])
    if @bank_account.soft_delete!(by: Current.user)   # restrict mirror: false while a kept income depends on it
      # Remove lives on the edit page (not the list rows), so a redirect is the only response.
      recede_or_redirect_to after_change_path, notice: t(".removed"), status: :see_other
    else
      redirect_to after_change_path, alert: @bank_account.errors.full_messages.to_sentence, status: :see_other
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
