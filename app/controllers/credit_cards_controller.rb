# Add / list / remove credit cards. Mirrors BankAccountsController: used in the onboarding
# wizard (cards step) and afterwards from the sidebar ("Cartões").
class CreditCardsController < ApplicationController
  layout "app"
  before_action :require_onboarding, only: :index

  def index
    @credit_cards = Current.account.credit_cards.kept.roots.includes(:institution).order(:created_at)
    # Lazy close (.plans/credit-cards 01 §2): arriving minutes after closing, before the
    # daily scan, still shows a payable bill — same code path, second trigger.
    @credit_cards.each { |card| CardBills::CloseScan.ensure_for(card) }
    @credit_card  = CreditCard.new
  end

  def create
    @credit_card = Current.account.credit_cards.build(credit_card_params)
    saved = @credit_card.save
    # First card ever auto-becomes its creator's default (04 §5 — zero-setup common case).
    if saved && Current.user.default_credit_card.nil? && Current.account.credit_cards.kept.count == 1
      Current.user.update!(default_credit_card_id: @credit_card.id)
    end
    respond_to do |format|
      # 422 on failure so Turbo's submit-end reports failure and the form is NOT reset
      # (the create.turbo_stream branches on persisted? to append the row or show errors).
      format.turbo_stream { render :create, status: (saved ? :ok : :unprocessable_entity) }
      format.html do
        # A sub-card is created FROM its root's edit page — land back there (banner on
        # top), never on the cards index (founder round 2026-07-22).
        parent_id = @credit_card.parent_card_id || params.dig(:credit_card, :parent_card_id).presence
        back = parent_id ? edit_credit_card_path(parent_id) : after_change_path
        if saved
          redirect_to back, notice: t(".created")
        else
          redirect_to back, alert: @credit_card.errors.full_messages.to_sentence
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
      recede_or_redirect_to return_path, notice: t(".updated")   # closes the native edit modal
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @credit_card = Current.account.credit_cards.kept.find(params[:id])
    # A root with kept sub-cards refuses (04 §1) — orphan sub-cards are meaningless.
    if @credit_card.soft_delete!(by: Current.user)
      recede_or_redirect_to after_change_path, notice: t(".removed"), status: :see_other
    else
      recede_or_redirect_to after_change_path, alert: @credit_card.errors.full_messages.to_sentence, status: :see_other
    end
  end

  # The per-member default plastic (04 §5): a star on the cards page, root or sub-card.
  # Turbo swaps ONLY the two affected stars — a full redirect would collapse the sub-cards
  # expansion the tap came from (founder complaint, 2026-07-22). HTML stays the fallback.
  def make_default
    card = Current.account.credit_cards.kept.find(params[:id])
    previous = Current.user.default_credit_card
    Current.user.update!(default_credit_card_id: card.id)
    respond_to do |format|
      format.turbo_stream { @stars = [ previous, card ].compact.uniq }
      format.html { redirect_to credit_cards_path, notice: t(".set", card: card.display_name) }
    end
  end

  # Closed-faturas history for a ROOT card (founder ask, 2026-07-22): every bill, its
  # status and what was paid, newest first — each row links to the bill page (where Pagar
  # lives). Sub-cards have no bills (04 §1), so they get no history.
  def bills
    @credit_card = Current.account.credit_cards.kept.roots.find(params[:id])
    CardBills::CloseScan.ensure_for(@credit_card)   # same lazy-close as the index
    @bills = @credit_card.card_bills.order(billing_month: :desc)
  end

  private
    def credit_card_params
      params.expect(credit_card: %i[institution_id nickname last4 card_type credit_limit_reais
                                    current_bill_reais bill_due_day closing_offset_days parent_card_id])
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
