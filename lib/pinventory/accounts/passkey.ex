defmodule Pinventory.Accounts.Passkey do
  @moduledoc """
  Domain types for WebAuthn ceremonies. Built by `PinventoryWeb.Passkey.Wire`
  from browser payloads; consumed by `Pinventory.Accounts`.
  """

  defmodule Ceremony do
    @moduledoc """
    An in-flight WebAuthn ceremony. Holds the Wax challenge (bytes, origin,
    rp_id, issued_at, timeout) and, for registration or sudo reauth, the user
    it is bound to.
    """
    @enforce_keys [:kind, :challenge]
    defstruct [:kind, :challenge, :user_id]

    @type kind :: :registration | :authentication
    @type t :: %__MODULE__{kind: kind(), challenge: Wax.Challenge.t(), user_id: binary() | nil}
  end

  defmodule Attestation do
    @moduledoc "Result of `navigator.credentials.create()`, decoded."
    @enforce_keys [:attestation_object, :client_data_json]
    defstruct [:attestation_object, :client_data_json, transports: []]

    @type t :: %__MODULE__{
            attestation_object: binary(),
            client_data_json: binary(),
            transports: [String.t()]
          }
  end

  defmodule Assertion do
    @moduledoc "Result of `navigator.credentials.get()`, decoded."
    @enforce_keys [:credential_id, :authenticator_data, :client_data_json, :signature]
    defstruct [:credential_id, :authenticator_data, :client_data_json, :signature, :user_handle]

    @type t :: %__MODULE__{
            credential_id: binary(),
            authenticator_data: binary(),
            client_data_json: binary(),
            signature: binary(),
            user_handle: binary() | nil
          }
  end
end
