# A native shell registered for FCM push (.plans/mobile/04 §2). One row per device
# token; re-registered on every app launch (upsert by token — a token can migrate
# between users on a shared device). The session FK is the revocation linkage:
# destroying the Session destroys the device row.
class PushDevice < ApplicationRecord
  belongs_to :user
  belongs_to :session

  validates :platform, inclusion: { in: %w[ios android] }
  validates :token, presence: true, uniqueness: true

  # The bridge re-posts on launch; the token's CURRENT user/session always wins.
  def self.register!(token:, user:, session:, platform:, app_version: nil)
    device = find_or_initialize_by(token: token)
    device.update!(user: user, session: session, platform: platform,
                   app_version: app_version, last_registered_at: Time.current)
    device
  end
end
