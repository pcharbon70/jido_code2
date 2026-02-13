defmodule JidoCode.Setup.SystemConfig do
  @moduledoc """
  Onboarding state loader and progress persistence for setup routing.
  """

  @enforce_keys [:onboarding_completed, :onboarding_step, :onboarding_state]
  defstruct onboarding_completed: false, onboarding_step: 1, onboarding_state: %{}

  @type onboarding_state :: %{optional(String.t()) => map()}

  @type t :: %__MODULE__{
          onboarding_completed: boolean(),
          onboarding_step: pos_integer(),
          onboarding_state: onboarding_state()
        }

  @type load_error :: %{
          diagnostic: String.t(),
          detail: term(),
          onboarding_step: pos_integer()
        }

  @type save_error :: %{
          diagnostic: String.t(),
          detail: term(),
          onboarding_step: pos_integer()
        }

  @spec load() :: {:ok, t()} | {:error, load_error()}
  def load do
    with {:ok, raw_config} <- run_loader(),
         {:ok, config} <- normalize_config(raw_config) do
      {:ok, config}
    else
      {:error, reason} -> {:error, load_error(reason)}
    end
  end

  @spec save_step_progress(map()) :: {:ok, t()} | {:error, save_error()}
  def save_step_progress(validated_state) when is_map(validated_state) do
    case load() do
      {:ok, %__MODULE__{} = config} ->
        current_step = config.onboarding_step

        updated_config = %__MODULE__{
          config
          | onboarding_step: current_step + 1,
            onboarding_state: Map.put(config.onboarding_state, Integer.to_string(current_step), validated_state)
        }

        case persist_config(updated_config) do
          {:ok, persisted_config} ->
            {:ok, persisted_config}

          {:error, reason} ->
            {:error, save_error(reason, current_step)}
        end

      {:error, reason} ->
        {:error, save_error({:load_failed, reason}, onboarding_step_from_reason(reason))}
    end
  end

  def save_step_progress(_), do: {:error, save_error(:invalid_step_state, 1)}

  @doc false
  def default_loader do
    {:ok, Application.get_env(:jido_code, :system_config, %{})}
  end

  @doc false
  def default_saver(%__MODULE__{} = config) do
    persisted_config = %{
      onboarding_completed: config.onboarding_completed,
      onboarding_step: config.onboarding_step,
      onboarding_state: config.onboarding_state
    }

    Application.put_env(:jido_code, :system_config, persisted_config)

    {:ok, persisted_config}
  end

  defp run_loader do
    loader = Application.get_env(:jido_code, :system_config_loader, &__MODULE__.default_loader/0)

    if is_function(loader, 0) do
      safe_invoke_loader(loader)
    else
      {:error, :invalid_loader}
    end
  end

  defp run_saver(config) do
    saver = Application.get_env(:jido_code, :system_config_saver, &__MODULE__.default_saver/1)

    if is_function(saver, 1) do
      safe_invoke_saver(saver, config)
    else
      {:error, :invalid_saver}
    end
  end

  defp safe_invoke_loader(loader) do
    try do
      case loader.() do
        {:ok, _config} = result ->
          result

        {:error, _reason} = result ->
          result

        other ->
          {:error, {:invalid_loader_result, other}}
      end
    rescue
      exception ->
        {:error, {:loader_exception, Exception.message(exception)}}
    catch
      kind, reason ->
        {:error, {:loader_throw, {kind, reason}}}
    end
  end

  defp safe_invoke_saver(saver, config) do
    try do
      case saver.(config) do
        {:ok, _config} = result ->
          result

        {:error, _reason} = result ->
          result

        other ->
          {:error, {:invalid_saver_result, other}}
      end
    rescue
      exception ->
        {:error, {:saver_exception, Exception.message(exception)}}
    catch
      kind, reason ->
        {:error, {:saver_throw, {kind, reason}}}
    end
  end

  defp normalize_config(%__MODULE__{} = config), do: validate_config(config)

  defp normalize_config(config) when is_map(config) do
    validate_config(%__MODULE__{
      onboarding_completed: map_get(config, :onboarding_completed, "onboarding_completed", false),
      onboarding_step: map_get(config, :onboarding_step, "onboarding_step", 1),
      onboarding_state: map_get(config, :onboarding_state, "onboarding_state", %{})
    })
  end

  defp normalize_config(other), do: {:error, {:invalid_config, other}}

  defp validate_config(
         %__MODULE__{
           onboarding_completed: completed,
           onboarding_step: step,
           onboarding_state: onboarding_state
         } = config
       )
       when is_boolean(completed) and is_integer(step) and step > 0 and is_map(onboarding_state) do
    {:ok, config}
  end

  defp validate_config(%__MODULE__{} = config), do: {:error, {:invalid_config, config}}

  defp persist_config(%__MODULE__{} = config) do
    with {:ok, raw_config} <- run_saver(config),
         {:ok, normalized_config} <- normalize_config(raw_config) do
      {:ok, normalized_config}
    end
  end

  defp map_get(map, atom_key, string_key, default) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp load_error(reason) do
    %{
      onboarding_step: 1,
      detail: reason,
      diagnostic:
        "Unable to load SystemConfig. Continue setup from step 1 and verify configuration storage (#{format_reason(reason)})."
    }
  end

  defp save_error(reason, onboarding_step) do
    %{
      onboarding_step: onboarding_step,
      detail: reason,
      diagnostic:
        "Unable to persist onboarding progress. No progress was advanced, so you can safely retry this step (#{format_reason(reason)})."
    }
  end

  defp onboarding_step_from_reason(%{onboarding_step: onboarding_step})
       when is_integer(onboarding_step) and onboarding_step > 0 do
    onboarding_step
  end

  defp onboarding_step_from_reason(_), do: 1

  defp format_reason(reason), do: inspect(reason)
end
