# Account-owned spend categories (R6). Mirrors BankAccountsController: scoped to Current.account,
# Turbo Streams with an HTML fallback, 422 on invalid create so the form isn't reset.
class CategoriesController < ApplicationController
  layout "app"
  before_action :require_onboarding, only: :index

  def index
    @categories = Current.account.categories.kept.ordered
    # Pre-select a rotating palette color so new categories start colorful (the user can change it).
    @category = Category.new(color: Category::COLORS[@categories.size % Category::COLORS.size])
    @uncategorized_count = Current.account.transactions.kept.posted
                                  .where(direction: "expense", category_id: nil).count
  end

  def create
    @category = Current.account.categories.build(category_params)
    @category.position = (Current.account.categories.kept.maximum(:position) || -1) + 1
    saved = @category.save
    respond_to do |format|
      format.turbo_stream { render :create, status: (saved ? :ok : :unprocessable_entity) }
      format.html do
        redirect_to categories_path, notice: (saved ? t(".created") : nil),
                    alert: (saved ? nil : @category.errors.full_messages.to_sentence)
      end
    end
  end

  def edit
    @category = Current.account.categories.kept.find(params[:id])
    render partial: "categories/edit", locals: { category: @category }
  end

  def update
    @category = Current.account.categories.kept.find(params[:id])
    @saved = @category.update(category_params)
    respond_to do |format|
      format.turbo_stream { render :update, status: (@saved ? :ok : :unprocessable_entity) }
      format.html { redirect_to categories_path, alert: (@saved ? nil : @category.errors.full_messages.to_sentence) }
    end
  end

  def destroy
    @category = Current.account.categories.kept.find(params[:id])
    @category.soft_delete!(by: Current.user)   # movements keep category_id; ledger renders name + suffix
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to categories_path, notice: t(".removed") }
    end
  end

  # Merchant-memory suggestion for the quick-add picker (auto-categories 03 §1). LLM-free,
  # pure read; the picker panel already renders every category, so the id is all JS needs.
  def suggest
    result = Categories::Suggest.call(account: Current.account, merchant: params[:merchant])
    if result
      render json: { category_id: result.category.id }
    else
      head :no_content
    end
  end

  # Empty-state "restaurar padrões" — idempotent re-seed of the locale defaults.
  def restore
    Categories::SeedDefaults.call(Current.account, locale: Current.user.locale)
    redirect_to categories_path, notice: t(".restored")
  end

  # Historical auto-categorization (auto-categories Phase 5, decision O3: silent apply +
  # undo). One run per account per day; the job re-checks the cap before touching AI.
  def backfill
    if Current.account.category_backfill_at&.after?(24.hours.ago)
      redirect_to categories_path, alert: t(".ran_recently")
    else
      CategorizeHistoryJob.perform_later(Current.account.id)
      redirect_to transactions_path, notice: t(".queued")
    end
  end

  def backfill_undo
    if (at = Current.account.category_backfill_at)
      Current.account.transactions.auto_categorized_since(at)
             .update_all(category_id: nil, category_source: nil, updated_at: Time.current)
      Current.account.update!(category_backfill_at: nil)
    end
    redirect_to transactions_path, notice: t("categories.backfill.undone")
  end

  def backfill_dismiss
    Current.account.update!(category_backfill_at: nil)
    redirect_to transactions_path
  end

  private
    def category_params = params.expect(category: %i[name color icon])
end
