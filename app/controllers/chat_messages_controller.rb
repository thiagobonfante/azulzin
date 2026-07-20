# The chat composer POST (.plans/mobile/08 §3): stores the inbound bubble and hands it to
# the SAME pipeline job WhatsApp uses — the reply comes back as a broadcast chat bubble.
class ChatMessagesController < AppController
  def create
    @message = ChatMessage.new(user: Current.user, account: Current.account,
                               direction: "inbound", status: "received",
                               body: params.dig(:chat_message, :body).to_s.strip.presence)
    if (file = params.dig(:chat_message, :media)).present?
      @message.media.attach(file)
      @message.message_type = ChatMessage.message_type_for(@message.media_mime) || "text"
    end

    if @message.save
      ProcessInboundWhatsappJob.perform_later(@message.id)
    end
    respond_to do |format|
      format.turbo_stream { render :create, status: (@message.persisted? ? :ok : :unprocessable_entity) }
      format.html do
        redirect_to chat_path, alert: (@message.persisted? ? nil : @message.errors.full_messages.to_sentence)
      end
    end
  end
end
