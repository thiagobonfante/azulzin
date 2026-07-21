# Share-to-app receipts (.plans/mobile/05 §1): the shells POST the shared photo/PDF here
# with the webview session cookie; the WhatsApp media pipeline does the rest.
class CapturesController < AppController
  # ponytail: the native shells POST directly (no form, no token). null_session + the
  # custom-header requirement closes cross-site abuse — browsers cannot send
  # X-Azulzin-Capture cross-site without a CORS preflight we never answer (05 §2).
  protect_from_forgery with: :null_session
  before_action :require_capture_header

  def create
    message = CaptureMessage.new(user: Current.user, account: Current.account,
                                 direction: "inbound", status: "received",
                                 body: params[:caption].to_s.strip.presence)
    message.media.attach(params.require(:file))
    message.message_type = CaptureMessage.message_type_for(message.media_mime) || "image"

    if message.save
      ProcessInboundWhatsappJob.perform_later(message.id)
      redirect_to transactions_path, notice: t(".received")
    else
      # 422, not a redirect: the shells key their "sent/failed" toast on the status —
      # both branches redirecting would make failure indistinguishable from success.
      head :unprocessable_entity
    end
  rescue ActionController::ParameterMissing
    head :unprocessable_entity
  end

  private

  def require_capture_header
    head :forbidden unless request.headers["X-Azulzin-Capture"] == "1"
  end
end
