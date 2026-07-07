# Exposes a `<name>_reais` virtual accessor over a `<name>_cents` integer column so
# forms can accept/show a human money string while the DB keeps integer cents.
module MoneyColumns
  extend ActiveSupport::Concern

  # Integer cents → the edit-prefill string, pt-BR style ("1234,56" — no grouping, always
  # two decimals); nil stays nil. Pure integer math — no floats on money paths. Shared by
  # the generated `_reais` accessors and one-off prefills (CategoriesController#suggest_budget).
  def self.prefill(cents)
    return nil if cents.nil?
    reais, centavos = cents.to_i.abs.divmod(100)
    "#{"-" if cents.to_i.negative?}#{reais},#{format("%02d", centavos)}"
  end

  class_methods do
    def money_column(*names)
      names.each do |name|
        cents_attr = "#{name}_cents"

        define_method("#{name}_reais") do
          MoneyColumns.prefill(public_send(cents_attr))
        end

        define_method("#{name}_reais=") do |value|
          public_send("#{cents_attr}=", Money.to_cents(value))
        end
      end
    end
  end
end
