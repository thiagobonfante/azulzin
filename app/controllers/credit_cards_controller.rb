# Add / list / remove credit cards. Mirrors BankAccountsController: used in the onboarding
# wizard (cards step) and afterwards from the sidebar ("Cartões").
class CreditCardsController < ApplicationController
  layout "app"
  before_action :require_onboarding, only: :index

  def index
    @credit_cards = Current.account.credit_cards.kept.includes(:institution).order(:created_at)
    @credit_card  = CreditCard.new
  end

  def create
    @credit_card = Current.account.credit_cards.build(credit_card_params)
    saved = @credit_card.save
    respond_to do |format|
      # 422 on failure so Turbo's submit-end reports failure and the form is NOT reset
      # (the create.turbo_stream branches on persisted? to append the row or show errors).
      format.turbo_stream { render :create, status: (saved ? :ok : :unprocessable_entity) }
      format.html do
        if saved
          redirect_to after_change_path, notice: t(".created")
        else
          redirect_to after_change_path, alert: @credit_card.errors.full_messages.to_sentence
        end
      end
    end
  end

  # Full-page edit — the first edit surface in the app; the billing config (R2) lives here.
  def edit
    @credit_card = Current.account.credit_cards.kept.find(params[:id])
  end

  # Saving a billing config re-buckets the card's history into real faturas (02 §3.2-5).
  def update
    @credit_card = Current.account.credit_cards.kept.find(params[:id])
    was_unconfigured = !@credit_card.billing_configured?
    if @credit_card.update(credit_card_params)
      if @credit_card.billing_configured? &&
         (@credit_card.saved_change_to_bill_due_day? || @credit_card.saved_change_to_closing_offset_days?)
        @credit_card.recompute_billing_months!(first_time: was_unconfigured)
      end
      redirect_to return_path, notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @credit_card = Current.account.credit_cards.kept.find(params[:id])
    @credit_card.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to after_change_path, notice: t(".removed") }
    end
  end

  private
    def credit_card_params
      params.expect(credit_card: %i[institution_id nickname last4 card_type credit_limit_reais
                                    current_bill_reais bill_due_day closing_offset_days])
    end

    def after_change_path
      Current.user.onboarded? ? credit_cards_path : onboarding_step_path("cards")
    end

    # Whitelisted return: the hub nudge passes the token "transactions" (never a URL, so no
    # open-redirect surface); anything else falls back to the cards page.
    def return_path
      params[:return_to] == "transactions" ? transactions_path(month: params[:month].presence) : credit_cards_path
    end
end
