# Pay / unpay a computed commitment occurrence (R10). The synthetic id ("42-2026-08") is parsed
# and authorized through the user's own commitments. Card-instrument occurrences settle on the
# bill — the pay route is rejected server-side (defense beyond the hidden button). 05 §5.5.
class CommitmentOccurrencesController < ApplicationController
  layout "app"
  before_action :require_onboarding
  helper_method :viewed_month, :summary, :hub_occurrences

  def pay
    @occurrence = CommitmentOccurrence.find_for!(Current.user, params[:id])
    return head :unprocessable_entity if @occurrence.card?
    payment = Commitments::MarkPaid.call(@occurrence.commitment, @occurrence.month)
    @occurrence = CommitmentOccurrence.new(@occurrence.commitment, @occurrence.month, payment: payment)
    respond_to do |format|
      format.turbo_stream { render :pay }
      format.html { redirect_to commitment_path(@occurrence.commitment), notice: t("commitments.occurrences.paid") }
    end
  end

  def unpay
    @occurrence = CommitmentOccurrence.find_for!(Current.user, params[:id])
    @occurrence.payment&.reverse!
    @occurrence = CommitmentOccurrence.new(@occurrence.commitment, @occurrence.month)
    respond_to do |format|
      format.turbo_stream { render :unpay }
      format.html { redirect_to commitment_path(@occurrence.commitment) }
    end
  end

  private
    def viewed_month
      @viewed_month ||= (parse_month(params[:month]) || Date.current.beginning_of_month)
    end

    def summary = @summary ||= MonthSummary.new(Current.user, viewed_month)

    def hub_occurrences = @hub_occurrences ||= CommitmentOccurrence.for_month(Current.user, viewed_month)

    def parse_month(param)
      return nil unless param.to_s.match?(/\A\d{4}-(0[1-9]|1[0-2])\z/)
      Date.strptime(param, "%Y-%m").beginning_of_month
    rescue ArgumentError
      nil
    end
end
