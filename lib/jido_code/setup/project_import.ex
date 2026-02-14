defmodule JidoCode.Setup.ProjectImport do
  @moduledoc """
  Imports the selected repository during setup step 7 and initializes baseline project metadata.
  """

  alias JidoCode.Projects.Project

  @default_selection_remediation "Select one of the repositories validated in step 4 and retry import."
  @default_importer_remediation "Verify project import configuration and retry step 7."
  @default_branch "main"

  @type status :: :ready | :blocked
  @type import_mode :: :created | :existing

  @type project_record :: %{
          id: String.t(),
          name: String.t(),
          github_full_name: String.t(),
          default_branch: String.t(),
          import_mode: import_mode(),
          imported_at: DateTime.t()
        }

  @type baseline_metadata :: %{
          workspace_initialized: boolean(),
          baseline_synced: boolean(),
          default_workflow_registered: boolean(),
          agent_configuration_registered: boolean(),
          status: :ready,
          initialized_at: DateTime.t()
        }

  @type report :: %{
          checked_at: DateTime.t(),
          status: status(),
          selected_repository: String.t() | nil,
          project_record: project_record() | nil,
          baseline_metadata: baseline_metadata() | nil,
          detail: String.t(),
          remediation: String.t(),
          error_type: String.t() | nil
        }

  @spec run(map() | nil, String.t() | nil, map() | nil) :: report()
  def run(previous_state \\ nil, selected_repository \\ nil, onboarding_state \\ %{}) do
    checked_at = DateTime.utc_now() |> DateTime.truncate(:second)
    available_repositories = available_repositories(onboarding_state)

    selected_repository =
      selected_repository
      |> normalize_repository(previous_selected_repository(previous_state))

    importer =
      Application.get_env(:jido_code, :setup_project_importer, &__MODULE__.default_importer/1)

    importer
    |> safe_invoke_importer(%{
      checked_at: checked_at,
      selected_repository: selected_repository,
      available_repositories: available_repositories,
      onboarding_state: onboarding_state
    })
    |> normalize_report(checked_at, selected_repository)
  end

  @spec available_repositories(map() | nil) :: [String.t()]
  def available_repositories(onboarding_state) when is_map(onboarding_state) do
    onboarding_state
    |> fetch_step_state(4)
    |> map_get(:github_credentials, "github_credentials", %{})
    |> map_get(:paths, "paths", [])
    |> normalize_paths()
    |> Enum.flat_map(fn path ->
      path_status =
        path
        |> map_get(:status, "status", nil)
        |> normalize_path_status(:blocked)

      repositories =
        path
        |> map_get(:repositories, "repositories", [])
        |> normalize_repositories()

      if path_status == :ready, do: repositories, else: []
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def available_repositories(_onboarding_state), do: []

  @spec blocked?(report() | nil) :: boolean()
  def blocked?(%{status: :ready}), do: false
  def blocked?(_), do: true

  @spec selected_repository(report() | nil) :: String.t() | nil
  def selected_repository(%{selected_repository: selected_repository})
      when is_binary(selected_repository),
      do: selected_repository

  def selected_repository(_report), do: nil

  @spec serialize_for_state(report() | nil) :: map()
  def serialize_for_state(%{
        checked_at: checked_at,
        status: status,
        selected_repository: selected_repository,
        project_record: project_record,
        baseline_metadata: baseline_metadata,
        detail: detail,
        remediation: remediation,
        error_type: error_type
      }) do
    %{
      "checked_at" => DateTime.to_iso8601(checked_at),
      "status" => Atom.to_string(status),
      "selected_repository" => selected_repository,
      "project_record" => serialize_project_record(project_record),
      "baseline_metadata" => serialize_baseline_metadata(baseline_metadata),
      "detail" => detail,
      "remediation" => remediation,
      "error_type" => error_type
    }
  end

  def serialize_for_state(_report), do: %{}

  @spec from_state(map() | nil) :: report() | nil
  def from_state(nil), do: nil

  def from_state(state) when is_map(state) do
    checked_at =
      state
      |> map_get(:checked_at, "checked_at")
      |> normalize_datetime(DateTime.utc_now() |> DateTime.truncate(:second))

    selected_repository =
      state
      |> map_get(:selected_repository, "selected_repository")
      |> normalize_repository(nil)

    project_record =
      state
      |> map_get(:project_record, "project_record", nil)
      |> normalize_project_record(checked_at)

    baseline_metadata =
      state
      |> map_get(:baseline_metadata, "baseline_metadata", nil)
      |> normalize_baseline_metadata(checked_at)

    status =
      state
      |> map_get(:status, "status", nil)
      |> normalize_status(default_status(project_record, baseline_metadata))

    error_type =
      state
      |> map_get(:error_type, "error_type", nil)
      |> normalize_error_type()

    detail =
      state
      |> map_get(:detail, "detail", nil)
      |> normalize_detail(status)

    remediation =
      state
      |> map_get(:remediation, "remediation", nil)
      |> normalize_remediation(status)

    normalized_status =
      if status == :ready and (is_nil(project_record) or is_nil(baseline_metadata)) do
        :blocked
      else
        status
      end

    %{
      checked_at: checked_at,
      status: normalized_status,
      selected_repository: selected_repository,
      project_record: if(normalized_status == :ready, do: project_record, else: nil),
      baseline_metadata: if(normalized_status == :ready, do: baseline_metadata, else: nil),
      detail: detail,
      remediation: remediation,
      error_type: if(normalized_status == :ready, do: nil, else: error_type)
    }
  end

  def from_state(_state), do: nil

  @doc false
  def default_importer(%{
        checked_at: checked_at,
        selected_repository: selected_repository,
        available_repositories: available_repositories,
        onboarding_state: onboarding_state
      })
      when is_list(available_repositories) and is_map(onboarding_state) do
    cond do
      is_nil(selected_repository) ->
        blocked_report(
          checked_at,
          nil,
          "repository_selection_missing",
          "Select a repository before importing your first project.",
          @default_selection_remediation
        )

      available_repositories != [] and selected_repository not in available_repositories ->
        blocked_report(
          checked_at,
          selected_repository,
          "repository_selection_unavailable",
          "Selected repository is not in the validated repository access list.",
          @default_selection_remediation
        )

      true ->
        default_branch =
          resolve_default_branch(selected_repository, onboarding_state, @default_branch)

        with {:ok, _owner, name} <- split_repository(selected_repository),
             {:ok, project, import_mode} <-
               ensure_project_record(name, selected_repository, default_branch) do
          baseline_metadata = baseline_metadata(checked_at)

          %{
            checked_at: checked_at,
            status: :ready,
            selected_repository: selected_repository,
            project_record: %{
              id: to_string(project.id),
              name: to_string(project.name),
              github_full_name: to_string(project.github_full_name),
              default_branch: to_string(project.default_branch),
              import_mode: import_mode,
              imported_at: checked_at
            },
            baseline_metadata: baseline_metadata,
            detail: "Repository import is complete and baseline metadata is ready.",
            remediation: "Project import is ready.",
            error_type: nil
          }
        else
          {:error, {error_type, detail}} ->
            blocked_report(
              checked_at,
              selected_repository,
              error_type,
              detail,
              @default_importer_remediation
            )
        end
    end
  end

  def default_importer(_context) do
    blocked_report(
      DateTime.utc_now() |> DateTime.truncate(:second),
      nil,
      "project_import_context_invalid",
      "Project importer context is invalid.",
      @default_importer_remediation
    )
  end

  defp safe_invoke_importer(importer, context) when is_function(importer, 1) do
    try do
      case importer.(context) do
        %{} = report -> {:ok, report}
        {:ok, %{} = report} -> {:ok, report}
        {:error, reason} -> {:error, reason}
        other -> {:error, {:invalid_importer_result, other}}
      end
    rescue
      exception ->
        {:error, {:importer_exception, Exception.message(exception)}}
    catch
      kind, reason ->
        {:error, {:importer_throw, {kind, reason}}}
    end
  end

  defp safe_invoke_importer(_importer, _context), do: {:error, :invalid_importer}

  defp normalize_report({:ok, report}, checked_at, selected_repository) do
    case from_state(report) do
      nil ->
        blocked_report(
          checked_at,
          selected_repository,
          "project_import_invalid_report",
          "Project import returned an invalid report.",
          @default_importer_remediation
        )

      normalized_report ->
        %{
          normalized_report
          | selected_repository: normalized_report.selected_repository || selected_repository
        }
    end
  end

  defp normalize_report({:error, {error_type, detail}}, checked_at, selected_repository) do
    blocked_report(
      checked_at,
      selected_repository,
      normalize_error_type(error_type) || "project_import_failed",
      normalize_error_detail(detail),
      @default_importer_remediation
    )
  end

  defp normalize_report({:error, reason}, checked_at, selected_repository) do
    blocked_report(
      checked_at,
      selected_repository,
      "project_import_failed",
      "Project import failed (#{inspect(reason)}).",
      @default_importer_remediation
    )
  end

  defp blocked_report(checked_at, selected_repository, error_type, detail, remediation) do
    %{
      checked_at: checked_at,
      status: :blocked,
      selected_repository: selected_repository,
      project_record: nil,
      baseline_metadata: nil,
      detail: detail,
      remediation: remediation,
      error_type: error_type
    }
  end

  defp ensure_project_record(name, selected_repository, default_branch) do
    case Project.read(query: [filter: [github_full_name: selected_repository], limit: 1]) do
      {:ok, [existing_project | _]} ->
        update_attributes = %{
          name: name,
          default_branch: default_branch
        }

        case Project.update(existing_project, update_attributes) do
          {:ok, updated_project} ->
            {:ok, updated_project, :existing}

          {:error, reason} ->
            {:error, {"project_persistence_update_failed", format_reason(reason)}}
        end

      {:ok, []} ->
        create_attributes = %{
          name: name,
          github_full_name: selected_repository,
          default_branch: default_branch
        }

        case Project.create(create_attributes) do
          {:ok, project} ->
            {:ok, project, :created}

          {:error, reason} ->
            {:error, {"project_persistence_create_failed", format_reason(reason)}}
        end

      {:error, reason} ->
        {:error, {"project_persistence_lookup_failed", format_reason(reason)}}
    end
  end

  defp baseline_metadata(checked_at) do
    %{
      workspace_initialized: true,
      baseline_synced: true,
      default_workflow_registered: true,
      agent_configuration_registered: true,
      status: :ready,
      initialized_at: checked_at
    }
  end

  defp split_repository(selected_repository) when is_binary(selected_repository) do
    case String.split(selected_repository, "/", parts: 2) do
      [owner, name] when owner != "" and name != "" ->
        {:ok, owner, name}

      _parts ->
        {:error, {"repository_selection_invalid", "Repository must use `owner/name` format."}}
    end
  end

  defp split_repository(_selected_repository),
    do: {:error, {"repository_selection_invalid", "Repository must use `owner/name` format."}}

  defp serialize_project_record(nil), do: nil

  defp serialize_project_record(project_record) when is_map(project_record) do
    %{
      "id" => map_get(project_record, :id, "id"),
      "name" => map_get(project_record, :name, "name"),
      "github_full_name" =>
        map_get(project_record, :github_full_name, "github_full_name") ||
          map_get(project_record, :full_name, "full_name"),
      "full_name" =>
        map_get(project_record, :github_full_name, "github_full_name") ||
          map_get(project_record, :full_name, "full_name"),
      "default_branch" => map_get(project_record, :default_branch, "default_branch", @default_branch),
      "import_mode" =>
        project_record
        |> map_get(:import_mode, "import_mode")
        |> normalize_import_mode(:existing)
        |> Atom.to_string(),
      "imported_at" =>
        project_record
        |> map_get(:imported_at, "imported_at")
        |> normalize_datetime(DateTime.utc_now() |> DateTime.truncate(:second))
        |> DateTime.to_iso8601()
    }
  end

  defp serialize_project_record(_project_record), do: nil

  defp serialize_baseline_metadata(nil), do: nil

  defp serialize_baseline_metadata(baseline_metadata) when is_map(baseline_metadata) do
    %{
      "workspace_initialized" => map_get(baseline_metadata, :workspace_initialized, "workspace_initialized", false),
      "baseline_synced" => map_get(baseline_metadata, :baseline_synced, "baseline_synced", false),
      "default_workflow_registered" =>
        map_get(
          baseline_metadata,
          :default_workflow_registered,
          "default_workflow_registered",
          false
        ),
      "agent_configuration_registered" =>
        map_get(
          baseline_metadata,
          :agent_configuration_registered,
          "agent_configuration_registered",
          false
        ),
      "status" =>
        baseline_metadata
        |> map_get(:status, "status", :blocked)
        |> normalize_status(:blocked)
        |> Atom.to_string(),
      "initialized_at" =>
        baseline_metadata
        |> map_get(:initialized_at, "initialized_at")
        |> normalize_datetime(DateTime.utc_now() |> DateTime.truncate(:second))
        |> DateTime.to_iso8601()
    }
  end

  defp serialize_baseline_metadata(_baseline_metadata), do: nil

  defp normalize_project_record(project_record, default_imported_at)
       when is_map(project_record) do
    id = project_record |> map_get(:id, "id") |> normalize_optional_string()
    name = project_record |> map_get(:name, "name") |> normalize_optional_string()

    github_full_name =
      project_record
      |> map_get(:github_full_name, "github_full_name")
      |> case do
        nil -> map_get(project_record, :full_name, "full_name")
        github_full_name -> github_full_name
      end
      |> normalize_optional_string()

    default_branch =
      project_record
      |> map_get(:default_branch, "default_branch", @default_branch)
      |> normalize_optional_string()
      |> case do
        nil -> @default_branch
        normalized_default_branch -> normalized_default_branch
      end

    if Enum.all?([id, name, github_full_name, default_branch], &is_binary/1) do
      %{
        id: id,
        name: name,
        github_full_name: github_full_name,
        default_branch: default_branch,
        import_mode:
          project_record
          |> map_get(:import_mode, "import_mode")
          |> normalize_import_mode(:existing),
        imported_at:
          project_record
          |> map_get(:imported_at, "imported_at")
          |> normalize_datetime(default_imported_at)
      }
    else
      nil
    end
  end

  defp normalize_project_record(_project_record, _default_imported_at), do: nil

  defp normalize_baseline_metadata(baseline_metadata, default_initialized_at)
       when is_map(baseline_metadata) do
    workspace_initialized =
      map_get(baseline_metadata, :workspace_initialized, "workspace_initialized", false) == true

    baseline_synced =
      map_get(baseline_metadata, :baseline_synced, "baseline_synced", false) == true

    default_workflow_registered =
      map_get(
        baseline_metadata,
        :default_workflow_registered,
        "default_workflow_registered",
        false
      ) == true

    agent_configuration_registered =
      map_get(
        baseline_metadata,
        :agent_configuration_registered,
        "agent_configuration_registered",
        false
      ) == true

    status =
      baseline_metadata
      |> map_get(:status, "status", nil)
      |> normalize_status(
        default_baseline_status(
          workspace_initialized,
          baseline_synced,
          default_workflow_registered,
          agent_configuration_registered
        )
      )

    initialized_at =
      baseline_metadata
      |> map_get(:initialized_at, "initialized_at")
      |> normalize_datetime(default_initialized_at)

    if status == :ready do
      %{
        workspace_initialized: workspace_initialized,
        baseline_synced: baseline_synced,
        default_workflow_registered: default_workflow_registered,
        agent_configuration_registered: agent_configuration_registered,
        status: :ready,
        initialized_at: initialized_at
      }
    else
      nil
    end
  end

  defp normalize_baseline_metadata(_baseline_metadata, _default_initialized_at), do: nil

  defp normalize_paths(paths) when is_list(paths), do: paths
  defp normalize_paths(_paths), do: []

  defp normalize_repositories(repositories) when is_list(repositories) do
    repositories
    |> Enum.map(&repository_full_name/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_repositories(_repositories), do: []

  defp resolve_default_branch(selected_repository, onboarding_state, fallback)
       when is_binary(selected_repository) and is_map(onboarding_state) do
    selected_repository
    |> repository_metadata(onboarding_state)
    |> map_get(:default_branch, "default_branch", fallback)
    |> normalize_branch_name(fallback)
  end

  defp resolve_default_branch(_selected_repository, _onboarding_state, fallback), do: fallback

  defp repository_metadata(selected_repository, onboarding_state)
       when is_binary(selected_repository) and is_map(onboarding_state) do
    repository_sources(onboarding_state)
    |> Enum.find(%{}, fn repository ->
      repository
      |> repository_full_name()
      |> normalize_repository(nil) == selected_repository
    end)
  end

  defp repository_metadata(_selected_repository, _onboarding_state), do: %{}

  defp repository_sources(onboarding_state) when is_map(onboarding_state) do
    step_7_repositories =
      onboarding_state
      |> fetch_step_state(7)
      |> map_get(:repository_listing, "repository_listing", %{})
      |> map_get(:repositories, "repositories", [])
      |> normalize_paths()

    step_4_repositories =
      onboarding_state
      |> fetch_step_state(4)
      |> map_get(:github_credentials, "github_credentials", %{})
      |> map_get(:paths, "paths", [])
      |> normalize_paths()
      |> Enum.flat_map(fn path ->
        path
        |> map_get(:repositories, "repositories", [])
        |> normalize_paths()
      end)

    step_7_repositories ++ step_4_repositories
  end

  defp repository_sources(_onboarding_state), do: []

  defp default_status(project_record, baseline_metadata) do
    if is_map(project_record) and is_map(baseline_metadata), do: :ready, else: :blocked
  end

  defp default_baseline_status(true, true, true, true), do: :ready
  defp default_baseline_status(_, _, _, _), do: :blocked

  defp previous_selected_repository(previous_state) do
    previous_state
    |> from_state()
    |> selected_repository()
  end

  defp normalize_import_mode(:created, _default), do: :created
  defp normalize_import_mode(:existing, _default), do: :existing
  defp normalize_import_mode("created", _default), do: :created
  defp normalize_import_mode("existing", _default), do: :existing
  defp normalize_import_mode(_import_mode, default), do: default

  defp normalize_status(:ready, _default), do: :ready
  defp normalize_status(:blocked, _default), do: :blocked
  defp normalize_status("ready", _default), do: :ready
  defp normalize_status("blocked", _default), do: :blocked
  defp normalize_status(_status, default), do: default

  defp normalize_path_status(:ready, _default), do: :ready
  defp normalize_path_status("ready", _default), do: :ready
  defp normalize_path_status(_status, default), do: default

  defp normalize_datetime(%DateTime{} = datetime, _default), do: datetime

  defp normalize_datetime(datetime, default) when is_binary(datetime) do
    case DateTime.from_iso8601(datetime) do
      {:ok, parsed_datetime, _offset} -> parsed_datetime
      _other -> default
    end
  end

  defp normalize_datetime(_datetime, default), do: default

  defp normalize_repository(repository, fallback) when is_binary(repository) do
    case String.trim(repository) do
      "" -> fallback
      normalized_repository -> normalized_repository
    end
  end

  defp normalize_repository(_repository, fallback), do: fallback

  defp repository_full_name(repository) when is_binary(repository),
    do: normalize_repository(repository, nil)

  defp repository_full_name(repository) when is_map(repository) do
    repository
    |> map_get(:full_name, "full_name")
    |> normalize_repository(nil)
  end

  defp repository_full_name(_repository), do: nil

  defp normalize_branch_name(value, fallback) when is_binary(value) do
    case String.trim(value) do
      "" -> fallback
      normalized_branch -> normalized_branch
    end
  end

  defp normalize_branch_name(_value, fallback), do: fallback

  defp normalize_detail(nil, :ready),
    do: "Repository import is complete and baseline metadata is ready."

  defp normalize_detail(nil, :blocked),
    do: "Repository import is blocked until a valid repository is selected and import succeeds."

  defp normalize_detail(detail, _status) when is_binary(detail) and detail != "", do: detail
  defp normalize_detail(_detail, _status), do: "Project import status is unavailable."

  defp normalize_remediation(nil, :ready), do: "Project import is ready."

  defp normalize_remediation(nil, :blocked),
    do: "Resolve project import validation failures and retry step 7."

  defp normalize_remediation(remediation, _status)
       when is_binary(remediation) and remediation != "",
       do: remediation

  defp normalize_remediation(_remediation, _status), do: @default_importer_remediation

  defp normalize_error_type(error_type) when is_atom(error_type), do: Atom.to_string(error_type)

  defp normalize_error_type(error_type) when is_binary(error_type) do
    case String.trim(error_type) do
      "" -> nil
      normalized_error_type -> normalized_error_type
    end
  end

  defp normalize_error_type(_error_type), do: nil

  defp normalize_error_detail(detail) when is_binary(detail) and detail != "", do: detail
  defp normalize_error_detail(detail), do: inspect(detail)

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized_value -> normalized_value
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: normalize_optional_string(Atom.to_string(value))

  defp normalize_optional_string(_value), do: nil

  defp fetch_step_state(onboarding_state, onboarding_step) when is_map(onboarding_state) do
    step_key = Integer.to_string(onboarding_step)
    Map.get(onboarding_state, step_key) || Map.get(onboarding_state, onboarding_step) || %{}
  end

  defp fetch_step_state(_onboarding_state, _onboarding_step), do: %{}

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(map, atom_key, string_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default

  defp format_reason(reason) do
    reason
    |> Exception.message()
  rescue
    _exception -> inspect(reason)
  end
end
