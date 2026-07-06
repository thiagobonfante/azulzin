require "test_helper"

class DocumentImportTest < ActiveSupport::TestCase
  setup { @user = users(:confirmed) }

  test "defaults to uploaded status" do
    assert_equal "uploaded", DocumentImport.new.status
  end

  test "accepts a nil kind and source_format" do
    di = valid_import
    di.kind = nil
    di.source_format = nil
    assert di.valid?, di.errors.full_messages.to_sentence
  end

  test "rejects an unknown kind" do
    di = valid_import
    di.kind = "nonsense"
    assert_not di.valid?
    assert di.errors.key?(:kind)
  end

  test "requires an attached file on create" do
    di = @user.document_imports.new(checksum: "abc")
    assert_not di.valid?
    assert di.errors.added?(:file, :missing)
  end

  test "rejects a file over the size cap" do
    di = @user.document_imports.new(checksum: "abc")
    di.file.attach(io: StringIO.new("a" * (DocumentImport::MAX_FILE_BYTES + 1)),
                   filename: "big.csv", content_type: "text/csv")
    assert_not di.valid?
    assert di.errors.added?(:file, :too_large)
  end

  test "rejects an unsupported content type" do
    di = @user.document_imports.new(checksum: "abc")
    di.file.attach(io: File.open(file_fixture("imports/sample.png")),
                   filename: "x.png", content_type: "image/png")
    assert_not di.valid?
    assert di.errors.added?(:file, :unsupported_type)
  end

  test "duplicate_checksum? is true when a live import shares the checksum" do
    make_import(checksum: "dup")
    assert @user.document_imports.new(checksum: "dup").duplicate_checksum?
  end

  test "a dismissed import does not block a re-upload" do
    make_import(checksum: "dup", status: "dismissed")
    assert_not @user.document_imports.new(checksum: "dup").duplicate_checksum?
  end

  test "duplicate_checksum? is scoped per user" do
    make_import(checksum: "dup")
    other = User.create!(email_address: "o@example.com", password: "password123")
    assert_not other.document_imports.new(checksum: "dup").duplicate_checksum?
  end

  test "proposed_items returns only proposals still in the proposed state" do
    di = DocumentImport.new(proposals: [ { "state" => "proposed" }, { "state" => "applied" } ])
    assert_equal 1, di.proposed_items.size
  end

  test "terminal? covers extracted, failed, applied and dismissed" do
    %w[extracted failed applied dismissed].each { |s| assert DocumentImport.new(status: s).terminal? }
    %w[uploaded processing].each { |s| assert_not DocumentImport.new(status: s).terminal? }
  end

  private

  def valid_import(**attrs)
    di = @user.document_imports.new({ checksum: SecureRandom.hex }.merge(attrs))
    di.file.attach(io: File.open(file_fixture("imports/sample.csv")),
                   filename: "sample.csv", content_type: "text/csv")
    di
  end

  def make_import(status: "uploaded", **attrs)
    di = valid_import(**attrs)
    di.status = status
    di.save!
    di
  end
end
