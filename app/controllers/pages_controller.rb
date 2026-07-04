class PagesController < ApplicationController
  # The marketing home page is public (the generator's Authentication concern
  # otherwise gates every controller behind require_authentication).
  allow_unauthenticated_access

  def home
    # On the product-app host, a signed-in visitor belongs in the app, not on marketing.
    redirect_to dashboard_path if authenticated? && on_app_host?
  end

  # Host-aware robots.txt: the marketing apex is crawlable; the product app
  # (app.azulzin.com.br) is kept out of search indexes. Rendered here rather than
  # from public/ so it can vary by host.
  def robots
    rules = request.host == Rails.application.config.x.app_host ? "Disallow: /" : "Disallow:"
    render plain: "User-agent: *\n#{rules}\n", content_type: "text/plain"
  end
end
