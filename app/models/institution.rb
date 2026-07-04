# A Brazilian financial institution (bank / fintech) offered in the account & card
# pickers. Reference data, seeded from config/institutions.yml — keyed by its COMPE
# bank `code` so the code is persisted for future integrations (Open Finance / Pix).
class Institution < ApplicationRecord
  OTHER_CODE = "000"

  has_many :bank_accounts, dependent: :restrict_with_error
  has_many :credit_cards,  dependent: :restrict_with_error

  validates :code, :name, :initials, :brand_color, presence: true
  validates :code, uniqueness: true

  scope :ordered,      -> { order(:position, :name) }
  scope :for_accounts, -> { where(supports_account: true).ordered }
  scope :for_cards,    -> { where(supports_card: true).ordered }

  def self.other = find_by(code: OTHER_CODE)

  # Idempotent upsert of the canonical registry. Derives logo_path from the presence
  # of a vendored SVG, so dropping app/assets/images/institutions/<code>.svg in (and
  # re-seeding) lights up the real logo with no other change.
  def self.load_registry!
    registry.each do |attrs|
      code = attrs.fetch("code")
      find_or_initialize_by(code: code)
        .update!(attrs.merge("logo_path" => logo_path_for(code)).except("code"))
    end
  end

  def self.registry
    YAML.safe_load_file(Rails.root.join("config/institutions.yml"))
  end

  def self.logo_path_for(code)
    rel = "institutions/#{code}.svg"
    rel if Rails.root.join("app/assets/images", rel).exist?
  end

  def other?        = code == OTHER_CODE
  def display_name  = other? ? I18n.t("institutions.other") : name

  # Luminance of the brand fill decides monogram text color: light fills (Banco do
  # Brasil yellow, Neon cyan, Will yellow) get dark text; everything else white.
  def dark_text?
    r, g, b = brand_color.delete_prefix("#").scan(/../).map { _1.to_i(16) }
    (0.299 * r + 0.587 * g + 0.114 * b) > 140
  end
end
