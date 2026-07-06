class AddPendingInvitationTokenToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :pending_invitation_token, :string
  end
end
