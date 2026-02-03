defmodule AgentJido.Forge.SpriteClient.Behaviour do
  @moduledoc """
  Behaviour defining the interface for sprite client implementations.

  A sprite is an isolated execution environment (container, VM, or local sandbox)
  where Forge runners execute commands and manage files.
  """

  @type client :: term()
  @type sprite_id :: String.t()
  @type spec :: map()
  @type command :: String.t()
  @type path :: String.t()
  @type content :: binary()
  @type env_map :: %{String.t() => String.t()}
  @type handle :: term()
  @type opts :: keyword()

  @doc """
  Create a new sprite from the given specification.

  Returns the client state and a unique sprite identifier.
  """
  @callback create(spec()) :: {:ok, client(), sprite_id()} | {:error, term()}

  @doc """
  Execute a command synchronously in the sprite.

  Returns the output and exit code.
  """
  @callback exec(client(), command(), opts()) :: {String.t(), non_neg_integer()}

  @doc """
  Spawn an asynchronous command in the sprite.

  Returns a handle for monitoring or interacting with the process.
  """
  @callback spawn(client(), command(), args :: [String.t()], opts()) ::
              {:ok, handle()} | {:error, term()}

  @doc """
  Write content to a file in the sprite.
  """
  @callback write_file(client(), path(), content()) :: :ok | {:error, term()}

  @doc """
  Read content from a file in the sprite.
  """
  @callback read_file(client(), path()) :: {:ok, content()} | {:error, term()}

  @doc """
  Inject environment variables into the sprite.

  These should be available to all subsequent commands.
  """
  @callback inject_env(client(), env_map()) :: :ok | {:error, term()}

  @doc """
  Destroy the sprite and clean up resources.
  """
  @callback destroy(client(), sprite_id()) :: :ok | {:error, term()}

  @doc """
  Returns the implementation module for this client type.
  """
  @callback impl_module() :: module()
end
