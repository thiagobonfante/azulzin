# Pure math for the regulated partial-payment path (.plans/credit-cards 02): one rotativo
# cycle (juros + IOF), then 12× parcelamento at the BCB average rate. Integer cents in and
# out; BigDecimal rates; no I/O, no clock. Everything is an ESTIMATE labeled as such in
# the UI — no output here is ever written to a balance or a transaction row.
#
# Conventions (pinned by the canonical R$ 3.000,00 table in rotativo_test):
# - juros and each IOF component round half-up independently;
# - the Price schedule runs on the EXACT (unrounded) installment — rounding happens only
#   at the output boundary (displayed parcel, schedule entries, totals).
module RevolvingCredit
  module_function

  # IOF on PF credit (Decreto 6.306/2007 art. 7º): 0.38% fixed + 0.0082%/day, daily part
  # capped at 365 days. Coded reading (flagged in the plan): IOF sits OUTSIDE the Lei
  # 14.690/2023 100% cap — the resolution says "juros e encargos financeiros" without
  # itemizing; we still clamp total encargos at the cap, which absorbs the ambiguity.
  IOF_FIXED_PCT    = BigDecimal("0.38")
  IOF_DAILY_PCT    = BigDecimal("0.0082")
  IOF_DAILY_MAX    = 365

  # Cost of one rotativo cycle on a financed remainder. monthly_rate as percent (15.09).
  def cycle_cost(financed_cents, monthly_rate:, days: 30)
    f     = BigDecimal(financed_cents)
    interest = (f * monthly_rate / 100).round
    iof   = (f * IOF_FIXED_PCT / 100).round +
            (f * IOF_DAILY_PCT / 100 * [ days, IOF_DAILY_MAX ].min).round
    { interest_cents: interest.to_i, iof_cents: iof.to_i, total_cents: (interest + iof).to_i }
  end

  # Price-table installment (rounded for display; the schedule uses the exact value).
  def parcel(financed_cents, monthly_rate:, count: 12)
    exact_parcel(BigDecimal(financed_cents), monthly_rate / 100, count).round.to_i
  end

  # The full modeled path for paying P of bill T: remainder → one rotativo cycle → 12×
  # parcelamento. nil when nothing is financed (full payment / overpay — no projection).
  #   { financed:, next_bill_add: (cycle juros+IOF), parcel:, schedule: [12 balances],
  #     total_cost: (P + all parcels), encargos:, cap: (100% of financed, Lei 14.690),
  #     months_to_cap: (compounding-only "dobra em ~N meses" counterfactual) }
  def projection(bill_cents, paid_cents, revolving_monthly_rate:, installment_monthly_rate:, count: 12)
    financed = bill_cents - paid_cents
    return nil unless financed.positive?

    cost      = cycle_cost(financed, monthly_rate: revolving_monthly_rate)
    principal = financed + cost[:total_cents]
    rate      = installment_monthly_rate / 100
    pmt       = exact_parcel(BigDecimal(principal), rate, count)

    schedule = []
    balance  = BigDecimal(principal)
    count.times do
      balance = balance * (1 + rate) - pmt
      schedule << balance.round.to_i
    end
    schedule[-1] = 0 if schedule.last.abs <= 1   # Price zeroes the last cent exactly

    cap        = financed
    total_cost = paid_cents + (pmt * count).round.to_i
    finance_charges = total_cost - bill_cents
    if finance_charges > cap                             # Lei 14.690/2023: the debt at most doubles
      finance_charges = cap
      total_cost = bill_cents + cap
    end

    { financed_cents: financed, next_bill_add_cents: cost[:total_cents],
      interest_cents: cost[:interest_cents], iof_cents: cost[:iof_cents],
      parcel_cents: pmt.round.to_i, schedule: schedule,
      total_cost_cents: total_cost, finance_charges_cents: finance_charges,
      cap_cents: cap, months_to_cap: months_to_cap(financed, revolving_monthly_rate) }
  end

  # Months for the debt to hit the 100%-encargos ceiling compounding at the rotativo rate
  # alone — the honest "sua dívida pode no máximo dobrar, e dobra em ~N meses" line.
  def months_to_cap(financed_cents, revolving_monthly_rate)
    return nil unless financed_cents.positive? && revolving_monthly_rate.positive?
    debt, months = BigDecimal(financed_cents), 0
    while debt < financed_cents * 2
      debt   *= 1 + revolving_monthly_rate / 100
      months += 1
    end
    months
  end

  def exact_parcel(principal, rate, count)
    return principal / count if rate.zero?
    principal * rate / (1 - (1 + rate)**-count)
  end
end
