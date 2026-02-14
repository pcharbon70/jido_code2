defmodule JidoCode.Agents.SupportAgentConfigs do
  @moduledoc """
  Reads and updates per-project Issue Bot configuration.
  """

  alias JidoCode.Projects.Project

  @load_error_type "support_agent_config_load_failed"
  @validation_error_type "support_agent_config_validation_failed"
  @not_found_error_type "support_agent_config_project_not_found"
  @persistence_error_type "support_agent_config_persistence_failed"

  @load_remediation """
  Retry loading agent configuration. If this persists, verify project access and database connectivity.
  """

  @validation_remediation """
  Select a valid project row and choose either Enable or Disable Issue Bot.
  """

  @not_found_remediation """
  Refresh the Agents page and retry from an existing project row.
  """

  @persistence_remediation """
  Retry the Issue Bot toggle. If this persists, verify project settings persistence health.
  """

  @type typed_error :: %{
          error_type: String.t(),
          detail: String.t(),
          remediation: String.t()
        }

  @type issue_bot_config :: %{
          id: String.t(),
          name: String.t(),
          github_full_name: String.t(),
          enabled: boolean()
        }

  @spec list_issue_bot_configs() :: {:ok, [issue_bot_config()]} | {:error, typed_error()}
  def list_issue_bot_configs do
    case list_projects() do
      {:ok, projects} ->
        {:ok, Enum.map(projects, &to_issue_bot_config/1)}

      {:error, typed_error} ->
        {:error, normalize_typed_error(typed_error, @load_error_type, @load_remediation)}
    end
  end

  @spec set_issue_bot_enabled(term(), term()) ::
          {:ok, issue_bot_config()} | {:error, typed_error()}
  def set_issue_bot_enabled(project_id, enabled_value) do
    with {:ok, normalized_project_id} <- normalize_project_id(project_id),
         {:ok, enabled} <- normalize_enabled_input(enabled_value),
         {:ok, project} <- fetch_project(normalized_project_id),
         settings <- project |> map_get(:settings, "settings", %{}) |> normalize_map(),
         updated_settings <- put_issue_bot_enabled(settings, enabled),
         {:ok, updated_project} <- persist_project_settings(project, updated_settings) do
      {:ok, to_issue_bot_config(updated_project)}
    else
      {:error, typed_error} ->
        {:error, typed_error}

      other ->
        {:error,
         typed_error(
           @persistence_error_type,
           "Issue Bot configuration update returned an unexpected result (#{inspect(other)}).",
           @persistence_remediation
         )}
    end
  end

  defp list_projects do
    loader =
      Application.get_env(
        :jido_code,
        :support_agent_config_project_loader,
        &__MODULE__.default_loader/0
      )

    if is_function(loader, 0) do
      safe_invoke_loader(loader)
    else
      {:error,
       typed_error(
         @load_error_type,
         "Support agent config loader is invalid.",
         @load_remediation
       )}
    end
  end

  @doc false
  @spec default_loader() :: {:ok, [Project.t()]} | {:error, typed_error()}
  def default_loader do
    case Project.read(query: [sort: [github_full_name: :asc]]) do
      {:ok, projects} when is_list(projects) ->
        {:ok, projects}

      {:ok, other} ->
        {:error,
         typed_error(
           @load_error_type,
           "Project loader returned an invalid list result (#{inspect(other)}).",
           @load_remediation
         )}

      {:error, reason} ->
        {:error,
         typed_error(
           @load_error_type,
           "Issue Bot configuration load failed (#{format_reason(reason)}).",
           @load_remediation
         )}
    end
  end

  defp safe_invoke_loader(loader) do
    try do
      loader.()
    rescue
      exception ->
        {:error,
         typed_error(
           @load_error_type,
           "Issue Bot configuration loader crashed (#{Exception.message(exception)}).",
           @load_remediation
         )}
    catch
      kind, reason ->
        {:error,
         typed_error(
           @load_error_type,
           "Issue Bot configuration loader threw #{inspect({kind, reason})}.",
           @load_remediation
         )}
    end
  end

  defp normalize_project_id(project_id) do
    case normalize_optional_string(project_id) do
      nil ->
        {:error,
         typed_error(
           @validation_error_type,
           "Project identifier is missing for Issue Bot configuration update.",
           @validation_remediation
         )}

      normalized_project_id ->
        {:ok, normalized_project_id}
    end
  end

  defp normalize_enabled_input(true), do: {:ok, true}
  defp normalize_enabled_input(false), do: {:ok, false}
  defp normalize_enabled_input("true"), do: {:ok, true}
  defp normalize_enabled_input("false"), do: {:ok, false}

  defp normalize_enabled_input(_enabled_value) do
    {:error,
     typed_error(
       @validation_error_type,
       "Issue Bot enabled state is invalid. Expected true or false.",
       @validation_remediation
     )}
  end

  defp fetch_project(project_id) do
    case Project.read(query: [filter: [id: project_id], limit: 1]) do
      {:ok, [project | _rest]} ->
        {:ok, project}

      {:ok, []} ->
        {:error,
         typed_error(
           @not_found_error_type,
           "Project #{project_id} was not found for Issue Bot configuration update.",
           @not_found_remediation
         )}

      {:error, reason} ->
        {:error,
         typed_error(
           @load_error_type,
           "Project lookup for Issue Bot configuration failed (#{format_reason(reason)}).",
           @load_remediation
         )}
    end
  end

  defp persist_project_settings(project, updated_settings) do
    updater =
      Application.get_env(
        :jido_code,
        :support_agent_config_project_updater,
        &__MODULE__.default_updater/2
      )

    if is_function(updater, 2) do
      safe_invoke_updater(updater, project, %{settings: updated_settings})
    else
      {:error,
       typed_error(
         @persistence_error_type,
         "Support agent config updater is invalid.",
         @persistence_remediation
       )}
    end
  end

  @doc false
  @spec default_updater(Project.t(), map()) :: {:ok, Project.t()} | {:error, term()}
  def default_updater(project, update_attributes) do
    Project.update(project, update_attributes)
  end

  defp safe_invoke_updater(updater, project, update_attributes) do
    try do
      case updater.(project, update_attributes) do
        {:ok, updated_project} ->
          {:ok, updated_project}

        {:error, reason} ->
          {:error,
           typed_error(
             @persistence_error_type,
             "Issue Bot configuration persistence failed (#{format_reason(reason)}).",
             @persistence_remediation
           )}

        other ->
          {:error,
           typed_error(
             @persistence_error_type,
             "Issue Bot configuration updater returned invalid output (#{inspect(other)}).",
             @persistence_remediation
           )}
      end
    rescue
      exception ->
        {:error,
         typed_error(
           @persistence_error_type,
           "Issue Bot configuration updater crashed (#{Exception.message(exception)}).",
           @persistence_remediation
         )}
    catch
      kind, reason ->
        {:error,
         typed_error(
           @persistence_error_type,
           "Issue Bot configuration updater threw #{inspect({kind, reason})}.",
           @persistence_remediation
         )}
    end
  end

  defp to_issue_bot_config(project) do
    settings =
      project
      |> map_get(:settings, "settings", %{})
      |> normalize_map()

    %{
      id:
        project
        |> map_get(:id, "id")
        |> normalize_optional_string() || "unknown-project",
      name:
        project
        |> map_get(:name, "name")
        |> normalize_optional_string() || "unknown-project",
      github_full_name:
        project
        |> map_get(:github_full_name, "github_full_name")
        |> normalize_optional_string() ||
          project
          |> map_get(:name, "name")
          |> normalize_optional_string() || "unknown-project",
      enabled: issue_bot_enabled(settings)
    }
  end

  defp issue_bot_enabled(settings) when is_map(settings) do
    settings
    |> map_get(:support_agent_config, "support_agent_config", %{})
    |> normalize_map()
    |> map_get(:github_issue_bot, "github_issue_bot", %{})
    |> normalize_map()
    |> map_get(:enabled, "enabled")
    |> normalize_enabled(true)
  end

  defp issue_bot_enabled(_settings), do: true

  defp put_issue_bot_enabled(settings, enabled) when is_map(settings) do
    support_agent_config =
      settings
      |> map_get(:support_agent_config, "support_agent_config", %{})
      |> normalize_map()

    issue_bot_config =
      support_agent_config
      |> map_get(:github_issue_bot, "github_issue_bot", %{})
      |> normalize_map()
      |> Map.put("enabled", enabled)

    support_agent_config
    |> Map.put("github_issue_bot", issue_bot_config)
    |> then(&Map.put(settings, "support_agent_config", &1))
  end

  defp put_issue_bot_enabled(_settings, enabled) do
    put_issue_bot_enabled(%{}, enabled)
  end

  defp normalize_typed_error(error, fallback_error_type, fallback_remediation) do
    typed_error(
      map_get(error, :error_type, "error_type", fallback_error_type),
      map_get(error, :detail, "detail", "Support agent configuration update failed."),
      map_get(error, :remediation, "remediation", fallback_remediation)
    )
  end

  defp typed_error(error_type, detail, remediation) do
    %{
      error_type: normalize_optional_string(error_type) || @persistence_error_type,
      detail: normalize_optional_string(detail) || "Support agent configuration update failed.",
      remediation: normalize_optional_string(remediation) || @persistence_remediation
    }
  end

  defp format_reason(reason) do
    reason
    |> Exception.message()
  rescue
    _exception -> inspect(reason)
  end

  defp normalize_enabled(true, _default), do: true
  defp normalize_enabled(false, _default), do: false
  defp normalize_enabled("true", _default), do: true
  defp normalize_enabled("false", _default), do: false
  defp normalize_enabled("enabled", _default), do: true
  defp normalize_enabled("disabled", _default), do: false
  defp normalize_enabled(:enabled, _default), do: true
  defp normalize_enabled(:disabled, _default), do: false
  defp normalize_enabled(_enabled, default), do: default

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized_value -> normalized_value
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: normalize_optional_string(Atom.to_string(value))

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_value), do: %{}

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(map, atom_key, string_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default
end
