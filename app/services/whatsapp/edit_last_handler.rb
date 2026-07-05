module Whatsapp
  # edit_last intent (07 §4.7): corrects the most recent WA-produced row ≤ 24h via update! /
  # assign_instrument! (callbacks fire → billing_month recomputes on date/instrument change).
  class EditLastHandler
    include HandlerHelpers

    def initialize(msg, extraction)
      @msg = msg
      @extraction = extraction
    end

    def call
      row = last_wa_row
      return reply("nothing_to_edit") unless row
      return reply("edit_unclear") unless apply_edit(row)
      reply("edited", txn: row, amount: currency(row.amount_cents), instrument: (row.instrument&.display_name || "—"))
      row
    end

    private

    def last_wa_row
      user.transactions.where.not(whatsapp_message_id: nil).where("created_at > ?", 24.hours.ago)
          .where.not(status: %w[rejected superseded]).where(installment_number: nil)
          .order(created_at: :desc).first
    end

    def apply_edit(row)
      case @extraction.edit_field_hint
      when "amount"     then set_amount(row)
      when "merchant"   then set_merchant(row)
      when "instrument" then set_instrument(row)
      when "date"       then set_date(row)
      else                   infer(row)
      end
    end

    def set_amount(row)
      cents = Money.to_cents(@extraction.amount_raw)
      return false unless cents&.positive?
      row.update!(amount_cents: cents)
    end

    def set_merchant(row)
      return false if @extraction.merchant.blank?
      row.update!(merchant: @extraction.merchant)
    end

    def set_instrument(row)
      inst = match_account(@extraction.instrument_phrase) || Whatsapp::Matcher.new(user, @extraction).call.instrument
      return false unless inst
      row.assign_instrument!(inst)
      true
    end

    def set_date(row)
      return false unless @extraction.occurred_on
      row.update!(occurred_on: @extraction.occurred_on)
    end

    def infer(row)
      if @extraction.amount_present? then row.update!(amount_cents: @extraction.amount_cents)
      elsif @extraction.merchant.present? then row.update!(merchant: @extraction.merchant)
      else false
      end
    end
  end
end
