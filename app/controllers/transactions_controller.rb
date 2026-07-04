# In-app pending inbox — the user-facing "fix-in-app" safety net for silent auto-commits
# (.plans/whats §5.8). Lists the user's rows that still need attention: needs_* / pending_review
# asks AND posted-but-unassigned expenses (auto-committed with no account picked). The user can
# assign an account/card, edit the amount/merchant, confirm a pending row, or reverse/discard.
# Chat and app are two front-ends over the same transactions row, so the same guarded
# transitions apply. Turbo-friendly: each action answers a turbo stream with an HTML fallback.
class TransactionsController < ApplicationController
  layout "app"
  before_action :require_onboarding, only: :index
  before_action :set_transaction, except: :index

  def index
    @transactions = Current.user.transactions.includes(:bank_account, :credit_card)
                           .pending_inbox.order(created_at: :desc)
  end

  # Edit amount / merchant.
  def update
    @saved = @transaction.update(transaction_params)
    respond_to do |format|
      format.turbo_stream { render :update, status: (@saved ? :ok : :unprocessable_entity) }
      format.html { redirect_back_to_inbox(@saved ? { notice: t(".updated") } : { alert: @transaction.errors.full_messages.to_sentence }) }
    end
  end

  # Pick (or clear) the account/card an expense is charged to.
  def assign
    if (record = resolve_instrument(params[:instrument]))
      @transaction.assign_instrument!(record)
    else
      @transaction.update!(bank_account: nil, credit_card: nil)   # explicit unassign
    end
    respond_to do |format|
      format.turbo_stream { render :row }
      format.html { redirect_back_to_inbox(notice: t(".assigned")) }
    end
  end

  # Confirm a pending / needs_* ask → posted. Guarded so a row the sweep already moved is a
  # silent no-op (never double-applies). See §5.4.
  def confirm
    @transaction.guarded_update(Transaction::PENDING_INBOX_STATUSES, status: "posted", confirmed_at: Time.current)
    respond_to do |format|
      format.turbo_stream { render :row }
      format.html { redirect_back_to_inbox(notice: t(".confirmed")) }
    end
  end

  # Reverse a posted expense / discard a pending one → rejected (excluded from spend).
  def destroy
    @transaction.reverse!
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back_to_inbox(notice: t(".removed")) }
    end
  end

  private
    def set_transaction
      @transaction = Current.user.transactions.find(params[:id])
    end

    def transaction_params
      params.expect(transaction: %i[amount_reais merchant])
    end

    def redirect_back_to_inbox(flash_opts)
      redirect_to transactions_path, **flash_opts
    end

    # Resolve a "bank_account-<id>" / "credit_card-<id>" token to the user's own record, or
    # nil (blank ⇒ unassign). Scoped to Current.user so one user can't charge another's
    # instrument.
    def resolve_instrument(token)
      type, id = token.to_s.split("-", 2)
      case type
      when "bank_account" then Current.user.bank_accounts.find_by(id: id)
      when "credit_card"  then Current.user.credit_cards.find_by(id: id)
      end
    end
end
