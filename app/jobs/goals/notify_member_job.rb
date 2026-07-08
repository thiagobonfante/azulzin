module Goals
  # One member's weekly goals sweep (.plans/goals 03, re-scoped by 06 §2). For each active goal:
  # auto-conclude if achieved (records goal_achieved), else compute the deterministic check, write
  # the idempotent goal_checks row (the dashboard widget reads it), and — only on an alert-worthy
  # moment (delta-gate + 14-day cooldown) — record a goal_alert. RECORD-ONLY this phase: rows show
  # as dashboard banners, zero WhatsApp (Phase 3 adds the weekly guard + Notifications::Deliver).
  #
  # MUST share the "proactive_notify" concurrency group (key user_id) with reminders/budgets/
  # summaries so Deliver's daily-cap read-then-act stays race-free once Phase 3 turns the push on.
  class NotifyMemberJob < ApplicationJob
    queue_as :default

    limits_concurrency to: 1, group: "proactive_notify", key: ->(_account_id, user_id, *) { user_id }

    discard_on ActiveRecord::RecordNotFound

    COOLDOWN_DAYS = 14
    SEVERITY = { "on_track" => 0, "insufficient_data" => 0, "at_risk" => 1, "off_track" => 2 }.freeze

    def perform(account_id, user_id, as_of = Date.current)
      @account = Account.find(account_id)
      @user    = User.find(user_id)
      return unless @user.account == @account          # membership revoked mid-flight

      @as_of = as_of.to_date
      week   = @as_of.beginning_of_week                # ISO Monday

      @account.goals.active.find_each do |goal|
        if Goals::Progress.new(goal, as_of: @as_of).achieved?
          record_achievement(goal, week) if Goals::Achieve.call(goal)
          next
        end
        check = upsert_check(goal, week, Goals::Checker.call(goal, as_of: @as_of))
        alert(goal, check, week) if check.status.in?(%w[at_risk off_track])
      end
    end

    private
      # The DB unique [goal_id, period_start] index is the referee: the first member's job computes
      # and writes; a later member's job for the same week loads the existing row (03 §2).
      def upsert_check(goal, week, result)
        @account.goal_checks.create!(goal: goal, period_start: week, status: result.status,
                                     expected_cents: result.expected_cents, actual_cents: result.actual_cents,
                                     findings: result.findings)
      rescue ActiveRecord::RecordNotUnique
        goal.checks.find_by!(period_start: week)
      end

      # Delta-gate (worsened status OR a new finding type) + 14-day cooldown run BEFORE record! —
      # a persistent, already-reported problem never re-fires. Idempotent per (user, goal, week).
      def alert(goal, check, week)
        return unless alert_worthy?(goal, check, week)
        return if in_cooldown?(goal)
        Notification.record!(user: @user, account: @account, kind: "goal_alert",
                             subject: goal, period_key: week, payload: check.findings.first)
      end

      def alert_worthy?(goal, check, week)
        prev = goal.checks.where(period_start: ...week).order(period_start: :desc).first
        return true if prev.nil?
        return true if SEVERITY.fetch(check.status) > SEVERITY.fetch(prev.status)
        new_causes = check.findings.map { |f| f["finding"] } - (prev.findings || []).map { |f| f["finding"] }
        new_causes.any?
      end

      def in_cooldown?(goal)
        last = Notification.where(user: @user, kind: "goal_alert", subject: goal).order(created_at: :desc).first
        last && last.created_at.to_date > @as_of - COOLDOWN_DAYS
      end

      def record_achievement(goal, week)
        Notification.record!(user: @user, account: @account, kind: "goal_achieved",
                             subject: goal, period_key: week,
                             payload: { "goal" => goal.name, "amount_cents" => goal.target_cents })
      end
  end
end
