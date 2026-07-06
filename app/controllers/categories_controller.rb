# Account-owned spend categories (R6). Mirrors BankAccountsController: scoped to Current.account,
# Turbo Streams with an HTML fallback, 422 on invalid create so the form isn't reset.
class CategoriesController < ApplicationController
  layout "app"
  before_action :require_onboarding, only: :index

  def index
    @categories = Current.account.categories.kept.ordered
    # Pre-select a rotating palette color so new categories start colorful (the user can change it).
    @category = Category.new(color: Category::COLORS[@categories.size % Category::COLORS.size])
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
    @category.destroy # nullifies linked movements; never destroys them
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to categories_path, notice: t(".removed") }
    end
  end

  # Empty-state "restaurar padrões" — idempotent re-seed of the locale defaults.
  def restore
    Categories::SeedDefaults.call(Current.account, locale: Current.user.locale)
    redirect_to categories_path, notice: t(".restored")
  end

  private
    def category_params = params.expect(category: %i[name color icon])
end
