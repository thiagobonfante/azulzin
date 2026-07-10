require "test_helpers/e2e/browser_case"

# CT: contract smokes against the REAL node fake sidecar (whatsapp-sidecar/fake.js) — the
# tripwire that keeps the in-process Ruby FakeSidecarServer honest (.plans/e2e/03 §6).
#
# Opt-in and serial:
#   E2E_SIDECAR=node PARALLEL_WORKERS=1 bin/rails test test/system/journeys/contract_sidecar_test.rb
#
# fake.js /_inject AWAITS the Rails webhook before answering, so a 200 means the message
# already landed — no cross-process polling.
class JourneysContractSidecarTest < E2E::BrowserCase
  SIDECAR_DIR = Rails.root.join("whatsapp-sidecar")

  setup do
    skip "contract lane runs only with E2E_SIDECAR=node" unless ENV["E2E_SIDECAR"] == "node"
    skip "whatsapp-sidecar/node_modules missing — run npm ci first" unless SIDECAR_DIR.join("node_modules").exist?
    boot_node_fake!
  end

  teardown do
    # Point outbound back at the in-process Ruby fake for whatever runs next.
    ENV["WHATSAPP_SERVICE_URL"] = "http://127.0.0.1:#{E2E::FakeSidecarServer.instance.port}"
  end

  # CT-01 — envelope parity: what fake.js posts is what wa_inject fabricates
  test "an /_inject text lands in Rails shaped exactly like the Ruby fake's envelope" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!

    node_inject(jid: s.jid, body: "parity check 12,34")

    via_node = WhatsappMessage.inbound.where(user: s.owner).sole
    assert_match(/\Afake_in_/, via_node.wa_message_id)
    assert_equal "text", via_node.message_type
    assert_equal s.jid, via_node.chat_id
    assert_equal "parity check 12,34", via_node.body

    twin = wa_inject(s.jid, "parity check 12,34")   # the Ruby fake's fabrication
    assert_equal [ via_node.message_type, via_node.chat_id, via_node.body ],
                 [ twin.message_type, twin.chat_id, twin.body ],
                 "fake.js and wa_inject must produce indistinguishable messages"
  end

  # CT-02 — full round trip: expense in, reply lands as an out-bubble in the node fake
  test "a captured expense replies into the node fake's chat state" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!

    with_canned_ai(extraction: E2E::CannedAI.expense(cents: 5_490, merchant: "mercado",
                                                     method: "debito", instrument: "itau")) do
      node_inject(jid: s.jid, body: "mercado 54,90")
      drain_jobs!
    end

    assert_equal 5_490, s.account.transactions.sole.amount_cents
    out = node_state.select { |e| e["dir"] == "out" && e["jid"] == s.jid }
    assert out.any? { |e| e["body"].include?("Lançado") && e["body"].include?(brl(5_490)) },
           "the confirmation must land as an out bubble, got: #{out.inspect}"
  end

  # CT-03 — media base64 round trip
  test "an injected image arrives byte-identical" do
    s = E2E::Scenario.build(:solo_basic).wa_verified!
    bytes = File.binread(Rails.root.join("test/fixtures/files/receipt.jpg"))

    receipt = E2E::CannedAI.expense(cents: 8_750, merchant: "Nota", method: "debito",
                                    instrument: "itau", modality: "image")
    with_canned_ai(receipt: receipt) do
      node_inject(jid: s.jid, body: "", type: "image",
                  media: { data: Base64.strict_encode64(bytes),
                           mimetype: "image/jpeg", filename: "receipt.jpg" })
      drain_jobs!
    end

    msg = WhatsappMessage.inbound.where(user: s.owner).sole
    assert msg.media.attached?
    assert_equal bytes, msg.media.blob.download, "media must survive the base64 round trip"
  end

  # CT-04 — session initialize announces connected back through the webhook
  test "initialize_session flips the connection singleton green" do
    WhatsappConnection.instance.mark_disconnected!("test")

    result = WhatsappService.initialize_session

    assert_nil result[:error]
    assert WhatsappConnection.instance.reload.connected?
  end

  # CT-05 — bearer mismatch degrades, never raises
  test "a wrong bearer token gets a sidecar 401 error hash" do
    previous = ENV["WHATSAPP_SERVICE_TOKEN"]
    ENV["WHATSAPP_SERVICE_TOKEN"] = "wrong-token"
    result = WhatsappService.send_message("5511900000000@c.us", "oi")
    assert_equal "sidecar 401", result[:error]
  ensure
    ENV["WHATSAPP_SERVICE_TOKEN"] = previous
  end

  # CT-06 — the verification handshake end-to-end through the node fake (mirrors WA-ID-01): an
  # unverified number texts its AZUL code → verified, and the golden reply lands as an out bubble.
  test "the verification handshake completes through the node fake" do
    s = E2E::Scenario.build(:solo_basic)
    code = s.owner.whatsapp_verification_code!

    node_inject(jid: s.jid, body: "meu código é #{code}")

    assert s.owner.reload.phone_verified?, "the code text verifies the number"
    out = node_state.select { |e| e["dir"] == "out" && e["jid"] == s.jid }
    assert out.any? { |e| e["body"] == I18n.t("whatsapp.replies.verified", locale: :"pt-BR") },
           "the verified reply must land as an out bubble, got: #{out.inspect}"
  end

  private

  mattr_accessor :node_port

  def boot_node_fake!
    visit root_path   # boots the Capybara server the node fake will post back to
    server = Capybara.current_session.server

    if self.class.node_port.nil?
      port = TCPServer.open("127.0.0.1", 0) { |s| s.addr[1] }
      log  = Rails.root.join("tmp/e2e-node-fake.log").to_s
      pid  = Process.spawn(
        { "PORT" => port.to_s,
          "RAILS_WEBHOOK_URL" => "http://#{server.host}:#{server.port}/api/whatsapp/webhook",
          "RAILS_API_TOKEN" => E2E::TOKEN },
        "node", "fake.js", chdir: SIDECAR_DIR.to_s, out: log, err: log)
      at_exit { Process.kill("TERM", pid) rescue nil }
      self.class.node_port = port
      wait_for_health!(port)
    end
    ENV["WHATSAPP_SERVICE_URL"] = "http://127.0.0.1:#{self.class.node_port}"
  end

  def wait_for_health!(port, deadline: 10)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    loop do
      begin
        return if Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/health")).code == "200"
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET
      end
      raise "node fake.js did not boot (see tmp/e2e-node-fake.log)" if
        Process.clock_gettime(Process::CLOCK_MONOTONIC) - started > deadline
      Kernel.sleep 0.1   # cross-process boot poll — the one legitimate sleep in the suite
    end
  end

  def node_base = "http://127.0.0.1:#{self.class.node_port}"

  def node_inject(jid:, body:, type: "text", media: nil)
    payload = { jid: jid, body: body, type: type }
    payload[:media] = media if media
    res = Net::HTTP.post(URI("#{node_base}/_inject"), payload.to_json,
                         "Content-Type" => "application/json")
    raise "inject failed: #{res.code} #{res.body}" unless res.code == "200"
  end

  def node_state
    JSON.parse(Net::HTTP.get(URI("#{node_base}/_state")))
  end
end
