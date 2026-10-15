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

  @doc """
  Raises at boot when the RP id and origin cannot work together, instead of
  every passkey prompt failing later with a browser security error.
  """
  def validate! do
    case check(id(), origin()) do
      :ok -> :ok
      {:error, message} -> raise ArgumentError, message
    end
  end

  @doc """
  WebAuthn RP id rule: the origin must be https (or http on localhost), and
  its host must equal the RP id or be a subdomain of it.
  """
  @spec check(String.t(), String.t()) :: :ok | {:error, String.t()}
  def check(rp_id, origin) do
    uri = URI.parse(origin)
    host = uri.host || ""

    cond do
      uri.scheme not in ["https", "http"] or host == "" or uri.path not in [nil, "", "/"] ->
        {:error, mismatch(rp_id, origin, "the origin must be a bare scheme://host[:port] URL")}

      uri.scheme == "http" and host != "localhost" ->
        {:error,
         mismatch(rp_id, origin, "browsers only allow passkeys over https (or http://localhost)")}

      host != rp_id and not String.ends_with?(host, "." <> rp_id) ->
        {:error,
         mismatch(rp_id, origin, "the origin host must equal the RP id or be a subdomain of it")}

      true ->
        :ok
    end
  end

  defp mismatch(rp_id, origin, why) do
    """
    passkey RP id #{inspect(rp_id)} does not work with origin #{inspect(origin)}: #{why}.

    Set PASSKEY_RP_ID to the hostname users visit and PASSKEY_ORIGIN to the exact
    URL in their address bar. Behind `tailscale serve` (which proxies and adds
    HTTPS) that is, for example:

        PASSKEY_RP_ID=myhost.tailnet.ts.net
        PASSKEY_ORIGIN=https://myhost.tailnet.ts.net

    with no port, since the browser talks to tailscale on 443. Without these, both
    default to PinventoryWeb.Endpoint's URL (PHX_HOST in prod).
    """
  end

  defp config(key) do
    case Application.get_env(:pinventory, :passkey, [])[key] do
      blank when blank in [nil, ""] -> nil
      value -> value
    end
  end
end
