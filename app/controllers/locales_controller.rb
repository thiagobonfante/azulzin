class LocalesController < ApplicationController
  allow_unauthenticated_access             # guests can switch too

  def update
    loc = params[:locale].to_s
    if Rails.application.config.x.supported_locales.key?(loc)
      Current.user&.update(locale: loc)
      session[:locale] = loc
    end
    redirect_back fallback_location: root_path
  end
end
