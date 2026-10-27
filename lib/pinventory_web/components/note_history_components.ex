defmodule PinventoryWeb.NoteHistoryComponents do
  @moduledoc """
  The item note's "edited N times" menu. The history window it opens is
  `PinventoryWeb.VersionHistoryComponents.history_window/1`.
  """

  use PinventoryWeb, :html

  import PinventoryWeb.VersionHistoryComponents, only: [author: 1, relative_time: 2]

  attr :versions, :list, required: true
  attr :history_path, :any, required: true, doc: "1-arity function from version number to path"

  def edited_menu(assigns) do
    assigns = assign(assigns, :now, DateTime.utc_now())

    ~H"""
    <div :if={length(@versions) > 1} class="relative">
      <button
        type="button"
        id="note-edited-menu"
        class="inline-flex items-center gap-0.5 rounded px-1 text-xs opacity-70 hover:opacity-100 hover:underline"
        aria-haspopup="menu"
        phx-click={JS.toggle(to: "#note-edited-list")}
      >
        edited {length(@versions) - 1} {if length(@versions) == 2, do: "time", else: "times"}
        <.icon name="hero-chevron-down" class="size-3" />
      </button>
      <div
        id="note-edited-list"
        role="menu"
        class="absolute right-0 z-30 mt-1 hidden w-72 max-w-[calc(100vw-2rem)] overflow-hidden rounded-xl border border-base-300 bg-base-100 shadow-xl"
        phx-click-away={JS.hide(to: "#note-edited-list")}
      >
        <p class="border-b border-base-300 px-3 py-2 text-xs font-semibold opacity-70">
          Edited {length(@versions) - 1} {if length(@versions) == 2, do: "time", else: "times"}
        </p>
        <div class="max-h-64 overflow-y-auto">
          <.link
            :for={version <- @versions |> tl() |> Enum.reverse()}
            id={"note-edited-#{version.number}"}
            role="menuitem"
            patch={@history_path.(version.number)}
            class="flex w-full items-baseline gap-2 px-3 py-1.5 text-left text-sm hover:bg-base-200"
          >
            <span class="font-medium">{author(version)}</span>
            <span class="flex-1 text-xs opacity-60">{relative_time(version.inserted_at, @now)}</span>
            <span class="text-xs tabular-nums opacity-40">v{version.number}</span>
          </.link>
        </div>
      </div>
    </div>
    """
  end
end
