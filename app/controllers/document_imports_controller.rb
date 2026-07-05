# Upload extratos/faturas (.plans/auto). Reachable DURING onboarding (accounts step) and after
# it (accounts index) — like BankAccountsController, so `create` is not gated on onboarding.
# There is no index/show and no route that serves the raw blob back: files go in, only derived
# data (proposals) comes out.
class DocumentImportsController < ApplicationController
  layout "app"

  def create
    files = Array(upload_params[:files]).select { it.respond_to?(:tempfile) }
    return redirect_to(after_upload_path, alert: t(".no_files")) if files.empty?

    if over_daily_cap?(files.size)
      return redirect_to(after_upload_path, alert: t(".daily_cap", max: DocumentImport::MAX_PER_DAY))
    end

    flash_ingest_results(files.map { |f| ingest(f) })
    redirect_to after_upload_path
  end

  # "Remover"/"Descartar" a non-applied import: mark dismissed and purge the blob immediately.
  def destroy
    import = Current.user.document_imports.find(params[:id])
    import.file.purge_later if import.file.attached?
    import.update!(status: "dismissed")
    redirect_to after_upload_path
  end

  # Turbo Frame polled by import_status_controller every 2s.
  def status
    imports = Current.user.document_imports.where.not(status: "dismissed").order(created_at: :desc)
    render partial: "document_imports/status", locals: { imports: imports }
  end

  private

  def upload_params
    params.expect(document_import: [ files: [] ])
  end

  # One uploaded file → one DocumentImport. Checksum BEFORE attach so a duplicate never even
  # writes a blob to disk. The partial unique index is the race backstop. (No processing job
  # yet — that arrives with Phase 1.)
  def ingest(uploaded)
    checksum = Digest::SHA256.file(uploaded.tempfile.path).hexdigest
    import = Current.user.document_imports.new(checksum: checksum)
    return [ :duplicate, import ] if import.duplicate_checksum?

    import.file.attach(io: uploaded, filename: uploaded.original_filename,
                       content_type: uploaded.content_type)
    import.save ? [ :created, import ] : [ :invalid, import ]
  rescue ActiveRecord::RecordNotUnique
    [ :duplicate, import ]
  end

  def over_daily_cap?(incoming)
    Current.user.document_imports.where(created_at: 24.hours.ago..).count + incoming >
      DocumentImport::MAX_PER_DAY
  end

  # Rejected files (dup, too large, wrong type) become one friendly alert; successes are silent —
  # the status frame is the feedback.
  def flash_ingest_results(results)
    rejected = results.reject { it.first == :created }
    return if rejected.empty?

    messages = rejected.map do |reason, import|
      if reason == :duplicate
        t("document_imports.errors.duplicate_file")
      else
        t("document_imports.upload_rejected",
          filename: import.file.filename.to_s.presence || t("document_imports.upload.file"),
          reason: invalid_reason(import))
      end
    end
    flash[:alert] = messages.uniq.join(" ")
  end

  def invalid_reason(import)
    if import.errors.added?(:file, :too_large)
      t("document_imports.upload.too_large")
    elsif import.errors.added?(:file, :unsupported_type)
      t("document_imports.upload.bad_type")
    else
      t("document_imports.errors.parse_failed")
    end
  end

  def after_upload_path
    Current.user.onboarded? ? bank_accounts_path : onboarding_step_path("accounts")
  end
end
