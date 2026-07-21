class Session < ApplicationRecord
  belongs_to :user
  # Revocation linkage (.plans/mobile/04 §2): sign-out and password-reset
  # (sessions.destroy_all) automatically revoke this session's push devices.
  has_many :push_devices, dependent: :destroy
end
