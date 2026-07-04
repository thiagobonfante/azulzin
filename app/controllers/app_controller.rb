# Base controller for the authenticated product app: the sidebar shell layout plus the
# onboarding gate. Auth itself comes from ApplicationController (require_authentication).
class AppController < ApplicationController
  layout "app"
  before_action :require_onboarding
end
