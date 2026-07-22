# "Conferir com o banco" for a card bill (.plans/credit-cards 03): upload → the shared
# import pipeline (purpose: reconciliation) → the deterministic diff review → apply.
# The monthly AI cap (P0 #2: one per instrument per month) gates ONLY documents that need
# the LLM (PDF); CSV/OFX parse deterministically and ride free.
class ReconciliationsController < ApplicationController
  layout "app"
  before_action :require_onboarding

  def create
    card   = Current.account.credit_cards.kept.find(params[:credit_card_id])
    period = parse_period
    file   = params[:file]
    return redirect_to back_path(card, period), alert: t(".no_file") unless file.respond_to?(:tempfile)

    if needs_llm?(file) && cap_consumed?(card)
      return redirect_to back_path(card, period),
                         alert: t(".monthly_cap", date: l(Date.current.next_month.beginning_of_month, format: :short))
    end

    checksum = Digest::SHA256.file(file.tempfile.path).hexdigest
    import = Current.account.document_imports.new(
      purpose: "reconciliation", credit_card: card, period: period, checksum: checksum)
    return redirect_to back_path(card, period), alert: t(".duplicate") if import.duplicate_checksum?

    import.file.attach(io: file, filename: file.original_filename, content_type: file.content_type)
    if import.save
      # Old query-only months materialize their bill row lazily (01 §2); idempotent.
      CardBills::CloseScan.close(card, period) if period < card.current_open_bill_month
      ProcessDocumentImportJob.perform_later(import.id)
      redirect_to reconciliation_path(import)
    else
      redirect_to back_path(card, period), alert: import.errors.full_messages.to_sentence
    end
  end

  def show
    @import = Current.account.document_imports.reconciliation.find(params[:id])
    return unless @import.extracted?
    @scope = scope_for(@import)
    @diff  = Reconciliation::Diff.call(rows: Reconciliation.rows_from_extraction(@import.extraction),
                                       scope: @scope)
  end

  # Only what the user accepted is applied; the diff re-runs against live data inside.
  def apply
    @import = Current.account.document_imports.reconciliation.find(params[:id])
    return redirect_to reconciliation_path(@import) unless @import.extracted?

    result = Reconciliation::Apply.call(
      import: @import, scope: scope_for(@import), created_by: Current.user,
      accepted: { create: Array(params[:create]), move: Array(params[:move]), fix: Array(params[:fix]) })
    redirect_to back_path(@import.credit_card, @import.period),
                notice: t(".applied", created: result.created, moved: result.moved, fixed: result.fixed)
  end

  private

  def scope_for(import)
    Reconciliation::CardBillScope.new(credit_card: import.credit_card, month: import.period)
  end

  # The bill page when the row exists (the usual case), else the cards page.
  def back_path(card, period)
    bill = card && period ? card.card_bills.find_by(billing_month: period) : nil
    bill ? card_bill_path(bill) : credit_cards_path
  end

  def parse_period
    Date.iso8601(params[:period].to_s).beginning_of_month
  rescue Date::Error
    Date.current.beginning_of_month
  end

  # P0 #2: one LLM reconciliation per instrument per month; failed/dismissed runs never
  # consume the slot.
  def cap_consumed?(card)
    Current.account.document_imports.reconciliation
           .where(credit_card_id: card.id, created_at: Time.current.all_month)
           .where.not(status: %w[failed dismissed]).exists?
  end

  def needs_llm?(file)
    head = file.tempfile.read(4096)
    file.tempfile.rewind
    Imports::FormatDetector.call(head, filename: file.original_filename) == "pdf"
  end
end
