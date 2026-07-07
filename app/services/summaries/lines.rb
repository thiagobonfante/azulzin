module Summaries
  # Render-time assembly of the digest's composite interpolations (up-tier 04 §3). The
  # notification payload snapshots structured data — names + integer cents, never
  # formatted money — and each composite line is built HERE, inside the ambient locale
  # (the dashboard's request locale; the recipient's locale in Notifications::Deliver),
  # so one stored row renders "R$ 1.234,56" for a pt-BR member and "R$ 1,234.56" for an
  # en-US one. Empty data ⇒ an empty string; the templates put these args at line starts,
  # so an empty line simply vanishes (04 §3: no "gastou R$ 0" filler).
  module Lines
    # Payload keys consumed here instead of interpolated raw by Notifications.template_args.
    STRUCTURED_KEYS = %i[month top_categories other_cents upcoming budget_within budget_total].freeze

    class << self
      # payload: symbolized top-level keys, string-keyed nested items (the JSONB shape).
      # The block formats integer cents in the viewer's locale — the same contract as
      # Notifications.template_args.
      def args(payload, &money)
        { month: month_name(payload[:month]),
          spent_line: spent_line(payload, &money),
          upcoming_line: upcoming_line(payload[:upcoming], &money),
          budget_line: budget_line(payload) }.compact
      end

      private

      def month_name(iso) = iso && I18n.l(Date.parse(iso), format: "%B").capitalize

      # "Você gastou R$ 920,00 — Mercado R$ 420,00, …, outros R$ 120,00.\n" — or "" for a
      # zero-spend week (the row can still exist for its upcoming bills).
      def spent_line(payload, &money)
        return "" unless payload[:spent_cents].to_i.positive?
        line(I18n.t("notifications.summary_lines.spent",
                    spent: money.call(payload[:spent_cents]), cats: cat_line(payload, &money)))
      end

      def cat_line(payload, &money)
        parts = (payload[:top_categories] || []).map { |cat| "#{cat['name']} #{money.call(cat['cents'])}" }
        if payload[:other_cents].to_i.positive?
          parts << I18n.t("notifications.summary_lines.others", amount: money.call(payload[:other_cents]))
        end
        parts.join(", ")
      end

      # "Contas nos próximos 7 dias: Luz (R$ 182,40), Internet (R$ 120,00).\n" or "".
      def upcoming_line(bills, &money)
        return "" if bills.blank?
        line(I18n.t("notifications.summary_lines.upcoming",
                    bills: bills.map { |bill| "#{bill['name']} (#{money.call(bill['cents'])})" }.join(", ")))
      end

      # "Você ficou dentro do combinado em 3 de 4 categorias.\n" — or "" when no budgets
      # are set (Summaries::Build omits the counts entirely).
      def budget_line(payload)
        return "" unless payload[:budget_total].to_i.positive?
        line(I18n.t("notifications.summary_lines.budget",
                    within: payload[:budget_within], count: payload[:budget_total]))
      end

      def line(text) = "#{text}\n"
    end
  end
end
