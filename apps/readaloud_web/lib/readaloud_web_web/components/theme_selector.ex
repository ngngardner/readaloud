defmodule ReadaloudWebWeb.ThemeSelector do
  use Phoenix.Component

  @dark_themes ~w(dark dracula night coffee dim sunset abyss vampire blood)
  @light_themes ~w(light cupcake bumblebee emerald corporate retro cyberpunk valentine garden lofi pastel fantasy wireframe cmyk autumn acid lemonade nord silk)

  def theme_modal(assigns) do
    assigns =
      assigns
      |> assign(:dark_themes, @dark_themes)
      |> assign(:light_themes, @light_themes)

    ~H"""
    <dialog id="theme-modal" class="modal">
      <div class="modal-box max-w-md">
        <div class="flex justify-between items-center mb-4">
          <h3 class="font-bold text-lg">Choose Theme</h3>
          <form method="dialog"><button class="btn btn-ghost btn-sm btn-circle">&times;</button></form>
        </div>

        <div class="mb-4">
          <div class="text-xs uppercase tracking-widest text-base-content/50 mb-2">Dark Themes</div>
          <div class="grid grid-cols-3 gap-2">
            <button :for={theme <- @dark_themes} phx-click="set_theme" phx-value-theme={theme}
              class="btn btn-sm btn-ghost justify-start gap-2">
              <div class="flex gap-0.5">
                <div class="w-2 h-2 rounded-full" data-theme={theme} style="background: var(--color-base-100)"></div>
                <div class="w-2 h-2 rounded-full" data-theme={theme} style="background: var(--color-primary)"></div>
                <div class="w-2 h-2 rounded-full" data-theme={theme} style="background: var(--color-secondary)"></div>
                <div class="w-2 h-2 rounded-full" data-theme={theme} style="background: var(--color-accent)"></div>
              </div>
              <span class="text-xs capitalize"><%= theme %></span>
            </button>
          </div>
        </div>

        <div>
          <div class="text-xs uppercase tracking-widest text-base-content/50 mb-2">Light Themes</div>
          <div class="grid grid-cols-3 gap-2">
            <button :for={theme <- @light_themes} phx-click="set_theme" phx-value-theme={theme}
              class="btn btn-sm btn-ghost justify-start gap-2">
              <div class="flex gap-0.5">
                <div class="w-2 h-2 rounded-full" data-theme={theme} style="background: var(--color-base-100)"></div>
                <div class="w-2 h-2 rounded-full" data-theme={theme} style="background: var(--color-primary)"></div>
                <div class="w-2 h-2 rounded-full" data-theme={theme} style="background: var(--color-secondary)"></div>
                <div class="w-2 h-2 rounded-full" data-theme={theme} style="background: var(--color-accent)"></div>
              </div>
              <span class="text-xs capitalize"><%= theme %></span>
            </button>
          </div>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop"><button>close</button></form>
    </dialog>
    """
  end
end
