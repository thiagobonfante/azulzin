# Dashboard alert dismissal (.plans/up-tier 01 §4). Turbo Stream removal, house
# convention (transactions#destroy). Strictly scoped to the current member's rows in the
# current account — a cross-user or cross-account id is a 404, not someone else's dismiss.
class NotificationsController < AppController
  def dismiss
    @notification = Current.user.notifications.where(account: Current.account).find(params[:id])
    @notification.dismiss!
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: dashboard_path }
    end
  end
end
