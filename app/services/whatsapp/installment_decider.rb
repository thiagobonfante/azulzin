module Whatsapp
  # installment_purchase intent (07 §4.4): never fan out an unconfident parse. Card instrument →
  # eager fan-out via Installments::Create; bank account → a debit Commitment(kind:"installment").
  # Idempotent on the parent's source_message_id.
  class InstallmentDecider
    include HandlerHelpers

    def initialize(msg, extraction)
      @msg = msg
      @extraction = extraction
    end

    def call
      return @existing if (@existing = account.commitments.find_by(source_message_id: @msg.wa_message_id)) # replay

      count      = @extraction.installments_count.to_i
      instrument = Whatsapp::Matcher.new(account, @extraction).call.instrument
      total      = derive_total_cents(count)

      return ask_installments_count if count < 2 && confident? && instrument
      return park_stub unless confident? && count.between?(2, 48) && instrument && total&.positive?

      if instrument.is_a?(CreditCard)
        commitment = Installments::Create.call(account: account, created_by: @msg.user,
          card: instrument, total_cents: total, count: count,
          occurred_on: occurred, merchant: @extraction.merchant, category_id: resolve_category,
          source_message_id: @msg.wa_message_id)
        if commitment.category
          reply("installments_posted_categorized", count: count, parcel: currency(commitment.amount_cents),
                instrument: instrument.display_name, category: commitment.category.name,
                month: month_label(commitment.starts_on))
        else
          reply("installments_posted", count: count, parcel: currency(commitment.amount_cents),
                instrument: instrument.display_name, month: month_label(commitment.starts_on))
        end
      else
        commitment = create_debit_plan(instrument, total, count)
        reply("installment_commitment_created", count: count, parcel: currency(commitment.amount_cents),
              name: commitment.name, instrument: instrument.display_name)
      end
      commitment
    end

    private

    def occurred = @occurred ||= (@extraction.occurred_on || sp_today)
    def confident? = Whatsapp::Confidence.new(@extraction).above_floor?

    def derive_total_cents(count)
      if @extraction.installment_total_raw.present?
        Money.to_cents(@extraction.installment_total_raw)
      elsif @extraction.installment_parcel_raw.present?
        (Money.to_cents(@extraction.installment_parcel_raw) || 0) * count
      else
        @extraction.amount_cents
      end
    end

    def create_debit_plan(bank, total, count)
      account.commitments.create!(
        created_by: @msg.user,
        bank_account: bank, name: @extraction.merchant.presence || I18n.t("commitments.default_installment_name"),
        kind: "installment", amount_cents: (total.to_f / count).round, total_cents: total, installments_count: count,
        schedule_kind: "fixed_day", schedule_day: occurred.day, starts_on: occurred.beginning_of_month,
        source: "whatsapp", source_message_id: @msg.wa_message_id, category_id: resolve_category
      )
    end

    # Ladder (auto-categories 01 §5), mirroring Decider. Commitments carry only the id;
    # parcel transactions get provenance stamped at MarkPaid time from commitment.source.
    def resolve_category
      Categories.auto_assign(account: account, merchant: @extraction.merchant, label: @extraction.category).first
    end

    # Parse missing count → one ask on a pending stub carrying the rest inside extraction jsonb.
    def ask_installments_count
      txn = upsert_row(status: "needs_clarification", direction: "expense", amount_cents: @extraction.amount_cents || 0,
                       merchant: @extraction.merchant, occurred_on: occurred, billing_month: occurred.beginning_of_month,
                       extraction: @extraction.to_h.compact, ask: { "slot" => "installments_count" },
                       ask_expires_at: 60.minutes.from_now)
      reply("ask_installments_count", txn: txn)
      txn
    end

    # Never fan out below floor — park ONE stub; the hub tray confirm expands it (superseding the stub).
    def park_stub
      total = derive_total_cents([ @extraction.installments_count.to_i, 1 ].max)
      txn = upsert_row(status: "pending_review", direction: "expense", amount_cents: total || @extraction.amount_cents || 0,
                       merchant: @extraction.merchant, occurred_on: occurred, billing_month: occurred.beginning_of_month,
                       extraction: @extraction.to_h.compact)
      reply("parked", txn: txn)
      txn
    end
  end
end
