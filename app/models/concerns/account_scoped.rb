# Tenancy scoping ONLY (spine D10). Attribution and soft deletion are separate concerns
# (Attributable / SoftDeletable, doc 05). Included by the 7 domain models; whatsapp_messages
# uses a plain optional belongs_to instead (nullable account_id).
module AccountScoped
  extend ActiveSupport::Concern

  included do
    belongs_to :account
  end
end
