# Exposes a `<name>_reais` virtual accessor over a `<name>_cents` integer column so
# forms can accept/show a human money string while the DB keeps integer cents.
module MoneyColumns
  extend ActiveSupport::Concern

  class_methods do
    def money_column(*names)
      names.each do |name|
        cents_attr = "#{name}_cents"

        define_method("#{name}_reais") do
          cents = public_send(cents_attr)
          cents && format("%.2f", cents.fdiv(100)).tr(".", ",")   # edit prefill, pt-BR style
        end

        define_method("#{name}_reais=") do |value|
          public_send("#{cents_attr}=", Money.to_cents(value))
        end
      end
    end
  end
end
