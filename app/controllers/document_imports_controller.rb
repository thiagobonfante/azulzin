# Upload extratos/faturas (.plans/auto). Reachable DURING onboarding (accounts step) and after
# it (accounts index) — like BankAccountsController, so `create` is not gated on onboarding.
# There is no index/show and no route that serves the raw blob back: files go in, only derived
# data (proposals) comes out.
class DocumentImportsController < ApplicationController
  layout :resolve_layout
  helper_method :after_upload_path

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

  # Unlock a password-protected PDF (P1-3): decrypt + extract the TEXT here, in the request, and
  # hand the job the extracted pages via `extraction`. The password is used in memory only and is
  # NEVER written to the DB or the job args.
  def unlock
    import = Current.user.document_imports.find(params[:id])
    pages  = Imports::PdfTextExtractor.call(import.file.download, password: params[:password])
    import.update!(extraction: pages, status: "uploaded", error_code: nil)
    ProcessDocumentImportJob.perform_later(import.id)
    redirect_to after_upload_path
  rescue Imports::PasswordProtected
    redirect_to after_upload_path, alert: t("document_imports.errors.wrong_password")
  rescue Imports::ParseError, Imports::TooLarge
    redirect_to after_upload_path, alert: t("document_imports.errors.parse_failed")
  end

  # Turbo Frame polled by import_status_controller every 2s.
  def status
    imports = Current.user.document_imports.where.not(status: "dismissed").order(created_at: :desc)
    render partial: "document_imports/status", locals: { imports: imports }
  end

  # ONE review page over ALL the user's extracted imports (D6). The Reconciler runs first — it
  # suppresses income proposals that are really cross-account self-transfers (§9).
  def review
    Imports::Reconciler.call(Current.user)
    @imports = Current.user.document_imports.awaiting_review.order(:created_at).to_a
    @groups  = Imports::Review.groups(@imports)
  end

  # Checked pids create records (Imports::Apply); discard[pid] rejects a single proposal.
  def apply
    return discard(params[:discard]) if params[:discard].present?

    fold_edits_into_proposals
    result = Imports::Apply.call(user: Current.user, accepted: build_accepted)
    redirect_to after_review_path, **apply_flash(result)
  end

  private

  def resolve_layout
    Current.user&.onboarded? ? "app" : "onboarding"
  end

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
    if import.save
      ProcessDocumentImportJob.perform_later(import.id)
      [ :created, import ]
    else
      [ :invalid, import ]
    end
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

  def after_review_path = after_upload_path

  # {import_id => [checked pid, ...]}. A checkbox posts check[pid]=1 when ticked, nothing when not.
  def build_accepted
    checked = params.fetch(:check, {}).keys
    Current.user.document_imports.awaiting_review.each_with_object({}) do |import, accepted|
      pids = import.proposals.map { it["pid"] } & checked
      accepted[import.id] = pids if pids.any?
    end
  end

  # Cheap inline edits (name always; income amount; instrument institution) folded into the
  # payload before Apply.
  def fold_edits_into_proposals
    edits = params[:edits]
    return unless edits.respond_to?(:dig)

    Current.user.document_imports.awaiting_review.find_each do |import|
      changed = false
      import.proposals.each do |proposal|
        name        = edits.dig(proposal["pid"], "name")
        amount      = edits.dig(proposal["pid"], "amount_reais")
        institution = edits.dig(proposal["pid"], "institution_code")
        if name.present?
          proposal["payload"]["nickname"] = name
          proposal["payload"]["name"]     = name
          changed = true
        end
        if amount.present?
          proposal["payload"]["amount_cents"] = Money.to_cents(amount)
          changed = true
        end
        if institution.present? && institution != proposal["payload"]["institution_code"]
          proposal["payload"]["institution_code"] = institution
          changed = true
        end
      end
      import.save! if changed
    end
  end

  def discard(pid)
    Current.user.document_imports.awaiting_review.find_each do |import|
      next unless import.proposals.any? { it["pid"] == pid && it["state"] == "proposed" }

      import.with_lock do
        proposal = import.proposals.find { it["pid"] == pid }
        proposal.merge!("state" => "rejected") if proposal && proposal["state"] == "proposed"
        import.status = "applied" if import.proposals.none? { it["state"] == "proposed" }
        import.save!
      end
    end
    # Stay on the review page — the user is mid-review; its empty state links back to the wizard.
    redirect_to review_document_imports_path
  end

  def apply_flash(result)
    created = result.created.values.sum
    flash = {}
    flash[:notice] = t("document_imports.review.applied", count: created) if created.positive?
    if result.failed.any?
      flash[:alert] = [ t("document_imports.review.some_failed", count: result.failed.size),
                        result.failed.map { it[:message] }.uniq.join("; ") ].join(" ")
    end
    flash
  end
end
