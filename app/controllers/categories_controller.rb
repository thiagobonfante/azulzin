# User-owned spend categories (R6). Mirrors BankAccountsController: scoped to Current.user,
# Turbo Streams with an HTML fallback, 422 on invalid create so the form isn't reset.
class CategoriesController < ApplicationController
  layout "app"
  before_action :require_onboarding, only: :index

  def index
    @categories = Current.user.categories.ordered
    @category   = Category.new
  end

  def create
    @category = Current.user.categories.build(category_params)
    @category.position = (Current.user.categories.maximum(:position) || -1) + 1
    saved = @category.save
    respond_to do |format|
      format.turbo_stream { render :create, status: (saved ? :ok : :unprocessable_entity) }
      format.html do
        redirect_to categories_path, notice: (saved ? t(".created") : nil),
                    alert: (saved ? nil : @category.errors.full_messages.to_sentence)
      end
    end
  end

  def update
    @category = Current.user.categories.find(params[:id])
    @saved = @category.update(category_params)
    respond_to do |format|
      format.turbo_stream { render :update, status: (@saved ? :ok : :unprocessable_entity) }
      format.html { redirect_to categories_path, alert: (@saved ? nil : @category.errors.full_messages.to_sentence) }
    end
  end

  def destroy
    @category = Current.user.categories.find(params[:id])
    @category.destroy # nullifies linked movements; never destroys them
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to categories_path, notice: t(".removed") }
    end
  end

  # Empty-state "restaurar padrões" — idempotent re-seed of the locale defaults.
  def restore
    Categories::SeedDefaults.call(Current.user)
    redirect_to categories_path, notice: t(".restored")
  end

  private
    def category_params = params.expect(category: %i[name])
end
