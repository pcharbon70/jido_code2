defmodule AgentJido.Forge.Error do
  @moduledoc """
  Structured errors for Forge operations with recovery strategies.
  """

  defmodule ProvisionError do
    defexception [:reason, :sprite_spec]

    @impl true
    def message(%{reason: r}), do: "Failed to provision sprite: #{inspect(r)}"
  end

  defmodule BootstrapError do
    defexception [:step, :reason]

    @impl true
    def message(%{step: s, reason: r}), do: "Bootstrap failed at #{inspect(s)}: #{inspect(r)}"
  end

  defmodule ExecSessionError do
    defexception [:sequence, :runner, :reason, :exit_code]

    @impl true
    def message(%{sequence: s, runner: r, reason: reason}),
      do: "ExecSession #{s} failed (#{r}): #{inspect(reason)}"
  end

  defmodule TimeoutError do
    defexception [:sequence, :timeout_ms]

    @impl true
    def message(%{sequence: s, timeout_ms: t}), do: "Execution #{s} timed out after #{t}ms"
  end

  defmodule SpriteError do
    defexception [:operation, :reason]

    @impl true
    def message(%{operation: op, reason: r}), do: "Sprite #{op} failed: #{inspect(r)}"
  end

  @doc "Classify error and return recovery strategy"
  @spec classify(Exception.t()) :: {atom(), atom()}
  def classify(error) do
    case error do
      %TimeoutError{} -> {:timeout, :retry}
      %ExecSessionError{reason: :rate_limited} -> {:rate_limit, :retry}
      %SpriteError{operation: :exec} -> {:exec_failed, :checkpoint_restore}
      %ProvisionError{} -> {:provision_failed, :terminal}
      %BootstrapError{} -> {:bootstrap_failed, :terminal}
      _ -> {:unknown, :terminal}
    end
  end
end
