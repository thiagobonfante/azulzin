require "mini_magick"
require "tempfile"

# Renders a scanned PDF's pages to PNG for the vision fallback (§5). Uses MiniMagick
# (ImageMagick + Ghostscript). If the rasterizer isn't available (e.g. no Ghostscript on the
# deploy image) it degrades to ParseError → the import fails parse_failed rather than crashing.
module Imports
  module PdfRasterizer
    module_function

    DENSITY = 150 # DPI — legible digits without ballooning the base64 payload

    def call(bytes, max_pages: DocumentImport::PDF_PAGE_CAP)
      Tempfile.create([ "import", ".pdf" ], binmode: true) do |pdf|
        pdf.write(bytes)
        pdf.flush
        page_count = [ MiniMagick::Image.open(pdf.path).pages.size, max_pages ].min
        (0...page_count).map { |index| render_page(pdf.path, index) }
      end
    rescue StandardError => e
      raise Imports::ParseError, "pdf rasterization failed: #{e.message}"
    end

    def render_page(pdf_path, index)
      Tempfile.create([ "page", ".png" ], binmode: true) do |out|
        MiniMagick.convert do |convert|
          convert.density(DENSITY)
          convert.background("white")
          convert << "#{pdf_path}[#{index}]"
          convert.flatten
          convert << out.path
        end
        out.rewind
        out.read
      end
    end
  end
end
