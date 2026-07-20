# The bridge's registration POST (.plans/mobile/04 §3): the webview's session cookie
# authenticates, giving both Current.user and Current.session (the revocation FK).
class PushDevicesController < AppController
  def create
    PushDevice.register!(
      token: params.require(:token),
      platform: params.require(:platform),
      app_version: params[:app_version],
      user: Current.user,
      session: Current.session)
    head :no_content
  rescue ActiveRecord::RecordInvalid, ActionController::ParameterMissing
    head :unprocessable_entity
  end
end
