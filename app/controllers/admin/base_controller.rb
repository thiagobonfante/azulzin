# Base for the admin area. Inherits Authentication + onboarding gate + "app" layout from
# AppController, then adds the admin-only gate. The admin area is a privileged surface over
# every user's financial data, so this gate is mandatory on every admin controller. See 07 §7.1.
class Admin::BaseController < AppController
  before_action :require_admin

  private
    def require_admin
      redirect_to dashboard_path, alert: t("admin.not_authorized") unless Current.user&.admin?
    end
end
