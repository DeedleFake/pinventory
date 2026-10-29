defmodule PinventoryWeb.NamingConventionLive do
  use PinventoryWeb, :live_view

  alias Pinventory.LiveEdits
  alias Pinventory.Markdown
  alias Pinventory.NamingConvention

  import PinventoryWeb.LiveEditComponents
  import PinventoryWeb.MarkdownComponents
  import PinventoryWeb.VersionHistoryComponents

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} nav={:items} wide fill>
      <div
        id="convention-page"
        class="flex flex-col gap-4 lg:min-h-0 lg:flex-1"
        phx-hook="UnsavedChanges"
        data-dirty={to_string(@dirty?)}
      >
        <%!-- Save sits up here because a phone keyboard covers the bottom of the page. --%>
        <div class="flex items-center justify-between gap-3">
          <div class="min-w-0">
            <.link navigate={~p"/"} class="text-xs opacity-60 hover:underline">Items</.link>
            <h1 class="text-xl font-semibold tracking-tight">Naming convention</h1>
          </div>
          <div id="convention-actions" class="flex flex-wrap items-center justify-end gap-2">
            <p :if={@dirty?} id="convention-hint" class="text-xs text-primary">
              Unsaved changes<span :if={@restored_from}> · restored from v{@restored_from}</span>
            </p>
            <.link
              :if={length(@versions) > 1}
              id="convention-history-open"
              patch={history_path(@base.number)}
              class="btn btn-ghost border border-base-300 transition-transform active:scale-95"
            >
              <.icon name="hero-clock" class="size-4" /> History
            </.link>
            <.button
              type="submit"
              form="convention-form"
              id="convention-save"
              variant="primary"
              class="btn btn-primary transition-transform active:scale-95"
              disabled={not @dirty? or @stale != nil}
              phx-disable-with="Saving..."
            >
              Save
            </.button>
          </div>
        </div>

        <.stale_section
          :if={@stale}
          id="convention-stale"
          by={author(@stale)}
          saved={"version #{@stale.number}"}
        >
          <%!-- On large screens the diff gives up its height first, so the editor stays in the window. --%>
          <div :if={@stale.text != @text} class="flex min-h-0 flex-col gap-1">
            <p class="text-xs font-semibold opacity-70">Their version → yours</p>
            <div class="max-h-48 min-h-16 overflow-y-auto">
              <.text_diff
                id="convention-stale-diff"
                rows={Pinventory.TextDiff.rows(@stale.text, @text)}
              />
            </div>
          </div>
        </.stale_section>

        <p id="convention-last-edit" class="text-xs opacity-60">
          <%= if @base.number == 0 do %>
            Initial version
          <% else %>
            Last edited by {author(@base)} · {relative_time(@base.inserted_at, DateTime.utc_now())} · v{@base.number}
          <% end %>
        </p>

        <.form
          for={@form}
          id="convention-form"
          phx-change="validate"
          phx-submit="save"
          class={[
            "flex flex-col overflow-hidden rounded-xl border transition-colors duration-200",
            "lg:min-h-48 lg:flex-1",
            @dirty? && "border-primary ring-1 ring-primary/30",
            not @dirty? && "border-base-300"
          ]}
        >
          <div
            id="convention-toolbar"
            class="flex flex-wrap items-center gap-0.5 border-b border-base-300 px-2 py-1"
            role="toolbar"
            aria-label="Formatting"
            aria-controls="convention-text"
            phx-hook=".MarkdownToolbar"
            data-textarea="convention-text"
          >
            <button
              :for={{action, icon, label} <- toolbar_actions()}
              type="button"
              id={"convention-tool-#{action}"}
              class="btn btn-ghost btn-sm btn-square transition-transform active:scale-90 active:bg-base-300"
              data-md={action}
              title={label}
              aria-label={label}
            >
              <.toolbar_icon action={action} icon={icon} />
            </button>
            <span class="ml-auto flex items-center gap-2">
              <span
                :if={@format_status}
                id="convention-format-status"
                class="text-xs opacity-70"
                role="status"
              >
                {@format_status}
              </span>
              <button
                type="button"
                id="convention-format"
                class="btn btn-ghost btn-sm transition-transform active:scale-95 active:bg-base-300"
                phx-click="format"
                title="Rewrite the Markdown in one tidy style"
              >
                <.icon name="hero-sparkles" class="size-4" /> Format
              </button>
            </span>
          </div>

          <div
            id="convention-panes"
            class="grid divide-base-300 lg:min-h-0 lg:flex-1 lg:grid-cols-2 lg:grid-rows-1 lg:divide-x"
            phx-hook=".ScrollSync"
            data-source="convention-text"
            data-preview="convention-preview"
          >
            <label class="flex min-h-0 flex-col bg-base-200">
              <span class="px-3 pt-2 text-xs font-semibold tracking-wide uppercase opacity-60">
                Markdown
              </span>
              <textarea
                id="convention-text"
                name={@form[:text].name}
                phx-debounce="250"
                aria-label="Naming convention Markdown"
                placeholder="e.g. Include the unit in the name: Boxes of Tissues, not Tissues"
                class="min-h-[60dvh] w-full flex-1 resize-none bg-transparent px-3 py-2 font-mono text-sm leading-relaxed focus:outline-none lg:min-h-0"
              >{Phoenix.HTML.Form.normalize_value("textarea", @form[:text].value)}</textarea>
            </label>
            <section
              id="convention-preview"
              aria-label="Preview"
              class="markdown-paper min-h-0 border-t border-base-300 lg:overflow-y-auto lg:border-t-0"
            >
              <p class="px-5 pt-2 text-xs font-semibold tracking-wide uppercase opacity-60">
                Preview
              </p>
              <.markdown id="convention-preview-body" text={@text} class="px-5 py-3" sourcepos />
            </section>
          </div>
        </.form>
        <.history_window
          :if={@history}
          id="convention"
          title="Naming convention history"
          initial_label="Initial version"
          versions={@versions}
          from={@history.from}
          to={@history.to}
          view={@history.view}
          current_text={@text}
          history_path={&history_path/1}
          close_path={~p"/items/naming-convention"}
        />
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".MarkdownToolbar">
        // Each action wraps the selection or prefixes the selected lines, and
        // undoes itself when the selection already has that formatting.
        const WRAPS = { bold: "**", italic: "*", strike: "~~", code: "`" }
        const PREFIXES = { heading: "## ", bullet: "- ", number: "1. ", quote: "> " }
        const MARKERS = { heading: /^#+ /, bullet: /^[-*+] /, number: /^\d+\. /, quote: /^> / }
        const ANY_MARKER = /^(#+ |[-*+] |\d+\. |> )/

        export default {
          mounted() {
            // Keep focus (and a phone's keyboard) in the textarea.
            this.el.addEventListener("mousedown", (e) => {
              if (e.target.closest("[data-md]")) e.preventDefault()
            })
            this.el.addEventListener("click", (e) => {
              const button = e.target.closest("[data-md]")
              if (button) this.apply(button.dataset.md)
            })
          },
          textarea() {
            return document.getElementById(this.el.dataset.textarea)
          },
          apply(action) {
            const ta = this.textarea()
            if (WRAPS[action]) this.wrap(ta, WRAPS[action], WRAPS[action])
            else if (action === "link") this.link(ta)
            else if (PREFIXES[action]) this.prefix(ta, action)
          },
          replace(ta, start, end, text, selStart, selEnd) {
            ta.focus()
            ta.setSelectionRange(start, end)
            // insertText keeps the browser's undo history; setRangeText is the fallback.
            if (!document.execCommand("insertText", false, text)) {
              ta.setRangeText(text, start, end)
              ta.dispatchEvent(new Event("input", { bubbles: true }))
            }
            ta.setSelectionRange(selStart, selEnd)
          },
          wrap(ta, before, after) {
            const { selectionStart: s, selectionEnd: e, value } = ta
            const selected = value.slice(s, e)
            const outer = value.slice(s - before.length, e + after.length)
            if (s >= before.length && outer === before + selected + after) {
              this.replace(ta, s - before.length, e + after.length, selected,
                s - before.length, e - before.length)
            } else {
              this.replace(ta, s, e, before + selected + after, s + before.length, e + before.length)
            }
          },
          link(ta) {
            const { selectionStart: s, selectionEnd: e, value } = ta
            const label = value.slice(s, e) || "text"
            const text = `[${label}](url)`
            const urlStart = s + label.length + 3
            this.replace(ta, s, e, text, urlStart, urlStart + 3)
          },
          prefix(ta, action) {
            const { selectionStart: s, selectionEnd: e, value } = ta
            const start = value.lastIndexOf("\n", s - 1) + 1
            const nextBreak = value.indexOf("\n", e)
            const end = nextBreak === -1 ? value.length : nextBreak
            const lines = value.slice(start, end).split("\n")
            const marker = MARKERS[action]
            const remove = lines.every((line) => marker.test(line))
            const changed = lines.map((line, i) => {
              if (remove) return line.replace(marker, "")
              const bare = line.replace(ANY_MARKER, "")
              return (action === "number" ? `${i + 1}. ` : PREFIXES[action]) + bare
            }).join("\n")
            this.replace(ta, start, end, changed, start, start + changed.length)
          }
        }
      </script>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".ScrollSync">
        // Keeps the textarea and the preview showing the same part of the
        // document. Each rendered block carries data-sourcepos, so a source
        // line's top in the textarea pairs with its block's top in the preview.
        // Scroll positions between two pairs are interpolated.
        export default {
          mounted() {
            this.source = document.getElementById(this.el.dataset.source)
            this.preview = document.getElementById(this.el.dataset.preview)
            this.anchors = null
            // The scrollTop each pane was last set to, so the scroll event
            // that setting fires is not synced back.
            this.expected = new Map()
            this.onScroll = (e) => this.follow(e.target)
            this.stale = () => { this.anchors = null }
            this.source.addEventListener("scroll", this.onScroll)
            this.preview.addEventListener("scroll", this.onScroll)
            this.source.addEventListener("input", this.stale)
            this.resize = new ResizeObserver(this.stale)
            this.resize.observe(this.source)
            this.resize.observe(this.preview)
            // A re-render follows typing, so the preview catches up to the textarea.
            this.rerender = new MutationObserver(() => {
              this.anchors = null
              this.sync(this.source, this.preview)
            })
            this.rerender.observe(this.preview, { childList: true, subtree: true, characterData: true })
          },
          destroyed() {
            this.resize.disconnect()
            this.rerender.disconnect()
          },
          follow(from) {
            const expected = this.expected.get(from)
            this.expected.delete(from)
            if (expected !== undefined && Math.abs(from.scrollTop - expected) <= 1) return
            this.sync(from, from === this.source ? this.preview : this.source)
          },
          sync(from, to) {
            // A stacked phone layout scrolls the page, not the preview.
            if (this.preview.scrollHeight <= this.preview.clientHeight) return
            this.anchors ??= this.measure()
            const [fromYs, toYs] = from === this.source
              ? [this.anchors.source, this.anchors.preview]
              : [this.anchors.preview, this.anchors.source]
            const top = Math.round(interpolate(from.scrollTop, fromYs, toYs))
            if (Math.abs(to.scrollTop - top) < 1) return
            this.expected.set(to, top)
            to.scrollTop = top
          },
          measure() {
            const lineTops = this.lineTops()
            const previewTop = this.preview.getBoundingClientRect().top - this.preview.scrollTop
            const sourceMax = this.source.scrollHeight - this.source.clientHeight
            const previewMax = this.preview.scrollHeight - this.preview.clientHeight
            const anchors = { source: [0], preview: [0] }
            const blocks = [...this.preview.querySelectorAll("[data-sourcepos]")]
              .map((el) => ({ line: parseInt(el.dataset.sourcepos, 10), el }))
              .sort((a, b) => a.line - b.line)
            for (const { line, el } of blocks) {
              const s = lineTops[line - 1]
              const p = el.getBoundingClientRect().top - previewTop
              // Nested blocks share a start line, and both lists must rise.
              if (s > anchors.source.at(-1) && p > anchors.preview.at(-1) && s < sourceMax && p < previewMax) {
                anchors.source.push(s)
                anchors.preview.push(p)
              }
            }
            // Both panes reach their ends together.
            anchors.source.push(Math.max(sourceMax, anchors.source.at(-1) + 1))
            anchors.preview.push(Math.max(previewMax, anchors.preview.at(-1) + 1))
            return anchors
          },
          // Each source line's top in the textarea's content, wrapped lines
          // included, measured on a hidden copy with the same text layout.
          lineTops() {
            const ta = this.source
            const style = getComputedStyle(ta)
            const mirror = document.createElement("div")
            for (const prop of ["font", "letterSpacing", "wordSpacing", "tabSize", "textTransform",
              "whiteSpace", "overflowWrap", "wordBreak", "lineHeight"]) {
              mirror.style[prop] = style[prop]
            }
            const padLeft = parseFloat(style.paddingLeft)
            const padTop = parseFloat(style.paddingTop)
            Object.assign(mirror.style, {
              position: "absolute", visibility: "hidden", top: "0", left: "-9999px",
              boxSizing: "content-box", padding: "0", border: "0",
              width: `${ta.clientWidth - padLeft - parseFloat(style.paddingRight)}px`,
            })
            for (const line of ta.value.split("\n")) {
              const div = document.createElement("div")
              div.textContent = line || "\u200b"
              mirror.append(div)
            }
            document.body.append(mirror)
            const tops = [...mirror.children].map((div) => padTop + div.offsetTop)
            mirror.remove()
            return tops
          }
        }

        function interpolate(y, from, to) {
          let i = 1
          while (i < from.length - 1 && from[i] < y) i++
          const t = Math.min(Math.max((y - from[i - 1]) / (from[i] - from[i - 1]), 0), 1)
          return to[i - 1] + t * (to[i] - to[i - 1])
        }
      </script>
    </Layouts.app>
    """
  end

  attr :action, :string, required: true
  attr :icon, :string, default: nil

  defp toolbar_icon(%{icon: nil} = assigns) do
    ~H"""
    <span class={["text-sm leading-none", toolbar_text_class(@action)]} aria-hidden="true">
      {toolbar_text(@action)}
    </span>
    """
  end

  defp toolbar_icon(assigns) do
    ~H"""
    <.icon name={@icon} class="size-4" />
    """
  end

  defp toolbar_actions do
    [
      {"bold", nil, "Bold"},
      {"italic", nil, "Italic"},
      {"strike", nil, "Strikethrough"},
      {"heading", nil, "Heading"},
      {"bullet", "hero-list-bullet", "Bulleted list"},
      {"number", "hero-numbered-list", "Numbered list"},
      {"quote", "hero-chat-bubble-bottom-center-text", "Quote"},
      {"code", "hero-code-bracket", "Code"},
      {"link", "hero-link", "Link"}
    ]
  end

  defp toolbar_text("bold"), do: "B"
  defp toolbar_text("italic"), do: "I"
  defp toolbar_text("strike"), do: "S"
  defp toolbar_text("heading"), do: "H"

  defp toolbar_text_class("bold"), do: "font-bold"
  defp toolbar_text_class("italic"), do: "font-serif italic"
  defp toolbar_text_class("strike"), do: "line-through"
  defp toolbar_text_class("heading"), do: "font-semibold"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Naming convention")
     |> assign(:dirty?, false)
     |> assign(:history, nil)
     |> assign(:format_status, nil)
     |> show_version(NamingConvention.current())
     |> tap(fn socket -> if connected?(socket), do: LiveEdits.subscribe(:naming_convention) end)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_version_param(socket, params["version"])}
  end

  @impl true
  def handle_event("validate", %{"convention" => %{"text" => text}}, socket) do
    {:noreply, socket |> assign(:format_status, nil) |> put_text(text)}
  end

  def handle_event("format", _params, socket) do
    formatted = Markdown.format(socket.assigns.text)
    status = if formatted == socket.assigns.text, do: "Already tidy", else: "Formatted"

    {:noreply,
     socket
     |> put_text(formatted, socket.assigns.restored_from)
     |> assign(:format_status, status)}
  end

  def handle_event("save", params, socket) do
    text = get_in(params, ["convention", "text"]) || socket.assigns.text
    scope = socket.assigns.current_scope

    case NamingConvention.save(scope, socket.assigns.base.number, text) do
      {:ok, version} ->
        {:noreply,
         socket
         |> put_flash(:info, "Naming convention saved")
         |> show_version(version)}

      {:error, :stale, newest} ->
        {:noreply, socket |> put_text(text) |> reconcile(newest)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, error_message(changeset))}
    end
  end

  # The newer saved version becomes the base and the form keeps the user's
  # text, so Save writes it on top of that version.
  def handle_event("keep_my_edits", _params, socket) do
    {:noreply,
     socket
     |> assign(:base, socket.assigns.stale)
     |> assign(:stale, nil)
     |> put_text(socket.assigns.text)}
  end

  def handle_event("load_latest", _params, socket) do
    {:noreply, show_version(socket, socket.assigns.stale)}
  end

  def handle_event("compare_versions", %{"from" => from, "to" => to}, socket) do
    {:noreply,
     update(socket, :history, fn history ->
       %{history | from: version_number(socket, from), to: version_number(socket, to)}
     end)}
  end

  def handle_event("set_diff_view", %{"view" => view}, socket) when view in ~w(inline split) do
    {:noreply, update(socket, :history, &%{&1 | view: String.to_existing_atom(view)})}
  end

  # Restore only fills the form. Save writes it as a new version.
  def handle_event("restore_version", %{"number" => number}, socket) do
    number = version_number(socket, number)
    text = Enum.at(socket.assigns.versions, number).text

    {:noreply,
     socket
     |> put_text(text, number)
     |> push_patch(to: ~p"/items/naming-convention")}
  end

  @impl true
  def handle_info({LiveEdits, :naming_convention, :saved}, socket) do
    {:noreply, reconcile(socket, NamingConvention.current())}
  end

  # Brings the page up to the newest saved version. Unedited text reloads in
  # place; edited text stays and the warning shows.
  defp reconcile(socket, newest) do
    cond do
      newest.number == socket.assigns.base.number ->
        socket

      socket.assigns.dirty? ->
        socket
        |> assign(:stale, newest)
        |> assign(:versions, NamingConvention.versions())

      true ->
        show_version(socket, newest)
    end
  end

  defp show_version(socket, version) do
    socket
    |> assign(:base, version)
    |> assign(:versions, NamingConvention.versions())
    |> assign(:stale, nil)
    |> put_text(version.text)
  end

  defp put_text(socket, text, restored_from \\ nil) do
    text = String.replace(text, "\r\n", "\n")
    dirty? = text != socket.assigns.base.text

    socket
    |> assign(:text, text)
    |> assign(:form, to_form(%{"text" => text}, as: :convention))
    |> assign(:restored_from, dirty? && restored_from)
    |> assign_dirty(dirty?)
  end

  defp assign_dirty(socket, dirty?) do
    if socket.assigns.dirty? == dirty? do
      socket
    else
      socket
      |> assign(:dirty?, dirty?)
      |> push_event("unsaved-changes", %{dirty: dirty?})
    end
  end

  defp apply_version_param(socket, number) when is_binary(number) do
    versions = socket.assigns.versions

    case Integer.parse(number) do
      {n, ""} when n >= 0 and n < length(versions) ->
        view = if socket.assigns.history, do: socket.assigns.history.view, else: :inline

        socket
        |> clear_flash()
        |> assign(:history, %{from: max(n - 1, 0), to: n, view: view})

      _ ->
        assign(socket, :history, nil)
    end
  end

  defp apply_version_param(socket, _number), do: assign(socket, :history, nil)

  defp version_number(socket, raw) do
    raw
    |> String.to_integer()
    |> max(0)
    |> min(length(socket.assigns.versions) - 1)
  end

  defp history_path(number), do: ~p"/items/naming-convention?version=#{number}"

  defp error_message(changeset) do
    case Keyword.get(changeset.errors, :text) do
      {message, opts} ->
        "Could not save the naming convention: it " <>
          Enum.reduce(opts, message, fn {key, value}, acc ->
            String.replace(acc, "%{#{key}}", to_string(value))
          end) <> "."

      nil ->
        "Could not save the naming convention"
    end
  end
end
