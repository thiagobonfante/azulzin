# One-off repair: fatura imports parsed two-digit years ("18/06/26") as year 0026, anchoring
# commitments 2000 years in the past — such a plan reads as fully elapsed (presumed paid, no
# limit reserved, absent from A pagar/faturas). Shift any pre-year-1000 date forward 2000 years;
# the parser is century-guarded now (Imports::DocumentExtractor#full_date), so no new rows regress.
class FixTwoDigitYearCommitmentDates < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE commitments SET starts_on = (starts_on + interval '2000 years')::date
      WHERE starts_on < DATE '1000-01-01'
    SQL
    execute <<~SQL
      UPDATE commitments SET ends_on = (ends_on + interval '2000 years')::date
      WHERE ends_on IS NOT NULL AND ends_on < DATE '1000-01-01'
    SQL
  end

  def down
    # Data repair — nothing sensible to restore on rollback.
  end
end
