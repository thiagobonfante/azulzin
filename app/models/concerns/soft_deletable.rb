# Hand-rolled soft delete (spine D8). NO default_scope — callers opt in with .kept. Included
# by the 6 financial tables (NOT document_imports, NOT whatsapp_messages). archived_at stays
# orthogonal (business state). See doc 05.
module SoftDeletable
  extend ActiveSupport::Concern

  included do
    belongs_to :deleted_by, class_name: "User", optional: true

    scope :kept,         -> { where(deleted_at: nil) }
    scope :soft_deleted, -> { where.not(deleted_at: nil) }
  end

  def soft_deleted? = deleted_at.present?

  def soft_delete!(by: Current.user)
    return true if soft_deleted?
    update!(deleted_at: Time.current, deleted_by: by, updated_by: by || updated_by)
  end

  def restore!(by: Current.user)
    return true unless soft_deleted?
    update!(deleted_at: nil, deleted_by: nil, updated_by: by || updated_by)
  end
end
