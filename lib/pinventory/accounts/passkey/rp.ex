defmodule Pinventory.Accounts.Passkey.RP do
  @moduledoc """
  Relying-party identity for WebAuthn.

  Defaults to the host and origin of `PinventoryWeb.Endpoint` (`PHX_HOST` in
  prod). `config :pinventory, :passkey, rp_id: ..., origin: ...` overrides
  them (runtime.exs reads `PASSKEY_RP_ID` / `PASSKEY_ORIGIN`). Never derived
  from request headers.
  """

  @rp_name "Pinventory"

  def name, do: @rp_name

  @spec id() :: String.t()
  def id, do: config(:rp_id) || URI.parse(origin()).host

  @spec origin() :: String.t()
  def origin, do: config(:origin) || PinventoryWeb.Endpoint.url()

  defp config(key) do
    case Application.get_env(:pinventory, :passkey, [])[key] do
      blank when blank in [nil, ""] -> nil
      value -> value
    end
  end
end
