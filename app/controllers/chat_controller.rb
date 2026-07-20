# The in-app conversation thread (.plans/mobile/08) — the Chat tab's target.
class ChatController < AppController
  def show
    @messages = ChatMessage.thread_for(Current.user)
  end
end
