require "net/http"

module BcbRates
  # Daily upsert of the SGS card-rate aggregates (recurring.yml `bcb_rates_fetch`).
  # Series 25477 (rotativo total PF, % a.m.) and 25478 (parcelamento da fatura PF) —
  # the 22699/20749 lookalikes are NOT these series (verified trap, plan 02 §2).
  # Any failure keeps the last stored row serving; there is nothing to retry urgently.
  class FetchJob < ApplicationJob
    queue_as :background

    SERIES = { "rotativo" => 25_477, "parcelamento" => 25_478 }.freeze

    def perform
      SERIES.each do |kind, series_id|
        entry = self.class.fetch_latest(series_id)
        next unless entry
        BcbRate.upsert(
          { kind: kind, monthly_rate: entry[:rate], reference_month: entry[:reference_month],
            fetched_at: Time.current, created_at: Time.current, updated_at: Time.current },
          unique_by: [ :kind, :reference_month ])
      rescue StandardError => e
        Rails.logger.warn("bcb_rates_fetch: #{kind} failed (#{e.class}: #{e.message}) — serving the last row")
      end
    end

    # → { rate: BigDecimal, reference_month: Date } or nil. SGS payload:
    # [{"data":"01/05/2026","valor":"15.09"}]
    def self.fetch_latest(series_id)
      uri = URI("https://api.bcb.gov.br/dados/serie/bcdata.sgs.#{series_id}/dados/ultimos/1?formato=json")
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                 open_timeout: 10, read_timeout: 10) { |http| http.get(uri.request_uri) }
      return nil unless response.is_a?(Net::HTTPSuccess)
      entry = JSON.parse(response.body).first
      return nil unless entry
      { rate: BigDecimal(entry.fetch("valor")),
        reference_month: Date.strptime(entry.fetch("data"), "%d/%m/%Y").beginning_of_month }
    end
  end
end
