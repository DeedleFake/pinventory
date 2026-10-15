defmodule PinventoryWeb.Passkey.Wire do
  @moduledoc """
  Boundary between the browser hook and `Pinventory.Accounts`: parses the
  base64url WebAuthn JSON into domain structs. Fails closed on anything
  malformed.
  """

  alias Pinventory.Accounts.Passkey.{Assertion, Attestation}

  @max_field 16_384

  @spec attestation(term()) :: {:ok, Attestation.t()} | {:error, :invalid_attestation}
  def attestation(%{"response" => %{} = r}) do
    with {:ok, client_data} <- decode(r["clientDataJSON"]),
         {:ok, att_obj} <- decode(r["attestationObject"]) do
      {:ok,
       %Attestation{
         client_data_json: client_data,
         attestation_object: att_obj,
         transports: transports(r["transports"])
       }}
    else
      _ -> {:error, :invalid_attestation}
    end
  end

  def attestation(_), do: {:error, :invalid_attestation}

  @spec assertion(term()) :: {:ok, Assertion.t()} | {:error, :invalid_assertion}
  def assertion(%{"rawId" => raw_id, "response" => %{} = r}) do
    with {:ok, cred_id} <- decode(raw_id),
         {:ok, auth_data} <- decode(r["authenticatorData"]),
         {:ok, client_data} <- decode(r["clientDataJSON"]),
         {:ok, sig} <- decode(r["signature"]),
         {:ok, handle} <- optional(r["userHandle"]) do
      {:ok,
       %Assertion{
         credential_id: cred_id,
         authenticator_data: auth_data,
         client_data_json: client_data,
         signature: sig,
         user_handle: handle
       }}
    else
      _ -> {:error, :invalid_assertion}
    end
  end

  def assertion(_), do: {:error, :invalid_assertion}

  defp decode(s) when is_binary(s) and byte_size(s) > 0 and byte_size(s) <= @max_field,
    do: Base.url_decode64(s, padding: false)

  defp decode(_), do: :error

  defp optional(nil), do: {:ok, nil}
  defp optional(""), do: {:ok, nil}
  defp optional(s), do: decode(s)

  @known_transports ~w(ble hybrid internal nfc smart-card usb)
  defp transports(list) when is_list(list), do: Enum.filter(list, &(&1 in @known_transports))
  defp transports(_), do: []
end
