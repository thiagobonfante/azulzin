# First-run setup wizard: profile (name + phone) → bank accounts (≥1 required) → credit
# cards (optional). Accounts and cards themselves are added/removed through
# BankAccountsController / CreditCardsController; this controller drives the step flow.
class OnboardingController < ApplicationController
  layout "onboarding"
  before_action :redirect_if_onboarded

  STEPS = %w[profile accounts cards].freeze

  def show
    step = params[:step]
    return redirect_to onboarding_step_path(resume_step) if step.blank? || ahead_of_resume?(step)

    @step = step
    render_step
  end

  def update
    @step = params[:step]
    # Never let a PATCH act on a step past the earliest incomplete one — this re-checks
    # the prerequisites (profile complete, ≥1 account) on every submit, so a stale/forged
    # "cards" finish (or an account deleted after advancing) can't complete onboarding.
    return redirect_to onboarding_step_path(resume_step) if ahead_of_resume?(@step)

    case @step
    when "profile"  then update_profile
    when "accounts" then advance_from_accounts
    when "cards"    then finish
    end
  end

  private
    def redirect_if_onboarded
      redirect_to dashboard_path if Current.user.onboarded?
    end

    # The earliest step the user still needs to complete — where `onboarding` resolves to
    # and the furthest a deep link may jump.
    def resume_step
      user = Current.user
      return "profile"  if user.name.blank? || user.phone.blank?
      return "accounts" if user.bank_accounts.none?
      "cards"
    end

    def ahead_of_resume?(step)
      STEPS.index(step).to_i > STEPS.index(resume_step)
    end

    # Explicit per-step render with literal template names keeps the render path free of
    # user input (Brakeman flags `render params[:step]`), even though the route already
    # constrains :step to the three known values.
    def render_step
      case @step
      when "profile"
        @user = Current.user
        render :profile
      when "accounts"
        @bank_accounts = Current.user.bank_accounts.includes(:institution).order(:created_at)
        @bank_account  = BankAccount.new
        render :accounts
      when "cards"
        @credit_cards = Current.user.credit_cards.includes(:institution).order(:created_at)
        @credit_card  = CreditCard.new
        render :cards
      end
    end

    def update_profile
      @user = Current.user
      if @user.update_as_profile(profile_params)
        redirect_to onboarding_step_path("accounts")
      else
        render "profile", status: :unprocessable_entity
      end
    end

    def advance_from_accounts
      if Current.user.bank_accounts.any?
        redirect_to onboarding_step_path("cards")
      else
        redirect_to onboarding_step_path("accounts"), alert: t("onboarding.accounts.need_one")
      end
    end

    def finish
      Current.user.onboard!
      redirect_to dashboard_path, notice: t("onboarding.finished")
    end

    def profile_params
      params.expect(user: %i[name country_code phone_national])
    end
end
