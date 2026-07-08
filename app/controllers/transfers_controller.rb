# Transfers between the user's own accounts (R5). Each transfer is one ordinary Transaction
# row — direction "transfer", bank_account_id = source, transfer_to_bank_account_id =
# destination. create accepts the inline single-source form (transfer[bank_account_id] +
# transfer[amount_reais]) or the hero modal's batch (sources[<account_id>] = amount, one row
# per filled source, all-or-nothing). Posting demands both accounts (distinct, no card); the
# pure-record balances self-correct.
class TransfersController < ApplicationController
  layout "app"
  before_action :require_onboarding

  def create
    to = Current.account.bank_accounts.kept.find_by(id: transfer_params[:transfer_to_bank_account_id])
    @transactions = source_rows.map do |account_id, amount_reais|
      Current.account.transactions.new(
        direction: "transfer", status: "posted", confirmed_at: Time.current, source: "manual",
        amount_reais: amount_reais,
        occurred_on: transfer_params[:occurred_on].presence || sp_today,
        bank_account: Current.account.bank_accounts.kept.find_by(id: account_id),
        transfer_to_bank_account: to
      )
    end
    @saved = @transactions.any? && @transactions.all?(&:valid?)
    ActiveRecord::Base.transaction { @transactions.each(&:save!) } if @saved
    @transaction = @transactions.first || Current.account.transactions.new(direction: "transfer")
    @to_savings = @saved && to&.savings?
    @error_message = batch_error_message unless @saved
    respond_to do |format|
      format.turbo_stream { render :create, status: (@saved ? :ok : :unprocessable_entity) }
      format.html { redirect_to transactions_path(month: params[:month]), notice: (@saved ? t(".created") : nil),
                    alert: (@saved ? nil : @error_message) }
    end
  end

  # Helpers shared with the hub streams (re-render the same figures).
  helper_method :viewed_month, :summary

  private
    def transfer_params
      params.expect(transfer: %i[amount_reais occurred_on bank_account_id transfer_to_bank_account_id])
    end

    # Batch (modal): every source whose amount was filled. Single (inline form): the one row.
    def source_rows
      if params[:sources].present?
        params.permit(sources: {})[:sources].to_h.filter_map do |account_id, amount|
          [ account_id, amount ] if amount.to_s.strip.present?
        end
      else
        [ [ transfer_params[:bank_account_id], transfer_params[:amount_reais] ] ]
      end
    end

    def batch_error_message
      return t("transactions.hero.save_modal.none_error") if @transactions.empty?
      invalid = @transactions.detect { |txn| txn.errors.any? } || @transactions.first
      invalid.errors.full_messages.to_sentence
    end

    def viewed_month
      @viewed_month ||= (parse_month(params[:month]) || sp_today.beginning_of_month)
    end

    def summary = @summary ||= MonthSummary.new(Current.account, viewed_month)

    def sp_today = Date.current.in_time_zone("America/Sao_Paulo").to_date

    def parse_month(param)
      return nil unless param.to_s.match?(/\A\d{4}-(0[1-9]|1[0-2])\z/)
      Date.strptime(param, "%Y-%m").beginning_of_month
    rescue ArgumentError
      nil
    end
end
