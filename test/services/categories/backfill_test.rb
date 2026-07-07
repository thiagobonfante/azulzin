require "test_helper"

class Categories::BackfillTest < ActiveSupport::TestCase
  setup do
    @user    = users(:confirmed)
    @account = @user.account
    Categories::SeedDefaults.call(@account, locale: "pt-BR")
    @mercado      = @account.categories.find_by(name: "Mercado")
    @restaurantes = @account.categories.find_by(name: "Restaurantes")
  end

  def spend!(merchant, category: nil, source: nil, status: "posted")
    @account.transactions.create!(
      created_by: @user, direction: "expense", status: status,
      confirmed_at: (Time.current if status == "posted"),
      amount_cents: 1_000, merchant: merchant, occurred_on: Date.current,
      category_id: category&.id, category_source: source, source: "manual"
    )
  end

  # A fake client that answers every batch with a fixed category label.
  def client_answering(label)
    client = Object.new
    client.define_singleton_method(:chat) do |messages:, schema:|
      rows = JSON.parse(messages.last[:content].split("\n\n").first)
      Struct.new(:parsed).new({ "rows" => rows.map { |r| { "id" => r["id"], "category" => label } } })
    end
    client
  end

  test "memory pass categorizes repeat merchants for free (rows the LLM never sees)" do
    spend!("Zaffari", category: @mercado, source: "user")
    2.times { spend!("Zaffari") }
    never_called = Object.new
    never_called.define_singleton_method(:chat) { |**| raise "LLM must not see memory-resolvable rows... but other rows may go" }

    # Only Zaffari rows exist uncategorized → LLM pass gets an empty set and must not be called.
    assert_equal 2, Categories::Backfill.call(@account, client: never_called)
    assert_equal 2, @account.transactions.where(category_source: "memory", category_id: @mercado.id).count
  end

  test "LLM pass resolves closed-set answers and stamps ai; unresolvable answers leave nil" do
    spend!("Churrascaria Zé")
    assert_equal 1, Categories::Backfill.call(@account, client: client_answering("restaurantes"))
    txn = @account.transactions.where(merchant: "Churrascaria Zé").sole
    assert_equal @restaurantes, txn.category
    assert_equal "ai", txn.category_source

    spend!("Loja Misteriosa")
    assert_equal 0, Categories::Backfill.call(@account, client: client_answering("xyzzy"))
    assert_nil @account.transactions.where(merchant: "Loja Misteriosa").sole.category_id
  end

  test "already-categorized, non-posted, and non-expense rows are untouched (idempotent re-run)" do
    keep = spend!("iFood", category: @restaurantes, source: "user")
    pending = spend!("Posto", status: "pending_review")
    Categories::Backfill.call(@account, client: client_answering("mercado"))
    assert_equal @restaurantes.id, keep.reload.category_id
    assert_equal "user", keep.category_source
    assert_nil pending.reload.category_id
  end
end
