# Inbound audit trail — recent inbound messages with their voice-note audio / receipt
# thumbnail (Active Storage) plus the stored transcription + ai_result, for calibrating
# extraction quality against what users later edit or reverse. See 07 §7.6.
class Admin::WhatsappMessagesController < Admin::BaseController
  def index
    @messages = WhatsappMessage.inbound.includes(:user, media_attachment: :blob)
                               .order(created_at: :desc).limit(100)
  end

  def show
    @message = WhatsappMessage.includes(:user, :produced_transactions).find(params[:id])
  end
end
