# Log of every inbound/outbound WhatsApp message. `wa_message_id` (the sidecar's
# globally-unique `_serialized` id) is THE inbound idempotency primitive: the sidecar
# redelivers on retry, so find_or_create_by!(wa_message_id:) + rescue RecordNotUnique is
# replay-safe. See .plans/whats §6.3.
class WhatsappMessage < ApplicationRecord
  belongs_to :user, optional: true                 # nil for an unknown/unverified sender

  # The transaction this (usually outbound) message concerns. Named `linked_transaction`
  # because an association literally named `transaction` collides with ActiveRecord's
  # own `transaction` method.
  belongs_to :linked_transaction, class_name: "Transaction",
             foreign_key: :transaction_id, optional: true, inverse_of: :reply_messages

  # Transactions produced BY this (inbound) message. dependent: :nullify so destroying a
  # message never orphans/violates the transactions.whatsapp_message_id FK.
  has_many :produced_transactions, class_name: "Transaction",
           foreign_key: :whatsapp_message_id, dependent: :nullify, inverse_of: :whatsapp_message

  has_one_attached :media                          # receipt image / audio ogg

  enum :direction, { inbound: "inbound", outbound: "outbound" }, validate: true
  enum :message_type, { text: "text", image: "image", audio: "audio", document: "document" },
       prefix: :type, validate: true, default: "text"
  enum :status, {
    received:   "received",
    processing: "processing",
    processed:  "processed",
    failed:     "failed",
    sent:       "sent"
  }, default: "received", validate: true

  scope :inbound_first, -> { order(created_at: :asc) }
end
