defmodule Phoenix.Token do
  @moduledoc """
  Tokens provide a way to  generate, verify bearer
  tokens for use in Channels or API authentication.

  ## Basic Usage

  When generating a unique token for usage in an API or Channel
  it is advised to use a unique identifier for the user typically
  the id from a database. For example:

      iex> user_id = 1
      iex> token = Phoenix.Token.sign(endpoint, "user", user_id)
      iex> Phoenix.Token.verify(endpoint, token)
      {:ok, 1}

  In that example we have a user's id, we generate a token and send
  it to the client. We could send it to the client in multiple ways.
  One is via the meta tag:

      <%= tag :meta, name: "channel_token"
                     content: Phoenix.Token.sign(@conn, "user", @current_user.id) %>

  Or an endpoint that returns it:

      def create(conn, params) do
        user = User.create(params)
        render conn, "user.json",
               %{token: Phoenix.Token.sign(conn, "user", user.id), user: user}
      end

  When using it with a socket a typical example might be:

    defmodule MyApp.UserSocket do
      use Phoenix.Socket

      def connect(%{"token" => token}, socket) do
        # Max age of 2 weeks (1209600 seconds)
        case Phoenix.Token.verify(socket, "user", token, max_age: 1209600) do
          {:ok, user_id} ->
            socket = assigns(socket, :user, Repo.get!(User, user_id))
            {:ok, socket}
          {:error, _} ->
            :error
        end
      end
    end

  In this example the phoenix.js client will be sending up the token
  in the connect command.

  `Phoenix.Token` can also be used for validating APIs, handling
  password resets, e-mail confirmation and more.
  """

  alias Plug.Crypto.KeyGenerator
  alias Plug.Crypto.MessageVerifier

  @doc """
  Signs your data into a token you can send down to clients

  ## Options
    * `:key_iterations` - option passed to `Plug.Crypto.KeyGenerator`
      when generating the encryption and signing keys. Defaults to 1000;
    * `:key_length` - option passed to `Plug.Crypto.KeyGenerator`
      when generating the encryption and signing keys. Defaults to 32;
    * `:key_digest` - option passed to `Plug.Crypto.KeyGenerator`
      when generating the encryption and signing keys. Defaults to `:sha256';
  """
  def sign(context, salt, data, opts \\ []) when is_binary(salt) do
    secret = get_endpoint(context) |> get_secret(salt, opts)

    message = %{
      data: data,
      signed: now_ms()
    } |> :erlang.term_to_binary()
    MessageVerifier.sign(message, secret)
  end

  @doc """
  Decrypts the token into the originaly present data.

  ## Options

    * `:max_age` - verifies the token only if it has been generated
      "max age" ago in seconds. A reasonable value is 2 weeks (`1209600`
      seconds);
    * `:key_iterations` - option passed to `Plug.Crypto.KeyGenerator`
      when generating the encryption and signing keys. Defaults to 1000;
    * `:key_length` - option passed to `Plug.Crypto.KeyGenerator`
      when generating the encryption and signing keys. Defaults to 32;
    * `:key_digest` - option passed to `Plug.Crypto.KeyGenerator`
      when generating the encryption and signing keys. Defaults to `:sha256';

  """
  def verify(context, salt, token, opts \\ []) when is_binary(salt) and is_binary(token) do
    secret = get_endpoint(context) |> get_secret(salt, opts)
    case MessageVerifier.verify(token, secret) do
      {:ok, message} ->
        %{data: data, signed: signed} = :erlang.binary_to_term(message)

        if (max_age = opts[:max_age]) && (signed + max_age) < now_ms() do
          {:error, :expired}
        else
          {:ok, data}
        end
      :error ->
        {:error, :invalid}
    end
  end

  defp get_endpoint(%Plug.Conn{} = conn), do: Phoenix.Controller.endpoint_module(conn)
  defp get_endpoint(%Phoenix.Socket{} = socket), do: socket.endpoint
  defp get_endpoint(endpoint) when is_atom(endpoint), do: endpoint

  # Gathers configuration and generates the key secrets and signing secrets.
  defp get_secret(endpoint, salt, opts) do
    secret_key_base = endpoint.config(:secret_key_base)
    iterations = Keyword.get(opts, :key_iterations, 1000)
    length = Keyword.get(opts, :key_length, 32)
    digest = Keyword.get(opts, :key_digest, :sha256)
    key_opts = [iterations: iterations,
                length: length,
                digest: digest,
                cache: Plug.Keys]
    KeyGenerator.generate(secret_key_base, salt, key_opts)
  end

  defp time_to_ms({mega, sec, _micro}), do: (mega * 1000000 + sec) * 1000
  defp now_ms, do: :os.timestamp() |> time_to_ms()
end
