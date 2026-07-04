class AddWhatsappVerificationCodeToUsers < ActiveRecord::Migration[8.1]
  def change
    # Short human-sendable code the user texts to the commercial number to prove they own
    # the number (reply-only verification handshake — see .plans/whats §3.3a). Cleared once
    # the number is bound + verified.
    add_column :users, :whatsapp_verification_code, :string
    add_index  :users, :whatsapp_verification_code, unique: true,
               where: "whatsapp_verification_code IS NOT NULL"
  end
end
