defmodule PinventoryWeb.ConfirmDeleteComponents do
  @moduledoc false
  use PinventoryWeb, :html

  @doc """
  Type-the-name confirmation form used by delete modals.
  """
  def delete_form(name) when is_binary(name) do
    to_form(%{"name" => name}, as: :delete)
  end

  def delete_name_from_params(%{"delete" => %{"name" => name}}) when is_binary(name), do: name
  def delete_name_from_params(_), do: ""

  def confirm_name_matches?(typed, saved) when is_binary(typed) and is_binary(saved) do
    typed == saved or String.trim(typed) == String.trim(saved)
  end

  attr :id_prefix, :string, required: true
  attr :title, :string, required: true
  attr :entity_name, :string, required: true
  attr :confirm_label, :string, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :confirm_ready?, :boolean, required: true
  slot :impact

  def name_confirm_delete_modal(assigns) do
    ~H"""
    <div
      id={"#{@id_prefix}-modal"}
      class="fixed inset-0 z-50 flex items-end justify-center bg-neutral/40 p-4 sm:items-center"
      phx-window-keydown="close_delete"
      phx-key="Escape"
    >
      <div
        id={"#{@id_prefix}-dialog"}
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id_prefix}-title"}
        class="w-full max-w-md rounded-2xl border border-base-300 bg-base-100 p-5 shadow-2xl sm:p-6"
        phx-click-away="close_delete"
      >
        <div class="space-y-1">
          <h2 id={"#{@id_prefix}-title"} class="text-lg font-semibold tracking-tight">
            {@title}
          </h2>
          {render_slot(@impact)}
        </div>

        <.form
          for={@form}
          id={"#{@id_prefix}-form"}
          class="mt-4 space-y-4"
          phx-change="validate_delete"
          phx-submit="confirm_delete"
        >
          <.input
            type="text"
            field={@form[:name]}
            id={"#{@id_prefix}-confirm"}
            label={@confirm_label}
            placeholder={@entity_name}
            autocomplete="off"
            spellcheck="false"
            phx-mounted={JS.focus()}
          />

          <div class="flex justify-end gap-2">
            <button
              type="button"
              id={"#{@id_prefix}-cancel"}
              class="btn btn-ghost"
              phx-click="close_delete"
            >
              Cancel
            </button>
            <button
              type="submit"
              id={"#{@id_prefix}-confirm-submit"}
              class="btn btn-error"
              disabled={not @confirm_ready?}
            >
              Delete
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end
end
