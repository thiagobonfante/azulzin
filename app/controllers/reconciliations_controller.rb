# "Conferir com o banco" (.plans/credit-cards 03): upload → the shared import pipeline
# (purpose: reconciliation) → the deterministic diff review → apply. Two targets, one
# flow: a card bill (CardBillScope) or a bank extrato month (BankPeriodScope). The
# monthly AI cap (P0 #2: one per instrument per month) gates ONLY documents that need the
# LLM (PDF); CSV/OFX parse deterministically and ride free.
class ReconciliationsController < ApplicationController
  layout "app"
  before_action :require_onboarding

  def create
    target = find_target
    period = parse_period
    file   = params[:file]
    return redirect_to back_path(target, period), alert: t(".no_file") unless file.respond_to?(:tempfile)

    llm = needs_llm?(file)
    if llm && cap_consumed?(target)
      return redirect_to back_path(target, period),
                         alert: t(".monthly_cap", date: l(Date.current.next_month.beginning_of_month, format: :short))
    end

    checksum = Digest::SHA256.file(file.tempfile.path).hexdigest
    import = Current.account.document_imports.new(
      purpose: "reconciliation", period: period, checksum: checksum,
      source_format: ("pdf" if llm),   # stamped now so the cap can count LLM runs only
      credit_card:  (target if target.is_a?(CreditCard)),
      bank_account: (target if target.is_a?(BankAccount)))
    return redirect_to back_path(target, period), alert: t(".duplicate") if import.duplicate_checksum?

    import.file.attach(io: file, filename: file.original_filename, content_type: file.content_type)
    if import.save
      # Old query-only months materialize their bill row lazily (01 §2); idempotent.
      if target.is_a?(CreditCard) && period < target.current_open_bill_month
        CardBills::CloseScan.close(target, period)
      end
      ProcessDocumentImportJob.perform_later(import.id)
      redirect_to reconciliation_path(import)
    else
      redirect_to back_path(target, period), alert: import.errors.full_messages.to_sentence
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
      accepted: { create: Array(params[:create]), move: Array(params[:move]),
                  fix: Array(params[:fix]), sections: Array(params[:sections]) })
    counts = { created: result.created, moved: result.moved, fixed: result.fixed }
    notice = @import.bank_account_id ? t(".applied_bank", **counts) : t(".applied", **counts)
    redirect_to back_path(@import.credit_card || @import.bank_account, @import.period), notice: notice
  end

  private

  def find_target
    if params[:bank_account_id].present?
      Current.account.bank_accounts.kept.find(params[:bank_account_id])
    else
      Current.account.credit_cards.kept.find(params[:credit_card_id])
    end
  end

  def scope_for(import)
    if import.credit_card_id
      Reconciliation::CardBillScope.new(credit_card: import.credit_card, month: import.period)
    else
      Reconciliation::BankPeriodScope.new(bank_account: import.bank_account, month: import.period)
    end
  end

  # Card: the bill page when the row exists, else the cards page. Bank: the accounts page.
  def back_path(target, period)
    return bank_accounts_path if target.is_a?(BankAccount)
    bill = target && period ? target.card_bills.find_by(billing_month: period) : nil
    bill ? card_bill_path(bill) : credit_cards_path
  end

  # Accepts a full ISO date or the month input's "YYYY-MM".
  def parse_period
    raw = params[:period].to_s
    date = begin
      Date.iso8601(raw)
    rescue Date::Error
      begin
        Date.strptime(raw, "%Y-%m")
      rescue ArgumentError
        Date.current
      end
    end
    date.beginning_of_month
  end

  # P0 #2: one LLM reconciliation per instrument per month; failed/dismissed runs never
  # consume the slot, and CSV/OFX runs (no LLM) never count against it.
  def cap_consumed?(target)
    column = target.is_a?(CreditCard) ? :credit_card_id : :bank_account_id
    Current.account.document_imports.reconciliation.format_pdf
           .where(column => target.id, created_at: Time.current.all_month)
           .where.not(status: %w[failed dismissed]).exists?
  end

  def needs_llm?(file)
    head = file.tempfile.read(4096)
    file.tempfile.rewind
    Imports::FormatDetector.call(head, filename: file.original_filename) == "pdf"
  end
end
