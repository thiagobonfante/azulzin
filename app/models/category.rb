# A per-user spending category (R6). Seeded from locale defaults at onboarding
# (Categories::SeedDefaults), plain user data afterwards — rename/delete freely, zero runtime
# i18n coupling. Deleting a category never touches movements (nullify).
class Category < ApplicationRecord
  belongs_to :user
  has_many :categorized_transactions, class_name: "Transaction", dependent: :nullify
  has_many :commitments, dependent: :nullify   # deleting a category never breaks a commitment

  # Curated presentation sets (R6) — the form only offers these, and both are validated so a
  # crafted request can't inject arbitrary CSS/markup. ICON_KEYS map to SVGs in CategoriesHelper.
  COLORS = %w[#3B82F6 #8B5CF6 #EC4899 #EF4444 #F97316 #F59E0B #22C55E #14B8A6 #06B6D4 #64748B].freeze
  ICON_KEYS = %w[cart utensils truck home document heart cap ticket arrow-path bag plane tag
                 sparkles gift bolt credit-card globe].freeze
  DEFAULT_COLOR = "#64748B".freeze

  validates :name, presence: true, length: { maximum: 60 },
                   uniqueness: { scope: :user_id, case_sensitive: false }  # citext ⇒ case-insensitive
  validates :color, inclusion: { in: COLORS }, allow_blank: true
  validates :icon,  inclusion: { in: ICON_KEYS }, allow_blank: true

  scope :ordered, -> { order(:position, :name) }

  # The color to paint with — the chosen swatch, else a neutral so bars/badges never go bare.
  def display_color = color.presence || DEFAULT_COLOR
end
