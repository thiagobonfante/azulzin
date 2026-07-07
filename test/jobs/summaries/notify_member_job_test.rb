require "test_helper"

# One member's digest, end to end (up-tier 04 §2, §4–5): Summaries::Build →
# Notification.record! (period_key = the week's Monday / the month's first, so re-runs
# dedupe) → Notifications::Deliver. Summaries are OPT-IN (default false) and pure push:
# an opted-out member gets NO row at all — a dashboard "recap" they never asked for is
# the opt-out surprise 04 §4 bans.
class Summaries::NotifyMemberJobTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  MONDAY = Date.new(2026, 7, 6)

  setup do
    @user    = users(:confirmed)
    @account = @user.account
    @inst    = Institution.find_by(code: "260")
    @bank    = BankAccount.create!(account: @account, institution: @inst)
    travel_to Time.utc(2026, 7, 12, 23, 0)   # Sunday 20:00 SP — the weekly dispatch moment
  end

  def run_for(user = @user, period: "weekly")
    Summaries::NotifyMemberJob.perform_now(@account.id, user.id, period)
  end

  def seed_week!
    cat = @account.categories.create!(name: "Mercado")
    @account.transactions.create!(direction: "expense", status: "posted", amount_cents: 42_000,
                                  occurred_on: Date.new(2026, 7, 8), category: cat, bank_account: @bank)
    Commitment.create!(account: @account, bank_account: @bank, name: "Luz", kind: "fixed",
                       amount_cents: 18_240, schedule_day: 13, starts_on: Date.new(2026, 7, 1))
  end

  test "opted-in member → one weekly row with the built payload; a re-run dedupes (one per week)" do
    @user.notification_prefs.update!(weekly_summary: true)
    seed_week!

    assert_difference(-> { Notification.count }, 1) { run_for }
    assert_no_difference(-> { Notification.count }) { run_for }

    row = Notification.find_by!(kind: "weekly_summary")
    assert_equal @user, row.user
    assert_nil row.subject
    assert_equal MONDAY, row.period_key
    assert_equal 42_000, row.payload["spent_cents"]
    assert_equal [ { "name" => "Luz", "cents" => 18_240 } ], row.payload["upcoming"]
    assert_nil row.whatsapp_sent_at, "no consent → dashboard-only, no claim burned"
  end

  test "opted-out member (the default) → NO row at all, not even a dashboard one" do
    seed_week!

    assert_no_difference(-> { Notification.count }) { run_for }
  end

  test "two members: only the opted-in one gets a row" do
    other = User.create!(email_address: "member@example.com", password: "password123")
    @account.add_member!(other)
    other.notification_prefs.update!(weekly_summary: true)
    seed_week!

    run_for(@user)
    run_for(other)
    assert_equal [ other.id ], Notification.where(kind: "weekly_summary").pluck(:user_id)
  end

  test "zero-activity week → no row even for an opted-in member (04 §4: no empty summary)" do
    @user.notification_prefs.update!(weekly_summary: true)

    assert_no_difference(-> { Notification.count }) { run_for }
  end

  test "monthly period → one monthly_summary row recapping the prior month; re-run dedupes" do
    @user.notification_prefs.update!(monthly_summary: true)
    @account.transactions.create!(direction: "income", status: "posted", amount_cents: 850_000,
                                  occurred_on: Date.new(2026, 7, 5), bank_account: @bank)
    travel_to Time.utc(2026, 8, 1, 11, 0)   # 08:00 SP on the 1st

    assert_difference(-> { Notification.count }, 1) { run_for(period: "monthly") }
    assert_no_difference(-> { Notification.count }) { run_for(period: "monthly") }

    row = Notification.find_by!(kind: "monthly_summary")
    assert_equal Date.new(2026, 7, 1), row.period_key
    assert_equal 850_000, row.payload["in_cents"]
    assert_equal "2026-07-01", row.payload["month"]
  end

  test "the weekly toggle does not open the monthly door (and vice versa)" do
    @user.notification_prefs.update!(weekly_summary: true, monthly_summary: false)
    @account.transactions.create!(direction: "income", status: "posted", amount_cents: 850_000,
                                  occurred_on: Date.new(2026, 7, 5), bank_account: @bank)
    travel_to Time.utc(2026, 8, 1, 11, 0)

    assert_no_difference(-> { Notification.count }) { run_for(period: "monthly") }
  end

  test "a member no longer in the account gets nothing" do
    outsider = users(:english)
    outsider.notification_prefs.update!(weekly_summary: true)
    seed_week!

    assert_no_difference -> { Notification.count } do
      Summaries::NotifyMemberJob.perform_now(@account.id, outsider.id, "weekly")
    end
  end

  test "consented + opted-in but sidecar down → dashboard row intact, claim NOT burned, nothing sent" do
    push_ready!
    WhatsappConnection.instance.update!(status: "disconnected")
    seed_week!

    assert_no_difference(-> { WhatsappMessage.count }) { run_for }
    row = Notification.find_by!(kind: "weekly_summary")
    assert_nil row.whatsapp_sent_at
    assert_includes Notification.dashboard_for(@user, @account), row
  end

  test "push-ready member → the digest goes out, localized, claim stamped" do
    push_ready!
    WhatsappConnection.instance.update!(status: "connected")
    seed_week!

    bodies = []
    WhatsappService.stub(:send_message, ->(_to, body) { bodies << body; { id: "out-1" } }) { run_for }

    assert_includes bodies.sole, "*Resumo da semana*"
    assert_includes bodies.sole, "Mercado R$ 420,00", "the category line is built in the recipient's locale"
    assert_includes bodies.sole, "Luz (R$ 182,40)", "the look-ahead names the next bill"
    assert_not_nil Notification.find_by!(kind: "weekly_summary").whatsapp_sent_at
  end

  private

  def push_ready!
    @user.update!(phone: "5511912345678", phone_verified_at: Time.current,
                  whatsapp_id: "5511912345678", whatsapp_jid: "5511912345678@c.us")
    @user.notification_prefs.update!(weekly_summary: true, whatsapp_consent: true,
                                     wa_intro_sent_at: 1.week.ago)
  end
end
