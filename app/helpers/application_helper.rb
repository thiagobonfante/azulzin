module ApplicationHelper
  # Absolute URL to a path on the product app (app.azulzin.com.br). The public
  # marketing chrome (apex host) uses this so its "sign in" / "get started" CTAs
  # cross to the app subdomain. In development everything is one origin, so the
  # relative path is returned unchanged.
  def app_url(path)
    return path unless Rails.env.production?

    "#{request.protocol}#{Rails.application.config.x.app_host}#{path}"
  end

  # Circular institution avatar: the vendored SVG logo when present (recolored to the
  # brand color through `currentColor`), otherwise a brand-color monogram with
  # contrast-aware text. `size` is the diameter in px.
  def institution_avatar(institution, size: 40)
    box = "width:#{size}px;height:#{size}px"

    if institution.logo_path
      tag.span class: "inline-grid shrink-0 place-items-center overflow-hidden rounded-full bg-base-100 ring-1 ring-base-300/70",
               style: box do
        tag.span institution_logo_svg(institution.logo_path),
                 class: "block",
                 style: "width:#{(size * 0.6).round}px;height:#{(size * 0.6).round}px;color:#{institution.brand_color}"
      end
    else
      tag.span institution.initials,
               class: "inline-grid shrink-0 place-items-center rounded-full font-semibold leading-none",
               style: "#{box};background-color:#{institution.brand_color};" \
                      "color:#{institution.dark_text? ? '#1b1b1b' : '#ffffff'};font-size:#{(size * 0.36).round}px"
    end
  end

  # Sidebar nav item — active styling derived from the caller's `active` flag. An optional
  # `badge` element (e.g. the pending-tray count) is rendered right-aligned.
  def sidebar_link(label, path, active:, badge: nil, &icon)
    base  = "flex items-center gap-3 rounded-box px-3 py-2 text-sm font-medium transition-colors"
    state = active ? "bg-primary/10 text-primary" : "text-base-content/70 hover:bg-base-200"
    link_to path, class: "#{base} #{state}", aria: { current: ("page" if active) } do
      safe_join([ capture(&icon), tag.span(label, class: "flex-1"), badge ].compact)
    end
  end

  # The sidebar pending-tray count badge — always rendered (with a stable id so Turbo Streams
  # can replace it after an in-app resolve), hidden at zero.
  def pending_nav_badge
    count = Current.user.transactions.pending_inbox.count
    tag.span(count.positive? ? count : "", id: "sidebar_pending_count",
             class: "badge badge-warning badge-sm#{' hidden' if count.zero?}")
  end

  # Vendored SVG sources are immutable first-party assets — read each file once and cache
  # it at the module level (survives across requests), rather than re-reading from disk on
  # every render.
  LOGO_SOURCE_CACHE = {}

  private
    # Inlines a vendored institution SVG (trusted, first-party asset) so `currentColor`
    # picks up the brand color.
    def institution_logo_svg(path)
      (LOGO_SOURCE_CACHE[path] ||= Rails.root.join("app/assets/images", path).read.freeze).html_safe
    end
end
