# Add / list / remove credit cards. Mirrors BankAccountsController: used in the onboarding
# wizard (cards step) and afterwards from the sidebar ("Cartões").
class CreditCardsController < ApplicationController
  layout "app"
  before_action :require_onboarding, only: :index

  def index
    @credit_cards = Current.user.credit_cards.includes(:institution).order(:created_at)
    @credit_card  = CreditCard.new
  end

  def create
    @credit_card = Current.user.credit_cards.build(credit_card_params)
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

  def destroy
    @credit_card = Current.user.credit_cards.find(params[:id])
    @credit_card.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to after_change_path, notice: t(".removed") }
    end
  end

  private
    def credit_card_params
      params.expect(credit_card: %i[institution_id nickname credit_limit_reais current_bill_reais])
    end

    def after_change_path
      Current.user.onboarded? ? credit_cards_path : onboarding_step_path("cards")
    end
end
