# The single date-scheduling primitive shared by Income and Commitment. Given a schedule
# (kind + day) and a target month (first-of-month Date), returns the concrete date the money
# is expected in that month. Pure — the only input beyond its arguments is the frozen holiday
# table (config/br_holidays.yml), read once at boot. module_function, like Money.
module Recurrence
  module_function

  HOLIDAYS = YAML.load_file(Rails.root.join("config/br_holidays.yml"))
                 .fetch("holidays").map { Date.parse(_1) }.to_set.freeze
  COVERED_YEARS = (HOLIDAYS.map(&:year).min..HOLIDAYS.map(&:year).max).freeze

  def date_for(kind, day, month)
    case kind.to_s
    when "fixed_day"        then fixed_day(day, month)
    when "nth_business_day" then nth_business_day(day, month)
    else raise ArgumentError, "unknown schedule kind: #{kind.inspect}"
    end
  end

  # Day-of-month, clamped to the month length (29–31 collapse to the last day of short months).
  def fixed_day(day, month)
    Date.new(month.year, month.month, [ day.to_i, month.end_of_month.day ].min)
  end

  # The nth Monday–Friday of the month that is not a national/bank holiday. Weekends-only would
  # put "1º dia útil" salaries on Jan 1.
  def nth_business_day(nth, month)
    guard_year!(month.year)
    count = 0
    date  = month.beginning_of_month
    loop do
      count += 1 if business_day?(date)
      return date if count == nth.to_i
      date = date.next_day
      raise ArgumentError, "no #{nth}th business day in #{month.strftime('%Y-%m')}" if date.month != month.month
    end
  end

  def business_day?(date)
    !date.saturday? && !date.sunday? && !HOLIDAYS.include?(date)
  end

  # Fail loudly in dev/test when asked for a year the table doesn't cover (extend the YAML);
  # in production, degrade to weekends-only rather than raising on a live money computation.
  def guard_year!(year)
    return if COVERED_YEARS.cover?(year) || Rails.env.production?
    raise ArgumentError, "config/br_holidays.yml has no data for #{year} (covered: #{COVERED_YEARS}); extend the table"
  end
end
