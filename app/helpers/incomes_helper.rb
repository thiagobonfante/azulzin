module IncomesHelper
  # Ordinal for the "Nth business day" label — helper-side (09 P1 #17): pt-BR keeps the plain
  # number (the key carries the º), en ordinalizes ("5th").
  def nth_ordinal(n) = I18n.locale.to_s.start_with?("pt") ? n.to_s : n.to_i.ordinalize

  # Human schedule description for an income row.
  def income_schedule_label(income)
    if income.fixed_day?
      t("incomes.row.fixed_day", day: income.schedule_day)
    else
      t("incomes.row.nth_business_day", nth: nth_ordinal(income.schedule_day))
    end
  end
end
