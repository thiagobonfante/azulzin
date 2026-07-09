module Whatsapp
  # Starts the conversational goal-creation flow (round 3 decision 8). The ONE Extractor
  # call that classified create_goal also seeds the slots; everything after is deterministic
  # Q&A in GoalFlowRouter (zero LLM). Also the lazy janitor: stale open conversations — and
  # their invisible draft Goals, which would leak the monthly AI-session quota — are
  # destroyed on every new start (the recommended lazy cleanup for TTL expiry).
  class GoalFlowHandler
    include HandlerHelpers

    def initialize(msg, extraction)
      @msg = msg
      @extraction = extraction
    end

    def call
      return reply("goal_flow.limit_reached") if account.goals.active.count >= Goal::MAX_ACTIVE
      self.class.close_open!(user)
      conv = account.goal_conversations.create!(user: user, status: "collecting",
               data: seed_data, expires_at: GoalConversation::TTL.from_now)
      GoalFlowRouter.new(conv, @msg, "").ask_next
    end

    # The lazy janitor, shared with GoalReplanHandler (the one-open-per-user index means any
    # new conversation must close whatever is open first): stale or superseded open chats —
    # and their invisible draft Goals, which would leak the monthly AI-session quota — are
    # destroyed before a new conversation starts.
    def self.close_open!(user)
      GoalConversation.where(user: user).where.not(status: "closed").find_each do |conv|
        conv.goal.destroy! if conv.goal&.draft?
        conv.update!(status: "closed")
      end
    end

    private

    # Deterministic Ruby parsing of the trigger's raw fields — the LLM never emits ISO dates
    # or cents (Money.to_cents / GoalMonthPhrase do the arithmetic). Only positive/valid
    # values seed a slot; anything else gets asked.
    def seed_data
      target  = Money.to_cents(@extraction.amount_raw)
      initial = Money.to_cents(@extraction.goal_initial_saved_raw)
      month   = GoalMonthPhrase.parse(@extraction.goal_month_phrase, reference: sp_today)
      data = {
        "kind"                => (@extraction.goal_kind if Goal.kinds.key?(@extraction.goal_kind)),
        "name"                => @extraction.goal_name.presence&.first(80),
        "target_cents"        => (target if target&.positive?),
        "target_month"        => month&.iso8601,
        "initial_saved_cents" => (initial if initial&.positive?)
      }.compact
      # A seeded head start at/above the seeded target can't be a goal — drop it and ask.
      if data["target_cents"] && data["initial_saved_cents"].to_i >= data["target_cents"]
        data.delete("initial_saved_cents")
      end
      data
    end
  end
end
