# Who created / last edited a domain row (spine D7). Stamped from Current.user inside
# requests; jobs and services set created_by/updated_by explicitly — Current is never
# populated outside a request and must not be faked there.
module Attributable
  extend ActiveSupport::Concern

  included do
    belongs_to :created_by, class_name: "User", optional: true
    belongs_to :updated_by, class_name: "User", optional: true

    # ||= lets a service pre-set an explicit creator (WhatsApp/import job) without the
    # callback clobbering it. before_update only stamps when a member actually acted.
    before_create { self.created_by ||= Current.user }
    before_update { self.updated_by = Current.user if Current.user && changed? }
  end
end
