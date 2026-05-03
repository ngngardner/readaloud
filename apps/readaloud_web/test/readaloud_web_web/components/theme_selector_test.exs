defmodule ReadaloudWebWeb.ThemeSelectorTest do
  use ReadaloudWebWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias ReadaloudWebWeb.ThemeSelector

  # Regression guard: JS.dispatch(..., to: "window") silently no-ops in
  # Phoenix.LiveView 1.1+ because LV resolves `to:` via querySelectorAll, and
  # there is no <window> element. The fix is to omit `to:` and let the event
  # bubble from the source element to window.
  # Rendered phx-click attributes are HTML-entity encoded (`&quot;` for `"`),
  # so assertions match against the encoded form.
  describe "phx-click rendering" do
    test "swatches dispatch readaloud:set-theme without to: window" do
      html =
        render_component(&ThemeSelector.theme_swatches/1,
          themes: ["dark", "light"],
          label: "All"
        )

      assert html =~ "&quot;event&quot;:&quot;readaloud:set-theme&quot;"
      refute html =~ "&quot;to&quot;:&quot;window&quot;"
    end

    test "modal dark/light themes dispatch readaloud:set-theme without to: window" do
      html = render_component(&ThemeSelector.theme_modal/1, [])

      assert html =~ "&quot;event&quot;:&quot;readaloud:set-theme&quot;"
      refute html =~ "&quot;to&quot;:&quot;window&quot;"
    end
  end
end
