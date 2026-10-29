defmodule PinventoryWeb.LiveEditComponents do
  @moduledoc """
  The warning an edit page shows when someone else saved a part of the page
  that has unsaved edits here. See `Pinventory.LiveEdits`.

  The LiveView handles `"load_latest"` and `"keep_my_edits"`, each with a
  `"section"` value when the page has more than one section.
  """

  use PinventoryWeb, :html

  attr :id, :string, required: true
  attr :section, :string, default: nil, doc: "sent as the section value of both buttons"
  attr :by, :string, required: true, doc: "who saved, e.g. sam@example.com"
  attr :saved, :string, required: true, doc: "what they saved, e.g. a new name"
  attr :their_edit, :string, default: nil, doc: "heading of their edit, from Activity"
  slot :inner_block, doc: "their version next to yours"

  def stale_section(assigns) do
    ~H"""
    <div
      id={@id}
      role="alert"
      class="flex flex-col gap-3 rounded-xl border border-warning/60 bg-warning/10 px-4 py-3 lg:min-h-0"
    >
      <div class="flex items-start gap-2">
        <.icon name="hero-exclamation-triangle" class="mt-0.5 size-5 shrink-0 text-warning" />
        <div class="space-y-1 text-sm">
          <p id={"#{@id}-message"} class="font-medium">
            {@by} saved {@saved} while you were editing.
          </p>
          <p class="opacity-80">
            Your edits here are not saved. Keep them to save them on top of the new version, or
            load the new version and drop them.
          </p>
          <p :if={@their_edit} id={"#{@id}-their-edit"} class="text-xs opacity-70">
            Their save: {@their_edit}
          </p>
        </div>
      </div>
      {render_slot(@inner_block)}
      <div class="flex flex-wrap justify-end gap-2">
        <button
          type="button"
          id={"#{@id}-load"}
          class="btn btn-ghost btn-sm transition-transform active:scale-95"
          phx-click="load_latest"
          phx-value-section={@section}
        >
          Load their version
        </button>
        <button
          type="button"
          id={"#{@id}-keep"}
          class="btn btn-warning btn-sm transition-transform active:scale-95"
          phx-click="keep_my_edits"
          phx-value-section={@section}
        >
          Keep my edits
        </button>
      </div>
    </div>
    """
  end
end
