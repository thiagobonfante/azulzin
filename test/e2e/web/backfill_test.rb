require "test_helpers/e2e/pipeline_case"

# WEB-TX-11: the auto-categorization backfill journey — memory pass, closed-set LLM batch,
# provenance stamps, the one-run-per-day guard, and the undo that reverts ONLY machine rows
# (.plans/e2e/05 §2). Previously uncovered anywhere in the suite.
class E2E::WebBackfillTest < E2E::PipelineCase
  test "backfill: memory then LLM stamp provenance; undo reverts machines only; daily guard holds" do
    s = E2E::Scenario.build(:solo_basic)
    sign_in_as s.owner

    # Merchant memory material: two USER-categorized Padaria Sol rows…
    2.times do |i|
      s.expense(merchant: "Padaria Sol", category: "Mercado", instrument: s.itau,
                cents: 2_000 + i, on: Date.current - 10 - i)
    end
    # …and the uncategorized backlog: two memory-eligible, one for the LLM, one human row.
    uncat = ->(merchant, cents) do
      s.expense(merchant: merchant, category: "Outros", instrument: s.itau,
                cents: cents, on: Date.current - 5)
        .update!(category_id: nil, category_source: nil)
    end
    uncat.call("Padaria Sol", 3_100)
    uncat.call("Padaria Sol", 3_200)
    uncat.call("Loja Zeta", 9_900)
    human = s.expense(merchant: "Farmácia", category: "Saúde", instrument: s.itau,
                      cents: 4_400, on: Date.current - 4)

    with_canned_backfill_llm("Loja Zeta" => "Vestuário") do
      post backfill_categories_path
      assert_redirected_to transactions_path
      drain_jobs!
    end

    padaria = s.account.transactions.where(merchant: "Padaria Sol", category_source: "memory")
    assert_equal 2, padaria.count, "memory pass owns the repeat merchant"
    assert padaria.all? { |t| t.category_id == s.category("Mercado").id }

    zeta = s.account.transactions.find_by!(merchant: "Loja Zeta")
    assert_equal "ai", zeta.category_source
    assert_equal s.category("Vestuário").id, zeta.category_id
    assert_equal "user", human.reload.category_source, "human rows are never restamped"
    assert s.account.reload.category_backfill_at.present?

    # Daily guard: a second run the same day bounces, enqueues nothing.
    assert_no_enqueued_jobs(only: CategorizeHistoryJob) do
      post backfill_categories_path
    end
    assert_redirected_to categories_path
    assert_equal I18n.t("categories.backfill.ran_recently"), flash[:alert]

    # Undo reverts EXACTLY the machine rows of the run window.
    post backfill_undo_categories_path
    assert_nil zeta.reload.category_id
    assert_equal 2, s.account.transactions.where(merchant: "Padaria Sol", category_id: nil).count
    assert_equal s.category("Saúde").id, human.reload.category_id, "undo never touches human rows"
    assert_nil s.account.reload.category_backfill_at, "undo re-arms the daily guard"
  end

  private

  # Fake OpenRouter client for the closed-set batch: answers by merchant name using
  # batch-local ids, exactly like the real schema response.
  def with_canned_backfill_llm(mapping, &block)
    fake = Object.new
    fake.define_singleton_method(:chat) do |messages:, schema:|
      rows = JSON.parse(messages.last[:content].lines.first)
      answers = rows.filter_map do |row|
        category = mapping[row["merchant"]]
        { "id" => row["id"], "category" => category } if category
      end
      response = Object.new
      response.define_singleton_method(:parsed) { { "rows" => answers } }
      response
    end
    OpenRouterClient.stub(:new, ->(**_) { fake }, &block)
  end
end
