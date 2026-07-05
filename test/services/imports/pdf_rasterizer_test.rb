require "test_helper"

class Imports::PdfRasterizerTest < ActiveSupport::TestCase
  # Real rasterization (needs ImageMagick + Ghostscript). Skipped where the tools aren't present;
  # the pipeline degrades to ParseError there, which the job maps to parse_failed.
  test "renders each PDF page to a PNG" do
    skip "ImageMagick/Ghostscript not available" unless magick_available?

    pngs = Imports::PdfRasterizer.call(file_fixture("imports/statement.pdf").binread)
    assert_equal 1, pngs.size
    assert_equal [ 0x89, 0x50, 0x4E, 0x47 ], pngs.first[0, 4].bytes # PNG magic
  end

  test "respects the page cap" do
    skip "ImageMagick/Ghostscript not available" unless magick_available?

    pngs = Imports::PdfRasterizer.call(file_fixture("imports/pages26.pdf").binread, max_pages: 3)
    assert_equal 3, pngs.size
  end

  test "degrades to ParseError on unrenderable input" do
    assert_raises(Imports::ParseError) { Imports::PdfRasterizer.call("not a pdf at all") }
  end

  private

  def magick_available?
    system("magick", "-version", out: File::NULL, err: File::NULL) ||
      system("convert", "-version", out: File::NULL, err: File::NULL)
  end
end
