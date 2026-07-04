class AddProfileAndOnboardingToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :name, :string
    add_column :users, :phone, :string
    add_column :users, :onboarded_at, :datetime
  end
end
