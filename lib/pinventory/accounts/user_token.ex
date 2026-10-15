defmodule Pinventory.Accounts.UserToken do
  use Ecto.Schema
  import Ecto.Query
  alias Pinventory.Accounts.UserToken

  @hash_algorithm :sha256
  @rand_size 32

  # Email-change tokens are delivered by email; keep validity limited.
  @change_email_validity_in_days 7
  @session_validity_in_days 14
  # Passkey login tokens hand a verified assertion from the LiveView to the
  # session controller. The browser posts them immediately.
  @passkey_login_validity_in_seconds 60

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    field :authenticated_at, :utc_datetime
    belongs_to :user, Pinventory.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Generates a token that will be stored in a signed place,
  such as session or cookie. As they are signed, those
  tokens do not need to be hashed.

  The reason why we store session tokens in the database, even
  though Phoenix already provides a session cookie, is because
  Phoenix's default session cookies are not persisted, they are
  simply signed and potentially encrypted. This means they are
  valid indefinitely, unless you change the signing/encryption
  salt.

  Therefore, storing them allows individual user
  sessions to be expired. The token system can also be extended
  to store additional data, such as the device used for logging in.
  You could then use this information to display all valid sessions
  and devices in the UI and allow users to explicitly expire any
  session they deem invalid.
  """
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    dt = user.authenticated_at || DateTime.utc_now(:second)
    {token, %UserToken{token: token, context: "session", user_id: user.id, authenticated_at: dt}}
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the user found by the token, if any, along with the token's creation time.

  The token is valid if it matches the value in the database and it has
  not expired (after @session_validity_in_days).
  """
  def verify_session_token_query(token) do
    query =
      from token in by_token_and_context_query(token, "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        select: {%{user | authenticated_at: token.authenticated_at}, token.inserted_at}

    {:ok, query}
  end

  @doc """
  Builds a token and its hash to be delivered to the user's email.

  Used for email-change confirmation. The plain token is emailed; only the
  hash is stored. Tokens bound to the previous email become invalid after
  the address changes.
  """
  def build_email_token(user, context) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %UserToken{
       token: hashed_token,
       context: context,
       sent_to: user.email,
       user_id: user.id
     }}
  end

  @doc """
  Checks if a change-email token is valid and returns its lookup query.

  The query returns the user_token found by the token, if any.
  The context must always start with `"change:"`.
  """
  def verify_change_email_token_query(token, "change:" <> _ = context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from token in by_token_and_context_query(hashed_token, context),
            where: token.inserted_at > ago(@change_email_validity_in_days, "day")

        {:ok, query}

      :error ->
        :error
    end
  end

  @doc """
  Builds a one-time passkey login token. The plain token goes to the browser
  (hidden form field); only its hash is stored. The hash also covers
  `binding`, a secret from the browser's Plug session, so the token only
  works when posted from the browser that ran the passkey prompt.
  """
  def build_passkey_login_token(user, binding) when is_binary(binding) do
    token = :crypto.strong_rand_bytes(@rand_size)

    {Base.url_encode64(token, padding: false),
     %UserToken{
       token: passkey_login_hash(token, binding),
       context: "passkey_login",
       user_id: user.id
     }}
  end

  @doc """
  Returns a query for the unexpired passkey login token row, or `:error`.
  """
  def verify_passkey_login_token_query(token, binding)
      when is_binary(token) and is_binary(binding) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded} ->
        query =
          from t in by_token_and_context_query(
                 passkey_login_hash(decoded, binding),
                 "passkey_login"
               ),
               where: t.inserted_at > ago(@passkey_login_validity_in_seconds, "second")

        {:ok, query}

      :error ->
        :error
    end
  end

  defp passkey_login_hash(token, binding),
    do: :crypto.hash(@hash_algorithm, [token, :crypto.hash(@hash_algorithm, binding)])

  defp by_token_and_context_query(token, context) do
    from UserToken, where: [token: ^token, context: ^context]
  end
end
