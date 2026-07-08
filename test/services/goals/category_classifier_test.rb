require "test_helper"

# Touchpoint 2 (.plans/goals 04 §2): one closed-set call, only for unresolved custom categories,
# cached in categories.flexibility. Injectable client — no network.
class Goals::CategoryClassifierTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :calls
    def initialize(parsed) = (@parsed = parsed; @calls = 0)
    def chat(**_) = (@calls += 1; OpenRouterClient::Result.new(parsed: @parsed))
  end

  setup { @account = users(:confirmed).account }

  test "classifies unresolved custom categories and caches the column" do
    pets = @account.categories.create!(name: "Pets")   # not in the seeded-name map
    client = FakeClient.new({ "categories" => [ { "name" => "Pets", "flexibility" => "flexible" } ] })
    assert_equal 1, Goals::CategoryClassifier.call(@account, client: client)
    assert_equal 1, client.calls
    assert_equal "flexible", pets.reload.flexibility
  end

  test "zero calls when every category is name-matched or already cached" do
    @account.categories.create!(name: "Restaurantes")                    # name-mapped
    @account.categories.create!(name: "Pets", flexibility: "essential")  # already cached
    client = FakeClient.new({})
    assert_equal 0, Goals::CategoryClassifier.call(@account, client: client)
    assert_equal 0, client.calls
  end

  test "a second run after caching makes no further call" do
    @account.categories.create!(name: "Pets")
    Goals::CategoryClassifier.call(@account, client: FakeClient.new({ "categories" => [ { "name" => "Pets", "flexibility" => "essential" } ] }))
    second = FakeClient.new({})
    assert_equal 0, Goals::CategoryClassifier.call(@account, client: second)
    assert_equal 0, second.calls
  end

  test "a client error leaves categories unresolved (no crash)" do
    @account.categories.create!(name: "Pets")
    raising = Object.new
    def raising.chat(**_) = raise(OpenRouterClient::Error, "boom")
    assert_equal 0, Goals::CategoryClassifier.call(@account, client: raising)
  end
end
