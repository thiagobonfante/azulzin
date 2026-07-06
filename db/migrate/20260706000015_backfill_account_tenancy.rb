# Migration C of the tenancy cutover (.plans/multi-user, D3). Per existing user: create one
# Account (name = user name or email local-part), an owner membership, and move every domain
# row and whatsapp_message onto that account. Runs in-migration — the prod dataset is 3 users.
class BackfillAccountTenancy < ActiveRecord::Migration[8.1]
  # Migration-local stubs — never reference app models in migrations.
  class MUser       < ActiveRecord::Base; self.table_name = "users";               end
  class MAccount    < ActiveRecord::Base; self.table_name = "accounts";            end
  class MMembership < ActiveRecord::Base; self.table_name = "account_memberships"; end

  DOMAIN = %w[bank_accounts credit_cards categories commitments incomes transactions document_imports].freeze

  def up
    MUser.find_each do |user|
      name    = user.name.presence || user.email_address.to_s.split("@").first
      account = MAccount.create!(name: name)
      MMembership.create!(account_id: account.id, user_id: user.id, role: "owner")
      # Stub models carry no counter_cache — set it explicitly (the CHECK allows 0..4).
      MAccount.where(id: account.id).update_all(members_count: 1)

      DOMAIN.each do |table|
        execute <<~SQL
          UPDATE #{table} SET account_id = #{account.id} WHERE created_by_id = #{user.id}
        SQL
      end
      execute <<~SQL
        UPDATE whatsapp_messages SET account_id = #{account.id} WHERE user_id = #{user.id}
      SQL
    end
  end

  def down
    (DOMAIN + %w[whatsapp_messages]).each { |t| execute "UPDATE #{t} SET account_id = NULL" }
    MMembership.delete_all
    MAccount.delete_all
  end
end
