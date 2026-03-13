defmodule ReadaloudWebWeb.Sidebar do
  use Phoenix.Component
  use ReadaloudWebWeb, :html

  attr :active, :atom, required: true
  attr :task_count, :integer, default: 0

  def sidebar(assigns) do
    ~H"""
    <aside
      id="sidebar"
      phx-hook="SidebarHook"
      class="fixed left-0 top-0 h-full z-40 w-14 hover:w-[200px] transition-all duration-200
             bg-base-200/95 backdrop-blur-xl border-r border-base-content/6
             flex flex-col items-start overflow-hidden
             max-sm:translate-x-[-100%] max-sm:w-[200px]"
      data-expanded="false"
    >
      <%!-- Logo --%>
      <div class="flex items-center gap-2.5 px-[9px] pt-3.5 pb-5 min-h-[60px]">
        <div class="w-9 h-9 min-w-9 rounded-[10px] bg-gradient-to-br from-indigo-500 to-violet-500
                    flex items-center justify-center">
          <.icon name="hero-speaker-wave-solid" class="w-[18px] h-[18px] text-white" />
        </div>
        <span class="text-base font-bold tracking-tight whitespace-nowrap opacity-0
                     transition-opacity">
          Readaloud
        </span>
      </div>

      <%!-- Nav items --%>
      <.nav_item icon="hero-book-open" label="Library" href={~p"/"} active={@active == :library} />
      <.nav_item
        icon="hero-chart-bar"
        label="Tasks"
        href={~p"/tasks"}
        active={@active == :tasks}
        badge={@task_count}
      />

      <div class="flex-1" />

      <%!-- Bottom items --%>
      <button
        onclick="document.getElementById('theme-modal').showModal()"
        class="flex items-center gap-3 w-full px-2 py-2.5 mx-0 rounded-[10px] hover:bg-base-content/8 transition-colors"
        aria-label="Theme"
      >
        <div class="w-10 h-10 min-w-10 flex items-center justify-center">
          <.icon name="hero-sun" class="w-[18px] h-[18px] text-base-content/50" />
        </div>
        <span class="text-sm text-base-content/60 whitespace-nowrap">Theme</span>
      </button>

      <div class="pb-3" />
    </aside>

    <%!-- Mobile hamburger --%>
    <button
      id="sidebar-toggle"
      class="sm:hidden fixed top-3 left-3 z-50 btn btn-ghost btn-sm btn-circle bg-base-200/80 backdrop-blur"
      aria-label="Menu"
    >
      <.icon name="hero-bars-3" class="w-5 h-5" />
    </button>

    <%!-- Mobile backdrop --%>
    <div id="sidebar-backdrop" class="sm:hidden fixed inset-0 z-30 bg-black/50 hidden" />
    """
  end

  defp nav_item(assigns) do
    assigns = assign_new(assigns, :badge, fn -> nil end)

    ~H"""
    <.link
      navigate={@href}
      class={[
        "flex items-center gap-3 w-full px-2 py-1 mx-0 rounded-[10px] transition-colors",
        @active && "bg-primary/15",
        !@active && "hover:bg-base-content/8"
      ]}
    >
      <div class="w-10 h-10 min-w-10 flex items-center justify-center">
        <.icon
          name={@icon}
          class={["w-[18px] h-[18px]", @active && "text-primary", !@active && "text-base-content/50"]}
        />
      </div>
      <span class={[
        "text-sm whitespace-nowrap",
        @active && "font-semibold text-primary",
        !@active && "text-base-content/60"
      ]}>
        {@label}
      </span>
      <span
        :if={@badge && @badge > 0}
        class="badge badge-sm badge-primary ml-auto"
      >
        {@badge}
      </span>
    </.link>
    """
  end
end
