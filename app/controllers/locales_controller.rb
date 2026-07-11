class LocalesController < ApplicationController
  allow_unauthenticated_access             # guests can switch too
  before_action :resume_session            # skip-auth also skips session resume — restore it so a
                                           # signed-in switch persists to user.locale (mailers read it)

  def update
    loc = params[:locale].to_s
    if Rails.application.config.x.supported_locales.key?(loc)
      Current.user&.update(locale: loc)
      session[:locale] = loc
    end
    redirect_back fallback_location: root_path
  end
end
