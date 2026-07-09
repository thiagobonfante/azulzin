# A financial goal ("Meta") — account-scoped household savings target (.plans/goals). Two kinds:
#   purchase     — buy something worth target_cents by target_date.
#   savings_rate — put away target_cents IN TOTAL each month (the form anchors on the household's
#                  current median guardado and asks for the new total), open-ended.
# user_caps ({ category_id => cap_cents }) are the household's draft-time orçamento slider choices;
# PlanBuilder carries them as fixed cuts in every plan.
# Goals READ the ledger and never write transactions; the analysis (baseline) and chosen plan are
# frozen jsonb snapshots so a later-deleted category still renders. Lifecycle is status, not
# deletion: draft → active → achieved | abandoned ("guardado continua guardado"). At most
# MAX_ACTIVE active goals per account bounds the weekly check fan-out.
class Goal < ApplicationRecord
  include MoneyColumns
  include AccountScoped, Attributable

  MAX_ACTIVE = 5

  money_column :target, :initial_saved, :monthly_target

  belongs_to :bank_account, optional: true   # linked caixinha; nil = all savings accounts
  # Where the "já guardado" head start sits (round 3 decision 7) — the bank accounts page
  # attributes initial_saved_cents to this caixinha in its livre/guardado-para-meta split.
  belongs_to :initial_saved_bank_account, class_name: "BankAccount", optional: true
  has_many :checks, class_name: "GoalCheck", dependent: :destroy
  has_many :commitments, dependent: :nullify   # the kind:"savings" contribution (07 §1.2)
  has_many :goal_conversations, dependent: :nullify   # WA chat state survives the draft's destroy

  enum :kind,   { purchase: "purchase", savings_rate: "savings_rate" }, validate: true
  enum :status, { draft: "draft", active: "active", achieved: "achieved", abandoned: "abandoned" },
       default: "draft", validate: true

  validates :name, presence: true, length: { maximum: 80 }
  validates :target_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :initial_saved_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :monthly_target_cents, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  # Mirrors the DB check goals_purchase_has_date for friendly errors.
  validates :target_date, presence: true, if: :purchase?
  validates :target_date, absence: true, if: :savings_rate?
  validate  :initial_below_target, if: :purchase?
  validate  :bank_account_is_a_savings_caixinha, if: -> { bank_account_id.present? }
  validate  :initial_saved_account_is_a_savings_caixinha, if: -> { initial_saved_bank_account_id.present? }
  # An amount must say WHERE it sits whenever there's a caixinha to point at; households with
  # no savings account keep the bare-amount behavior (round 3 decision 7).
  validate  :initial_saved_account_required, if: -> { initial_saved_cents.to_i.positive? && initial_saved_bank_account_id.blank? }
  validate  :active_cap_not_exceeded, if: :becoming_active?

  # The active savings commitment backing this goal, if any (07 §1.2 — one per active goal).
  # .kept guards against a soft-deleted commitment being returned as the live one.
  def savings_commitment = commitments.savings.kept.active.first

  # Where this goal's contributions land: the linked caixinha, else every savings account
  # (legacy pre-round-3 goals). One definition shared by Progress / RiskScan / Replan /
  # GoalsHelper — pair with Transaction.guardado_into (round-4 review consolidation).
  def savings_account_ids
    return [ bank_account_id ] if bank_account_id
    account.bank_accounts.kept.savings.pluck(:id)
  end

  # The chosen plan's promised finish (leve honestly promises later than the asked date) —
  # the shared anchor for the guardian's missed-month slip test AND the replan extend option;
  # the two must never drift (an alert would point at a replan section that doesn't render).
  def promised_done_on
    iso = plan["projected_done_on"]
    iso.present? ? Date.iso8601(iso) : target_date
  end

  private
    def becoming_active? = active? && (new_record? || status_changed?)

    def active_cap_not_exceeded
      return unless account
      errors.add(:base, :too_many_active) if account.goals.active.where.not(id: id).count >= MAX_ACTIVE
    end

    def bank_account_is_a_savings_caixinha
      return if bank_account&.account_id == account_id && bank_account&.savings?
      errors.add(:bank_account, :not_savings)
    end

    def initial_saved_account_is_a_savings_caixinha
      return if initial_saved_bank_account&.account_id == account_id && initial_saved_bank_account&.savings?
      errors.add(:initial_saved_bank_account, :not_savings)
    end

    def initial_saved_account_required
      errors.add(:initial_saved_bank_account, :blank) if account&.bank_accounts&.kept&.savings&.exists?
    end

    # A purchase you've already saved for isn't a goal — and required-monthly would be 0, tripping
    # goals_monthly_target_positive at choose time.
    def initial_below_target
      return if target_cents.blank? || initial_saved_cents.blank?
      errors.add(:initial_saved_cents, :exceeds_target) if initial_saved_cents >= target_cents
    end
end
