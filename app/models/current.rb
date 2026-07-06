class Current < ActiveSupport::CurrentAttributes
  attribute :session
  delegate :user,    to: :session, allow_nil: true
  delegate :account, to: :user,    allow_nil: true   # spine D2 — the one addition
end
