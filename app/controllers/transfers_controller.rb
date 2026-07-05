# Single-row transfers between the user's own accounts (R5). One ordinary Transaction row —
# direction "transfer", bank_account_id = source, transfer_to_bank_account_id = destination.
# Posting demands both accounts (distinct, no card); the pure-record balances self-correct.
class TransfersController < ApplicationController
  layout "app"
  before_action :require_onboarding

  def create
    @transaction = Current.user.transactions.new(
      direction: "transfer", status: "posted", confirmed_at: Time.current, source: "manual",
      amount_reais: transfer_params[:amount_reais],
      occurred_on: transfer_params[:occurred_on].presence || sp_today,
      bank_account: Current.user.bank_accounts.find_by(id: transfer_params[:bank_account_id]),
      transfer_to_bank_account: Current.user.bank_accounts.find_by(id: transfer_params[:transfer_to_bank_account_id])
    )
    @saved = @transaction.save
    @to_savings = @saved && @transaction.transfer_to_bank_account&.savings?
    respond_to do |format|
      format.turbo_stream { render :create, status: (@saved ? :ok : :unprocessable_entity) }
      format.html { redirect_to transactions_path(month: params[:month]), notice: (@saved ? t(".created") : nil),
                    alert: (@saved ? nil : @transaction.errors.full_messages.to_sentence) }
    end
  end

  # Helpers shared with the hub streams (re-render the same figures).
  helper_method :viewed_month, :summary

  private
    def transfer_params
      params.expect(transfer: %i[amount_reais occurred_on bank_account_id transfer_to_bank_account_id])
    end

    def viewed_month
      @viewed_month ||= (parse_month(params[:month]) || sp_today.beginning_of_month)
    end

    def summary = @summary ||= MonthSummary.new(Current.user, viewed_month)

    def sp_today = Date.current.in_time_zone("America/Sao_Paulo").to_date

    def parse_month(param)
      return nil unless param.to_s.match?(/\A\d{4}-(0[1-9]|1[0-2])\z/)
      Date.strptime(param, "%Y-%m").beginning_of_month
    rescue ArgumentError
      nil
    end
end
