# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# Reference data: the Brazilian financial-institution registry backing the account
# and card pickers. Idempotent — safe to re-run on every deploy.
Institution.load_registry!
Rails.logger.info "Seeded #{Institution.count} institutions."
