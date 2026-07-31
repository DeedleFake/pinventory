defmodule PinventoryWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use PinventoryWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="flex h-14 sm:h-16 items-center gap-2 sm:gap-3 px-3 sm:px-6 lg:px-8 flex-nowrap overflow-hidden">
      <div class="min-w-0 shrink">
        <a
          href="/"
          class="flex items-center gap-2 text-base-content opacity-80 transition-opacity duration-200 hover:opacity-100"
          aria-label="Pinventory home"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 32 32"
            fill="currentColor"
            class="size-7 sm:size-8 shrink-0"
            aria-hidden="true"
          >
            <path
              fill-rule="evenodd"
              clip-rule="evenodd"
              d="M16 1C9.925 1 5 5.925 5 12c0 8.284 10.125 18.375 10.556 18.806a.625.625 0 0 0 .888 0C16.875 30.375 27 20.284 27 12 27 5.925 22.075 1 16 1ZM11 8.75a.75.75 0 0 0 0 1.5h10a.75.75 0 0 0 0-1.5H11Zm0 3.5a.75.75 0 0 0 0 1.5h10a.75.75 0 0 0 0-1.5H11Zm0 3.5a.75.75 0 0 0 0 1.5h6a.75.75 0 0 0 0-1.5h-6Z"
            />
          </svg>
          <span class="hidden md:inline text-lg font-semibold tracking-tight">Pinventory</span>
        </a>
      </div>

      <div class="ml-auto flex shrink-0 items-center gap-1.5 sm:gap-3">
        <div
          :if={@current_scope && @current_scope.user}
          class="flex items-center gap-1 sm:gap-3 text-sm"
        >
          <span class="hidden lg:inline opacity-80">
            {@current_scope.user.email}
          </span>
          <.link
            href={~p"/user/settings"}
            class={[
              "inline-flex items-center justify-center rounded-lg p-2 sm:px-1 sm:py-0",
              "opacity-80 transition-opacity hover:opacity-100",
              "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/40"
            ]}
            aria-label="Settings"
          >
            <.icon name="hero-cog-6-tooth" class="size-5 sm:hidden" />
            <span class="hidden sm:inline">Settings</span>
          </.link>
          <.link
            href={~p"/user/log-out"}
            method="delete"
            class={[
              "inline-flex items-center justify-center rounded-lg p-2 sm:px-1 sm:py-0",
              "opacity-80 transition-opacity hover:opacity-100",
              "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/40"
            ]}
            aria-label="Log out"
          >
            <.icon name="hero-arrow-right-start-on-rectangle" class="size-5 sm:hidden" />
            <span class="hidden sm:inline">Log out</span>
          </.link>
        </div>
        <.theme_toggle />
      </div>
    </header>

    <main class="px-4 py-10 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="relative flex flex-row items-center border border-base-300 bg-base-300 rounded-full scale-90 sm:scale-100 origin-right">
      <div class="absolute w-1/3 h-full rounded-full border border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        type="button"
        class="flex p-1.5 sm:p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        aria-label="System theme"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        type="button"
        class="flex p-1.5 sm:p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label="Light theme"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        type="button"
        class="flex p-1.5 sm:p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label="Dark theme"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
