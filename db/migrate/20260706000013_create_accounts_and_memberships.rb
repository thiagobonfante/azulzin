# Migration A of the tenancy cutover (.plans/multi-user, D3). Creates the tenant tables:
# accounts, account_memberships, and invitations (the whole feature ships in one deploy).
class CreateAccountsAndMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts do |t|
      t.string  :name,          null: false
      t.integer :members_count, null: false, default: 0
      t.timestamps
    end
    # The ONLY true concurrent-join guard: counter_cache's atomic
    # `UPDATE accounts SET members_count = members_count + 1` trips this CHECK inside the
    # same transaction as the 5th membership INSERT (D1).
    add_check_constraint :accounts, "members_count BETWEEN 0 AND 4",
                         name: "accounts_members_count_cap"

    create_table :account_memberships do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user,    null: false, foreign_key: true, index: { unique: true }
      t.string     :role,    null: false, default: "member"
      t.timestamps
    end
    # Exactly one owner per account, enforced at the DB.
    add_index :account_memberships, :account_id, unique: true,
              where: "role = 'owner'", name: "index_account_memberships_one_owner"

    # Invitations DDL is owned by doc 02 §1.1 but ships here so a single deploy carries it.
    create_table :invitations do |t|
      t.references :account,    null: false, foreign_key: true
      t.citext     :email,      null: false
      t.references :invited_by, null: true,  foreign_key: { to_table: :users, on_delete: :nullify }
      t.string     :token,      null: false
      t.datetime   :expires_at, null: false
      t.datetime   :accepted_at
      t.timestamps
    end
    add_index :invitations, :token, unique: true
    add_index :invitations, %i[account_id email], unique: true, where: "accepted_at IS NULL",
              name: "index_invitations_open_per_email"
  end
end
