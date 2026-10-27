defmodule PinventoryWeb.VersionHistoryComponents do
  @moduledoc """
  The version history window and word diff shared by texts that keep every
  saved version, such as item notes and the item naming convention.

  A version is any map with `number`, `text`, `user`, and `inserted_at`, and
  optionally `via_token_name`. Version 0 is the starting text and has no
  author. The LiveView that renders `history_window/1` handles the
  `"compare_versions"`, `"set_diff_view"`, and `"restore_version"` events.
  """

  use PinventoryWeb, :html

  alias Pinventory.TextDiff
  alias PinventoryWeb.AuditHelpers

  @doc """
  Author of a version, shown the same way as users in Activity, with "via
  <token name>" when an agent saved it with an API token.
  """
  def author(%{user: user, via_token_name: name}) when is_binary(name),
    do: "#{AuditHelpers.actor_label(user)} via #{name}"

  def author(%{user: user}), do: AuditHelpers.actor_label(user)

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
  attr :from, :integer, required: true
  attr :to, :integer, required: true
  attr :view, :atom, values: [:inline, :split], required: true
  attr :current_text, :string, required: true, doc: "the form's text, to disable a no-op restore"
  attr :history_path, :any, required: true, doc: "1-arity function from version number to path"
  attr :close_path, :string, required: true
  attr :id, :string, required: true, doc: "prefix for element ids"
  attr :title, :string, required: true
  attr :initial_label, :string, required: true, doc: "label for version 0"

  def history_window(assigns) do
    from_version = Enum.at(assigns.versions, assigns.from)
    to_version = Enum.at(assigns.versions, assigns.to)
    rows = TextDiff.rows(from_version.text, to_version.text)
    authors = range_authors(assigns.versions, assigns.from, assigns.to)
    last = length(assigns.versions) - 1

    assigns =
      assigns
      |> assign(:to_version, to_version)
      |> assign(:rows, rows)
      |> assign(:counts, TextDiff.counts(rows))
      |> assign(:authors, authors)
      |> assign(:last, last)
      |> assign(:now, DateTime.utc_now())

    ~H"""
    <div
      id={"#{@id}-history"}
      class="fixed inset-0 z-[60] flex items-end justify-center bg-neutral/40 sm:items-center sm:p-4"
      phx-window-keydown={JS.patch(@close_path)}
      phx-key="Escape"
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id}-history-title"}
        class="flex max-h-[88vh] w-full max-w-5xl flex-col rounded-t-2xl border border-base-300 bg-base-100 shadow-2xl sm:max-h-[85vh] sm:rounded-2xl"
        phx-click-away={JS.patch(@close_path)}
      >
        <div class="flex items-center justify-between gap-2 border-b border-base-300 px-4 py-3">
          <h2 id={"#{@id}-history-title"} class="text-lg font-semibold tracking-tight">{@title}</h2>
          <.link
            patch={@close_path}
            id={"#{@id}-history-close"}
            class="btn btn-ghost btn-sm btn-square"
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </.link>
        </div>

        <div class="flex min-h-0 flex-1">
          <nav
            id={"#{@id}-history-versions"}
            aria-label="Versions"
            class="hidden w-60 shrink-0 overflow-y-auto border-r border-base-300 py-1 sm:block"
          >
            <.link
              :for={version <- Enum.reverse(@versions)}
              id={"#{@id}-history-version-#{version.number}"}
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
                {if version.number == 0, do: @initial_label, else: author(version)}
              </span>
              <span :if={version.inserted_at} class="shrink-0 text-xs opacity-50">
                {relative_time(version.inserted_at, @now)}
              </span>
            </.link>
          </nav>

          <div class="flex min-w-0 flex-1 flex-col">
            <div class="flex flex-wrap items-center gap-2 border-b border-base-300 px-4 py-2">
              <form
                id={"#{@id}-compare-form"}
                phx-change="compare_versions"
                class="flex items-center gap-1 text-sm"
              >
                <span class="opacity-70">Compare</span>
                <select name="from" id={"#{@id}-compare-from"} class="select select-sm w-auto">
                  <option :for={v <- @versions} value={v.number} selected={v.number == @from}>
                    v{v.number}
                  </option>
                </select>
                <.icon name="hero-arrow-right" class="size-4 opacity-60" />
                <select name="to" id={"#{@id}-compare-to"} class="select select-sm w-auto">
                  <option :for={v <- @versions} value={v.number} selected={v.number == @to}>
                    v{v.number}
                  </option>
                </select>
              </form>

              <div class="join ml-auto" role="group" aria-label="Diff view">
                <button
                  :for={{view, label} <- [inline: "Inline", split: "Side by side"]}
                  type="button"
                  id={"#{@id}-view-#{view}"}
                  class={["btn btn-xs join-item", @view == view && "btn-active"]}
                  aria-pressed={to_string(@view == view)}
                  phx-click="set_diff_view"
                  phx-value-view={view}
                >
                  {label}
                </button>
              </div>
            </div>

            <div class="flex flex-wrap items-center justify-between gap-2 px-4 pt-3 text-sm">
              <p id={"#{@id}-history-summary"}>
                <span :if={@authors != []}>
                  Changes by
                  <span class="font-medium" title={authors_title(@authors)}>
                    {authors_label(@authors)}
                  </span>
                </span>
                <span :if={@authors == []} class="opacity-70">Same version</span>
                <span class="opacity-60">· v{@from} → v{@to}</span>
              </p>
              <p id={"#{@id}-history-counts"} class="text-xs tabular-nums">
                <span class="text-success">+{@counts.added}</span>
                <span class="text-error">−{@counts.removed}</span>
              </p>
            </div>

            <div class="min-h-0 flex-1 overflow-y-auto px-4 py-3">
              <.text_diff id={"#{@id}-diff"} rows={@rows} view={@view} />
            </div>

            <div class="flex flex-wrap items-center gap-2 border-t border-base-300 px-4 py-3">
              <.link
                :if={@to > 0}
                id={"#{@id}-history-prev"}
                patch={@history_path.(@to - 1)}
                class="btn btn-ghost btn-sm"
              >
                <.icon name="hero-chevron-left" class="size-4" /> v{@to - 1}
              </.link>
              <.link
                :if={@to < @last}
                id={"#{@id}-history-next"}
                patch={@history_path.(@to + 1)}
                class="btn btn-ghost btn-sm"
              >
                v{@to + 1} <.icon name="hero-chevron-right" class="size-4" />
              </.link>
              <button
                type="button"
                id={"#{@id}-history-restore"}
                class="btn btn-primary btn-sm ml-auto"
                phx-click="restore_version"
                phx-value-number={@to}
                disabled={@to_version.text == @current_text}
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
  attr :id, :string, required: true

  def text_diff(%{view: :inline} = assigns) do
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

  def text_diff(%{view: :split} = assigns) do
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
            <.diff_line ops={TextDiff.old_side(elem(row, 1))} class="rounded bg-error/5 px-1" />
            <.diff_line ops={TextDiff.new_side(elem(row, 1))} class="rounded bg-success/5 px-1" />
          <% end %>
        <% end %>
      </div>
      <div class="space-y-3 sm:hidden">
        <div
          :for={{label, side} <- [{"Before", &TextDiff.old_side/1}, {"After", &TextDiff.new_side/1}]}
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
    <div class={["min-h-6 whitespace-pre-wrap wrap-break-word", @class]} phx-no-format><span
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
