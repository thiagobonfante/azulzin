module ApplicationHelper
  # Absolute URL to a path on the product app (app.azulzin.com.br). The public
  # marketing chrome (apex host) uses this so its "sign in" / "get started" CTAs
  # cross to the app subdomain. In development everything is one origin, so the
  # relative path is returned unchanged.
  def app_url(path)
    return path unless Rails.env.production?

    "#{request.protocol}#{Rails.application.config.x.app_host}#{path}"
  end
end
