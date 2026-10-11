defmodule PinventoryWeb.NoteHistoryComponents do
  @moduledoc """
  The item note's "edited N times" menu, the note history window, and the
  word diff they share.
  """

  use PinventoryWeb, :html

  alias Pinventory.Items.NoteVersion
  alias Pinventory.NoteDiff

  @doc """
  Short author name for a version: the local part of the user's email.
  """
  def author(%NoteVersion{user: %{email: email}}), do: email |> String.split("@") |> hd()
  def author(%NoteVersion{}), do: "unknown"

  @doc """
  Names the authors of a compared range.

  Lists up to three names. With four or more, lists the first two and
  "others"; `authors_title/1` gives the full list for a tooltip.
  """
  def authors_label([]), do: "nobody"
  def authors_label([a]), do: a
  def authors_label([a, b]), do: "#{a} and #{b}"
  def authors_label([a, b, c]), do: "#{a}, #{b}, and #{c}"
  def authors_label([a, b | _]), do: "#{a}, #{b}, and others"

  def authors_title(authors) when length(authors) > 3, do: Enum.join(authors, ", ")
  def authors_title(_authors), do: nil

  @doc """
  Distinct authors of the versions after `from` up to and including `to`, in
  the order they first edited. The order of `from` and `to` does not matter.
  """
  def range_authors(versions, from, to) do
    {low, high} = Enum.min_max([from, to])

    versions
    |> Enum.filter(&(&1.number > low and &1.number <= high))
    |> Enum.map(&author/1)
    |> Enum.uniq()
  end

  @doc """
  Compact relative time, such as "5m ago" or "3d ago". Older than 30 days
  shows the date.
  """
  def relative_time(%DateTime{} = at, %DateTime{} = now) do
    seconds = DateTime.diff(now, at)

    cond do
      seconds < 60 -> "just now"
      seconds < 3600 -> "#{div(seconds, 60)}m ago"
      seconds < 86_400 -> "#{div(seconds, 3600)}h ago"
      seconds < 30 * 86_400 -> "#{div(seconds, 86_400)}d ago"
      true -> Calendar.strftime(at, "%b %-d, %Y")
    end
  end

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

  attr :versions, :list, required: true
  attr :from, :integer, required: true
  attr :to, :integer, required: true
  attr :view, :atom, values: [:inline, :split], required: true
  attr :current_notes, :string, required: true
  attr :history_path, :any, required: true
  attr :close_path, :string, required: true

  def history_window(assigns) do
    from_version = Enum.at(assigns.versions, assigns.from)
    to_version = Enum.at(assigns.versions, assigns.to)
    rows = NoteDiff.rows(from_version.text, to_version.text)
    authors = range_authors(assigns.versions, assigns.from, assigns.to)
    last = length(assigns.versions) - 1

    assigns =
      assigns
      |> assign(:to_version, to_version)
      |> assign(:rows, rows)
      |> assign(:counts, NoteDiff.counts(rows))
      |> assign(:authors, authors)
      |> assign(:last, last)
      |> assign(:now, DateTime.utc_now())

    ~H"""
    <div
      id="note-history"
      class="fixed inset-0 z-[60] flex items-end justify-center bg-neutral/40 sm:items-center sm:p-4"
      phx-window-keydown={JS.patch(@close_path)}
      phx-key="Escape"
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="note-history-title"
        class="flex max-h-[88vh] w-full max-w-5xl flex-col rounded-t-2xl border border-base-300 bg-base-100 shadow-2xl sm:max-h-[85vh] sm:rounded-2xl"
        phx-click-away={JS.patch(@close_path)}
      >
        <div class="flex items-center justify-between gap-2 border-b border-base-300 px-4 py-3">
          <h2 id="note-history-title" class="text-lg font-semibold tracking-tight">Note history</h2>
          <.link
            patch={@close_path}
            id="note-history-close"
            class="btn btn-ghost btn-sm btn-square"
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </.link>
        </div>

        <div class="flex min-h-0 flex-1">
          <nav
            id="note-history-versions"
            aria-label="Versions"
            class="hidden w-60 shrink-0 overflow-y-auto border-r border-base-300 py-1 sm:block"
          >
            <.link
              :for={version <- Enum.reverse(@versions)}
              id={"note-history-version-#{version.number}"}
              patch={@history_path.(version.number)}
              aria-current={version.number == @to && "true"}
              class={[
                "flex items-baseline gap-2 px-3 py-1.5 text-sm hover:bg-base-200",
                version.number == @to && "bg-primary/10 font-medium text-primary",
                (version.number != @to and in_range?(version.number, @from, @to)) && "bg-base-200/60"
              ]}
            >
              <span class="w-8 shrink-0 text-xs tabular-nums opacity-60">v{version.number}</span>
              <span class="min-w-0 flex-1 truncate">
                {if version.number == 0, do: "Empty note", else: author(version)}
              </span>
              <span :if={version.inserted_at} class="shrink-0 text-xs opacity-50">
                {relative_time(version.inserted_at, @now)}
              </span>
            </.link>
          </nav>

          <div class="flex min-w-0 flex-1 flex-col">
            <div class="flex flex-wrap items-center gap-2 border-b border-base-300 px-4 py-2">
              <form
                id="note-compare-form"
                phx-change="compare_note_versions"
                class="flex items-center gap-1 text-sm"
              >
                <span class="opacity-70">Compare</span>
                <select name="from" id="note-compare-from" class="select select-sm w-auto">
                  <option :for={v <- @versions} value={v.number} selected={v.number == @from}>
                    v{v.number}
                  </option>
                </select>
                <.icon name="hero-arrow-right" class="size-4 opacity-60" />
                <select name="to" id="note-compare-to" class="select select-sm w-auto">
                  <option :for={v <- @versions} value={v.number} selected={v.number == @to}>
                    v{v.number}
                  </option>
                </select>
              </form>

              <div class="join ml-auto" role="group" aria-label="Diff view">
                <button
                  :for={{view, label} <- [inline: "Inline", split: "Side by side"]}
                  type="button"
                  id={"note-view-#{view}"}
                  class={["btn btn-xs join-item", @view == view && "btn-active"]}
                  aria-pressed={to_string(@view == view)}
                  phx-click="set_note_view"
                  phx-value-view={view}
                >
                  {label}
                </button>
              </div>
            </div>

            <div class="flex flex-wrap items-center justify-between gap-2 px-4 pt-3 text-sm">
              <p id="note-history-summary">
                <span :if={@authors != []}>
                  Changes by
                  <span class="font-medium" title={authors_title(@authors)}>
                    {authors_label(@authors)}
                  </span>
                </span>
                <span :if={@authors == []} class="opacity-70">Same version</span>
                <span class="opacity-60">· v{@from} → v{@to}</span>
              </p>
              <p id="note-history-counts" class="text-xs tabular-nums">
                <span class="text-success">+{@counts.added}</span>
                <span class="text-error">−{@counts.removed}</span>
              </p>
            </div>

            <div class="min-h-0 flex-1 overflow-y-auto px-4 py-3">
              <.note_diff rows={@rows} view={@view} />
            </div>

            <div class="flex flex-wrap items-center gap-2 border-t border-base-300 px-4 py-3">
              <.link
                :if={@to > 0}
                id="note-history-prev"
                patch={@history_path.(@to - 1)}
                class="btn btn-ghost btn-sm"
              >
                <.icon name="hero-chevron-left" class="size-4" /> v{@to - 1}
              </.link>
              <.link
                :if={@to < @last}
                id="note-history-next"
                patch={@history_path.(@to + 1)}
                class="btn btn-ghost btn-sm"
              >
                v{@to + 1} <.icon name="hero-chevron-right" class="size-4" />
              </.link>
              <button
                type="button"
                id="note-history-restore"
                class="btn btn-primary btn-sm ml-auto"
                phx-click="restore_note_version"
                phx-value-number={@to}
                disabled={@to_version.text == @current_notes}
              >
                Restore v{@to} into the form
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :rows, :list, required: true
  attr :view, :atom, values: [:inline, :split], default: :inline
  attr :id, :string, default: "note-diff"

  def note_diff(%{view: :inline} = assigns) do
    ~H"""
    <div
      id={@id}
      data-view="inline"
      class="rounded-lg border border-base-300 bg-base-200/40 p-2 text-sm leading-relaxed"
    >
      <%= for row <- @rows do %>
        <.skip_row :if={match?({:skip, _}, row)} count={elem(row, 1)} />
        <.diff_line :if={match?({:line, _}, row)} ops={elem(row, 1)} />
      <% end %>
    </div>
    """
  end

  def note_diff(%{view: :split} = assigns) do
    ~H"""
    <div id={@id} data-view="split" class="text-sm leading-relaxed">
      <div class="hidden grid-cols-2 gap-x-3 sm:grid">
        <p class="pb-1 text-xs font-semibold opacity-60">Before</p>
        <p class="pb-1 text-xs font-semibold opacity-60">After</p>
        <%= for row <- @rows do %>
          <div :if={match?({:skip, _}, row)} class="col-span-2">
            <.skip_row count={elem(row, 1)} />
          </div>
          <%= if match?({:line, _}, row) do %>
            <.diff_line ops={NoteDiff.old_side(elem(row, 1))} class="rounded bg-error/5 px-1" />
            <.diff_line ops={NoteDiff.new_side(elem(row, 1))} class="rounded bg-success/5 px-1" />
          <% end %>
        <% end %>
      </div>
      <div class="space-y-3 sm:hidden">
        <div
          :for={{label, side} <- [{"Before", &NoteDiff.old_side/1}, {"After", &NoteDiff.new_side/1}]}
          class="rounded-lg border border-base-300 bg-base-200/40 p-2"
        >
          <p class="pb-1 text-xs font-semibold opacity-60">{label}</p>
          <%= for row <- @rows do %>
            <.skip_row :if={match?({:skip, _}, row)} count={elem(row, 1)} />
            <.diff_line
              :if={match?({:line, _}, row) and not only_other_side?(elem(row, 1), side)}
              ops={side.(elem(row, 1))}
            />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :count, :integer, required: true

  defp skip_row(assigns) do
    ~H"""
    <div class="my-1 rounded bg-base-300/50 px-2 py-0.5 text-xs opacity-60">
      ⋯ {@count} unchanged {if @count == 1, do: "line", else: "lines"}
    </div>
    """
  end

  attr :ops, :list, required: true
  attr :class, :string, default: nil

  defp diff_line(assigns) do
    ~H"""
    <div class={["min-h-6 whitespace-pre-wrap break-words", @class]} phx-no-format><span
        :for={{op, text} <- @ops}
        class={op_class(op)}
      >{text}</span></div>
    """
  end

  defp only_other_side?(ops, side), do: ops != [] and side.(ops) == []

  defp op_class(:eq), do: nil
  defp op_class(:del), do: "rounded-sm bg-error/15 text-error line-through decoration-error/60"
  defp op_class(:ins), do: "rounded-sm bg-success/20 text-success"

  defp in_range?(number, from, to) do
    {low, high} = Enum.min_max([from, to])
    number > low and number <= high
  end
end
