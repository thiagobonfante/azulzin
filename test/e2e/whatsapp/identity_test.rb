require "test_helpers/e2e/pipeline_case"

# WA-ID: WhatsApp identity & verification through the real webhook (.plans/e2e/03 §1).
class E2E::WhatsappIdentityTest < E2E::PipelineCase
  # WA-ID-01
  test "handshake: unknown JID texting its AZUL code becomes verified" do
    s = E2E::Scenario.build(:solo_basic)
    code = s.owner.whatsapp_verification_code!

    msg = wa_inject(s.jid, "meu código é #{code}")

    assert_nil msg, "handshake short-circuits before persisting a WhatsappMessage"
    user = s.owner.reload
    assert user.phone_verified?
    assert_equal user.phone, user.whatsapp_id
    assert_equal s.jid, user.whatsapp_jid
    assert_nil user.whatsapp_verification_code
    assert_wa_reply(s.jid, equals: I18n.t("whatsapp.replies.verified", locale: :"pt-BR"))
  end

  # WA-ID-02
  test "9th-digit tolerance: a message from the digit-dropped JID still resolves and refreshes the reply address" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!
    variant_jid = "#{s.owner.phone.sub("55119", "5511")}@c.us"

    with_canned_ai(extraction: E2E::CannedAI.expense(cents: 1_000, merchant: "padaria")) do
      wa_inject(variant_jid, "padaria 10")
      drain_jobs!
    end

    assert_equal 1_000, s.account.transactions.sole.amount_cents
    assert_equal variant_jid, s.owner.reload.whatsapp_jid, "reply address must follow the sender JID"
  end

  # WA-ID-03
  test "collision: a code texted from an already-linked phone replies phone_already_linked" do
    a = E2E::Scenario.build(:solo_basic).wa_verified!
    # A second verified user holding the 9th-digit-dropped variant makes the JID ambiguous,
    # so resolution refuses (0 or ≥2) and the code scan reaches the unique-index collision.
    E2E::Scenario.build(:solo_basic).owner.update!(
      whatsapp_id: a.owner.phone.sub("55119", "5511"), phone_verified_at: Time.current)
    claimant = E2E::Scenario.build(:solo_basic)
    code = claimant.owner.whatsapp_verification_code!

    wa_inject(a.jid, "meu código #{code}")

    assert_wa_reply(a.jid, equals: I18n.t("whatsapp.replies.phone_already_linked", locale: :"pt-BR"))
    assert_nil claimant.owner.reload.whatsapp_id, "the claimant must NOT be bound to the taken number"
    assert_not claimant.owner.phone_verified?
  end

  # WA-ID-04 — the cap counter lives in Rails.cache (a no-op under the test null_store),
  # so swap in a real store for the duration.
  test "code-guess cap: 10 code-shaped guesses a day, the 11th is ignored even when correct" do
    s = E2E::Scenario.build(:solo_basic)
    code = s.owner.whatsapp_verification_code!

    Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
      10.times { |i| wa_inject(s.jid, "AZUL-XXX#{i}") }
      wa_inject(s.jid, code)
      assert_not s.owner.reload.phone_verified?, "over the cap even the right code is ignored"
      assert_equal 10, fake_sidecar.messages_to(s.jid).size,
                   "each under-cap wrong guess replies invalid_code; over the cap: silence"

      travel 1.day
      wa_inject(s.jid, code)
      assert s.owner.reload.phone_verified?, "the cap re-arms the next day"
    end
  end

  # WA-ID-12 — wrong code from a registered phone gets feedback, not the 6h silence (2026-07-11).
  test "wrong code from a registered phone replies invalid_code, nothing persisted" do
    s = E2E::Scenario.build(:solo_basic)
    s.owner.whatsapp_verification_code!

    assert_no_difference -> { WhatsappMessage.count } do
      wa_inject(s.jid, "meu codigo é AZUL-ZZZZ")
    end

    assert_not s.owner.reload.phone_verified?
    assert_wa_reply(s.jid, equals: I18n.t("whatsapp.replies.invalid_code", locale: :"pt-BR"))
    assert_empty enqueued_jobs
  end

  # WA-ID-13 — code attempt from a phone no user registered → sign-up nudge (2026-07-11).
  test "code attempt from an unregistered phone replies register_first" do
    jid = "5511800000002@c.us"

    wa_inject(jid, "AZUL-ZZZZ")

    assert_wa_reply(jid, equals: I18n.t("whatsapp.replies.register_first", locale: :"pt-BR"))
    assert_empty enqueued_jobs
  end

  # WA-ID-05 — the throttle also lives in Rails.cache.
  test "unknown sender: one throttled reply, then silence, nothing persisted" do
    jid = "5511800000001@c.us"

    Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
      assert_no_difference -> { WhatsappMessage.count } do
        wa_inject(jid, "oi")
        wa_inject(jid, "tem alguém aí?")
      end
    end

    assert_equal 1, fake_sidecar.messages_to(jid).size, "exactly one onboarding reply inside the window"
    assert_equal I18n.t("whatsapp.replies.unknown_sender", locale: :"pt-BR"),
                 fake_sidecar.messages_to(jid).sole.body
    assert_empty enqueued_jobs
  end

  # WA-ID-06
  test "oversized media: asked to resend, nothing persisted, no job" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!

    assert_no_difference -> { WhatsappMessage.count } do
      deliver_webhook(event: "message_received",
                      data: { from: s.jid, message_id_serialized: "big-#{E2E::Seq.next}",
                              type: "document", media_too_large: true })
    end

    assert_wa_reply(s.jid, equals: I18n.t("whatsapp.replies.media_too_large", locale: :"pt-BR"))
    assert_empty enqueued_jobs
  end

  # WA-ID-07
  test "redelivery: the same message_id yields one message, one transaction, one reply" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!

    with_canned_ai(extraction: E2E::CannedAI.expense(cents: 2_500, merchant: "farmácia")) do
      wa_inject(s.jid, "farmácia 25", message_id: "dup-1")
      drain_jobs!
      wa_inject(s.jid, "farmácia 25", message_id: "dup-1")
      drain_jobs!
    end

    assert_equal 1, WhatsappMessage.inbound.where(wa_message_id: "dup-1").count
    assert_equal 1, s.account.transactions.count
    assert_equal 1, fake_sidecar.messages_to(s.jid).size
  end

  # WA-ID-09
  test "stop command: consent off, one confirmation, expense capture keeps working" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!(consent: true)

    wa_inject(s.jid, "para de me avisar")
    drain_jobs!

    assert_not s.owner.reload.notification_prefs.whatsapp_consent?
    assert_wa_reply(s.jid, equals: I18n.t("whatsapp.replies.notifications_stopped", locale: :"pt-BR"))

    with_canned_ai(extraction: E2E::CannedAI.expense(cents: 3_000, merchant: "mercado")) do
      wa_inject(s.jid, "mercado 30")
      drain_jobs!
    end
    assert_equal 1, s.account.transactions.count, "stop opts out of pushes, never out of capture"
  end

  # WA-ID-10
  test "removed member: their next message posts into their fresh solo account, never the old family ledger" do
    s = E2E::Scenario.build(:couple)
    partner = s.partner
    old_count = s.account.transactions.count

    Accounts::RemoveMember.call(s.account.memberships.find_by!(user: partner))

    with_canned_ai(extraction: E2E::CannedAI.expense(cents: 4_200, merchant: "posto")) do
      wa_inject(s.jid(partner), "posto 42")
      drain_jobs!
    end

    new_account = partner.reload.account
    assert_not_equal s.account.id, new_account.id
    assert_equal 4_200, new_account.transactions.sole.amount_cents
    assert_equal old_count, s.account.reload.transactions.count, "the family ledger is untouched"
  end

  # WA-ID-11
  test "connection events flip the singleton state" do
    wa_connect!
    assert WhatsappConnection.instance.reload.connected?
    wa_disconnect!
    assert_not WhatsappConnection.instance.reload.connected?
  end
end
