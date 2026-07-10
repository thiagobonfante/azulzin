require_relative "fake_sidecar_server"
require_relative "canned_ai"
require_relative "scenario"

module E2E
  TOKEN = "e2e-token"

  # Frozen time anchor for every E2E test: Wednesday 2026-05-20 12:00 São Paulo (15:00 UTC).
  # Mid-month, inside the 08–21 SP window (quiet hours), away from week/month boundaries,
  # and within Recurrence's BR-holiday coverage. Boundary scenarios travel deliberately
  # from here. One constant to bump. See .plans/e2e/01 §5.
  def self.anchor = Time.utc(2026, 5, 20, 15, 0)

  # Per-process monotonic sequence for unique identities (parallel workers have separate
  # DBs, so per-process uniqueness is enough).
  module Seq
    @n = 0
    @mutex = Mutex.new
    def self.next = @mutex.synchronize { @n += 1 }
  end

  # Shared by PipelineCase (rack inbound) and BrowserCase (socket inbound); each defines
  # its own #deliver_webhook.
  module Helpers
    def fake_sidecar = E2E::FakeSidecarServer.instance

    # -- WhatsApp inbound (byte-parity with fake.js /_inject → webhook envelope) ---------

    def wa_inject(jid, body, type: "chat", media: nil, message_id: nil)
      id = message_id || "fake_in_#{E2E::Seq.next}"
      data = { from: jid, message_id_serialized: id, type: type, body: body || "" }
      data[:media] = media if media
      deliver_webhook(event: "message_received", data: data)
      WhatsappMessage.find_by(wa_message_id: id)
    end

    def wa_connect!    = deliver_webhook(event: "connected", data: { phone_number: "5599999999999" })
    def wa_disconnect! = deliver_webhook(event: "disconnected", data: {})

    # -- WhatsApp outbound (asserted on the fake sidecar's capture: the user-visible artifact)

    def assert_wa_reply(jid, includes: nil, equals: nil)
      msgs = fake_sidecar.messages_to(jid)
      assert msgs.any?, "expected an outbound WhatsApp message to #{jid}; sidecar captured none"
      body = msgs.last.body
      Array(includes).each { |fragment| assert_includes body, fragment }
      assert_equal equals, body if equals
      body
    end

    def assert_no_wa_reply(jid)
      msgs = fake_sidecar.messages_to(jid)
      assert msgs.empty?, "expected no outbound WhatsApp message to #{jid}, got: #{msgs.map(&:body).inspect}"
    end

    # -- jobs -----------------------------------------------------------------------------

    def drain_jobs!(rounds: 20)
      rounds.times do
        return if enqueued_jobs.empty?
        perform_enqueued_jobs
      end
      raise "jobs still enqueued after #{rounds} drain rounds: " \
            "#{enqueued_jobs.map { |j| j["job_class"] }.inspect}"
    end

    # -- money ----------------------------------------------------------------------------

    def brl(cents) = ApplicationController.helpers.brl(cents)

    def assert_brl(cents, text, message = nil)
      assert_includes text, brl(cents), message
    end

    # -- AI canning (the only stubbed boundary in E2E) --------------------------------------

    def with_canned_ai(extraction: nil, transcript: nil, receipt: nil, &block)
      stubs = []
      stubs << [ Whatsapp::Extractor, :from_text, ->(*_a, **_k) { extraction } ] if extraction
      stubs << [ Whatsapp::SttClient, :transcribe, ->(*_a, **_k) { transcript } ] if transcript
      stubs << [ Whatsapp::ReceiptExtractor, :from_message, ->(*_a, **_k) { receipt } ] if receipt
      compose_stubs(stubs, &block)
    end

    private

    def compose_stubs(stubs, &block)
      return yield if stubs.empty?
      obj, name, impl = stubs.first
      obj.stub(name, impl) { compose_stubs(stubs.drop(1), &block) }
    end
  end
end
