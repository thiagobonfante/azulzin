# up-tier F4 — sync ledger download (05 §3). Every query starts from Current.account;
# request params pick only the file format (whitelisted) and the occurred_on range — they
# can never widen scope to another account's data.
class ExportsController < AppController
  FORMATS = %w[xlsx csv pdf].freeze

  def new
  end

  def index
    from, to = range
    ledger = Exports::Ledger.new(Current.account, from: from, to: to)
    fmt = FORMATS.include?(params[:format]) ? params[:format] : "xlsx"
    send_data payload(ledger, fmt),
              filename: t(".filename", month: Date.current.strftime("%Y-%m"), ext: fmt),
              type: mime_for(fmt), disposition: "attachment"
  end

  private
    def payload(ledger, fmt)
      case fmt
      when "csv" then Exports::CsvFormatter.call(ledger)
      when "pdf" then Exports::PdfFormatter.call(ledger)
      else            Exports::XlsxFormatter.call(ledger)
      end
    end

    def mime_for(fmt)
      case fmt
      when "csv" then Mime[:csv].to_s
      when "pdf" then Mime[:pdf].to_s
      else            Mime[:xlsx].to_s   # registered by caxlsx_rails
      end
    end

    # Preset → occurred_on bounds. Unknown/missing preset falls back to the current month
    # (the smallest range); "tudo" is unbounded — sync send_data by decision (07 D11).
    def range
      today = Date.current
      case params[:preset]
      when "last_3_months" then [ today.beginning_of_month << 2, today.end_of_month ]
      when "year"          then [ today.beginning_of_year, today.end_of_year ]
      when "all"           then [ nil, nil ]
      when "custom"        then [ parse_date(params[:from]), parse_date(params[:to]) ]
      else                      [ today.beginning_of_month, today.end_of_month ]
      end
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end
end
