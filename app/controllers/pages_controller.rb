class PagesController < ApplicationController
  # The marketing home page is public (the generator's Authentication concern
  # otherwise gates every controller behind require_authentication).
  allow_unauthenticated_access

  def home
  end
end
