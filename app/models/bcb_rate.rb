# One row per (kind, reference month) of the BCB SGS card-rate aggregates
# (.plans/credit-cards 02 §2; P0 #5: SGS only in v1, labeled "taxas médias do Banco
# Central"). Readers take the newest row; a fetch failure simply keeps serving it —
# a stale rate is a fine estimate (it moves ~0.1 pp/month).
class BcbRate < ApplicationRecord
  KINDS = %w[rotativo parcelamento].freeze

  validates :kind, inclusion: { in: KINDS }
  validates :monthly_rate, numericality: { greater_than: 0 }
  validates :reference_month, presence: true

  def self.current(kind) = where(kind: kind).order(reference_month: :desc).first
end
