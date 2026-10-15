defmodule Pinventory.SoftAuthenticator do
  @moduledoc """
  A software WebAuthn authenticator for tests. Produces the same base64url
  JSON the browser hook sends, signed with a real P-256 key, so tests run the
  full Wire -> Accounts -> Wax path without mocks.
  """

  defstruct [:credential_id, :private_key, :public_key, :user_handle]

  def new do
    {pub, priv} = :crypto.generate_key(:ecdh, :secp256r1)
    %__MODULE__{credential_id: :crypto.strong_rand_bytes(16), private_key: priv, public_key: pub}
  end

  @doc "Answers `navigator.credentials.create(options)`."
  def create(%__MODULE__{} = a, options, opts \\ []) do
    origin = Keyword.get(opts, :origin, PinventoryWeb.Endpoint.url())
    rp_id = Keyword.get(opts, :rp_id, options_value(options, :rp)[key(options, :id)])
    sign_count = Keyword.get(opts, :sign_count, 0)

    client_data = client_data("webauthn.create", options_value(options, :challenge), origin)
    <<4, x::binary-32, y::binary-32>> = a.public_key

    cose =
      CBOR.encode(%{1 => 2, 3 => -7, -1 => 1, -2 => bytes(x), -3 => bytes(y)})

    attested =
      <<0::128, byte_size(a.credential_id)::16>> <> a.credential_id <> cose

    auth_data = auth_data(rp_id, 0x45, sign_count) <> attested

    att_obj =
      CBOR.encode(%{"fmt" => "none", "attStmt" => %{}, "authData" => bytes(auth_data)})

    %{
      "id" => b64(a.credential_id),
      "rawId" => b64(a.credential_id),
      "type" => "public-key",
      "response" => %{
        "clientDataJSON" => b64(client_data),
        "attestationObject" => b64(att_obj),
        "transports" => ["internal"]
      }
    }
  end

  @doc "Answers `navigator.credentials.get(options)`."
  def get(%__MODULE__{} = a, options, opts \\ []) do
    origin = Keyword.get(opts, :origin, PinventoryWeb.Endpoint.url())
    rp_id = Keyword.get(opts, :rp_id, options_value(options, :rpId))
    sign_count = Keyword.get(opts, :sign_count, 1)
    challenge = Keyword.get(opts, :challenge, options_value(options, :challenge))

    client_data = client_data("webauthn.get", challenge, origin)
    # 0x05 = user present + user verified; pass flags: 0x01 for presence only.
    auth_data = auth_data(rp_id, Keyword.get(opts, :flags, 0x05), sign_count)

    sig =
      :crypto.sign(:ecdsa, :sha256, auth_data <> :crypto.hash(:sha256, client_data), [
        a.private_key,
        :secp256r1
      ])

    response = %{
      "clientDataJSON" => b64(client_data),
      "authenticatorData" => b64(auth_data),
      "signature" => b64(sig)
    }

    # Defaults to the handle stored at registration; `user_handle: nil` omits it.
    response =
      case Keyword.get(opts, :user_handle, a.user_handle) do
        nil -> response
        handle -> Map.put(response, "userHandle", b64(handle))
      end

    %{
      "id" => b64(a.credential_id),
      "rawId" => b64(a.credential_id),
      "type" => "public-key",
      "response" => response
    }
  end

  defp auth_data(rp_id, flags, sign_count),
    do: :crypto.hash(:sha256, rp_id) <> <<flags, sign_count::32>>

  defp client_data(type, challenge, origin),
    do: Jason.encode!(%{type: type, challenge: challenge, origin: origin})

  # Options may arrive with atom keys (from Accounts) or string keys (via push_event JSON).
  defp options_value(options, k), do: Map.get(options, k) || Map.get(options, Atom.to_string(k))
  defp key(options, k), do: if(Map.has_key?(options, :rp), do: k, else: Atom.to_string(k))

  defp bytes(bin), do: %CBOR.Tag{tag: :bytes, value: bin}
  defp b64(bin), do: Base.url_encode64(bin, padding: false)
end
