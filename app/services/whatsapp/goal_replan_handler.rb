module Whatsapp
  # Starts the "reorganizar" chat (round 4) — the deterministic pre-pass keyword the risk
  # alerts advertise. ZERO LLM: no extraction, no narrative; the offer numbers come from
  # Goals::ReplanOffer and the reply parsing is a numbered pick. One active purchase goal →
  # straight to the offer; several → numbered pick; none → a friendly nudge. State rides
  # goal_conversations (one open per user — anything open is superseded first).
  class GoalReplanHandler
    include HandlerHelpers

    def initialize(msg)
      @msg = msg
    end

    def call
      candidates = account.goals.active.where(kind: "purchase").order(created_at: :asc).to_a
      return reply("goal_replan.none") if candidates.empty?
      GoalFlowHandler.close_open!(user)
      conv = account.goal_conversations.create!(user: user, status: "replan_picking_goal",
               data: { "options" => candidates.map(&:id) }, expires_at: GoalConversation::TTL.from_now)
      if candidates.size == 1
        GoalFlowRouter.new(conv, @msg, "").present_replan_offer(candidates.first)
      else
        # Goals have no display_name (the shared numbered_options helper's contract) — name it is.
        reply("goal_replan.pick",
              options: candidates.each_with_index.map { |g, i| "#{i + 1}. #{g.name}" }.join("\n"))
      end
    end
  end
end
