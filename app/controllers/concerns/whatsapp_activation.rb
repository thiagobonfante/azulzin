module WhatsappActivation
  extend ActiveSupport::Concern

  private
    # Idempotently mint the code the user texts to the commercial number to prove ownership,
    # and stash it for the activation partial. No-op once the phone is verified. MUST run in
    # the controller because whatsapp_verification_code! mutates (persists the code).
    def prepare_whatsapp_activation
      return if Current.user.phone_verified?

      @whatsapp_activation_code = Current.user.whatsapp_verification_code!
    end
end
