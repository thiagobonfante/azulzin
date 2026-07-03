require "test_helper"
require "i18n/tasks"

class I18nTest < ActiveSupport::TestCase
  setup do
    @i18n         = I18n::Tasks::BaseTask.new
    @missing_keys = @i18n.missing_keys
    @unused_keys  = @i18n.unused_keys
  end

  test "no missing keys" do
    assert_empty @missing_keys,
      "Missing #{@missing_keys.leaves.count} i18n key(s). Run: bundle exec i18n-tasks missing"
  end

  test "no unused keys" do
    assert_empty @unused_keys,
      "#{@unused_keys.leaves.count} unused i18n key(s). Run: bundle exec i18n-tasks unused"
  end
end
