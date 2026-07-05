# A per-user spending category (R6). Seeded from locale defaults at onboarding
# (Categories::SeedDefaults), plain user data afterwards — rename/delete freely, zero runtime
# i18n coupling. Deleting a category never touches movements (nullify).
class Category < ApplicationRecord
  belongs_to :user
  has_many :categorized_transactions, class_name: "Transaction", dependent: :nullify
  has_many :commitments, dependent: :nullify   # deleting a category never breaks a commitment

  validates :name, presence: true, length: { maximum: 60 },
                   uniqueness: { scope: :user_id, case_sensitive: false }  # citext ⇒ case-insensitive

  scope :ordered, -> { order(:position, :name) }
end
