defmodule JidoCode.GitHub.WebhookPipeline do
  @moduledoc """
  Routes verified webhook deliveries into downstream pipeline stages.
  """

  require Logger

  alias JidoCode.GitHub.Repo
  alias JidoCode.GitHub.WebhookDelivery
  alias JidoCode.Setup.GitHubInstallationSync

  @type verified_delivery :: %{
          delivery_id: String.t() | nil,
          event: String.t() | nil,
          payload: map(),
          raw_payload: binary()
        }

  @type dispatch_decision :: :dispatch | :duplicate

  @spec route_verified_delivery(verified_delivery()) :: :ok | {:error, :verified_dispatch_failed}
  def route_verified_delivery(%{} = delivery) do
    with {:ok, dispatch_decision} <- persist_delivery_for_idempotency(delivery) do
      case dispatch_decision do
        :dispatch ->
          maybe_sync_installation_metadata(delivery)
          dispatch_verified_delivery(delivery)

        :duplicate ->
          :ok
      end
    else
      {:error, reason} ->
        Logger.error(
          "github_webhook_delivery_persist_failed reason=#{inspect(reason)} delivery_id=#{log_value(Map.get(delivery, :delivery_id))} event=#{log_value(Map.get(delivery, :event))}"
        )

        {:error, :verified_dispatch_failed}
    end
  end

  @doc false
  @spec default_dispatcher(verified_delivery()) :: :ok
  def default_dispatcher(%{} = delivery) do
    Logger.info(
      "github_webhook_pipeline_handoff stage=idempotency stage_next=trigger_mapping delivery_id=#{log_value(Map.get(delivery, :delivery_id))} event=#{log_value(Map.get(delivery, :event))}"
    )

    :ok
  end

  @spec persist_delivery_for_idempotency(verified_delivery()) ::
          {:ok, dispatch_decision()} | {:error, term()}
  defp persist_delivery_for_idempotency(%{} = delivery) do
    with {:ok, delivery_id} <- normalize_required_string(Map.get(delivery, :delivery_id), :missing_delivery_id),
         {:ok, existing_delivery} <- get_delivery_by_id(delivery_id),
         {:ok, dispatch_decision} <-
           persist_or_acknowledge_duplicate(existing_delivery, delivery, delivery_id) do
      {:ok, dispatch_decision}
    end
  end

  @spec persist_or_acknowledge_duplicate(WebhookDelivery.t() | nil, verified_delivery(), String.t()) ::
          {:ok, dispatch_decision()} | {:error, term()}
  defp persist_or_acknowledge_duplicate(%WebhookDelivery{}, delivery, delivery_id) do
    log_duplicate_delivery_ack(delivery_id, Map.get(delivery, :event))
    {:ok, :duplicate}
  end

  defp persist_or_acknowledge_duplicate(nil, delivery, delivery_id) do
    with {:ok, event} <- normalize_required_string(Map.get(delivery, :event), :missing_event),
         {:ok, payload} <- normalize_payload(Map.get(delivery, :payload)),
         {:ok, repo_id} <- resolve_repo_id(event, payload),
         {:ok, dispatch_decision} <- create_delivery_record(delivery_id, event, payload, repo_id) do
      {:ok, dispatch_decision}
    end
  end

  @spec create_delivery_record(String.t(), String.t(), map(), Ash.UUID.t()) ::
          {:ok, dispatch_decision()} | {:error, term()}
  defp create_delivery_record(delivery_id, event, payload, repo_id) do
    case WebhookDelivery.create(
           %{
             github_delivery_id: delivery_id,
             event_type: event,
             action: normalize_action(payload),
             payload: payload,
             repo_id: repo_id
           },
           authorize?: false
         ) do
      {:ok, %WebhookDelivery{}} ->
        Logger.info(
          "github_webhook_delivery_persisted outcome=recorded delivery_id=#{delivery_id} event=#{event} repo_id=#{repo_id}"
        )

        {:ok, :dispatch}

      {:error, reason} ->
        resolve_delivery_create_error(delivery_id, event, reason)
    end
  end

  @spec resolve_delivery_create_error(String.t(), String.t(), term()) ::
          {:ok, dispatch_decision()} | {:error, term()}
  defp resolve_delivery_create_error(delivery_id, event, reason) do
    case get_delivery_by_id(delivery_id) do
      {:ok, %WebhookDelivery{}} ->
        log_duplicate_delivery_ack(delivery_id, event)
        {:ok, :duplicate}

      {:ok, nil} ->
        {:error, {:delivery_persist_failed, reason}}

      {:error, lookup_reason} ->
        {:error, {:delivery_persist_failed, {reason, lookup_reason}}}
    end
  end

  @spec get_delivery_by_id(String.t()) :: {:ok, WebhookDelivery.t() | nil} | {:error, term()}
  defp get_delivery_by_id(delivery_id) when is_binary(delivery_id) do
    case WebhookDelivery.get_by_github_delivery_id(delivery_id, authorize?: false) do
      {:ok, %WebhookDelivery{} = delivery} ->
        {:ok, delivery}

      {:ok, nil} ->
        {:ok, nil}

      {:error, reason} ->
        if ash_not_found?(reason) do
          {:ok, nil}
        else
          {:error, reason}
        end
    end
  end

  @spec resolve_repo_id(String.t(), map()) :: {:ok, Ash.UUID.t()} | {:error, term()}
  defp resolve_repo_id(event, payload) when is_binary(event) and is_map(payload) do
    with {:ok, %Repo{id: repo_id}} <- resolve_repo_for_event(event, payload) do
      {:ok, repo_id}
    end
  end

  @spec resolve_repo_for_event(String.t(), map()) :: {:ok, Repo.t()} | {:error, term()}
  defp resolve_repo_for_event(event, payload) when is_binary(event) and is_map(payload) do
    case extract_repo_full_name(payload) do
      {:ok, repo_full_name} ->
        if installation_event?(event) do
          get_or_create_repo_by_full_name(repo_full_name, extract_installation_id(payload))
        else
          get_repo_by_full_name(repo_full_name)
        end

      {:error, :missing_repository_full_name} ->
        resolve_installation_repo(event, payload)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec resolve_installation_repo(String.t(), map()) :: {:ok, Repo.t()} | {:error, term()}
  defp resolve_installation_repo(event, payload) when is_binary(event) and is_map(payload) do
    if installation_event?(event) do
      with {:ok, repository_candidates} <- repository_name_candidates(payload),
           {:ok, repo_full_name} <- first_repository_candidate(repository_candidates) do
        get_or_create_repo_by_full_name(repo_full_name, extract_installation_id(payload))
      else
        {:error, :missing_repository_candidates} ->
          resolve_repo_by_installation_id(payload)

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :missing_repository_full_name}
    end
  end

  @spec resolve_repo_by_installation_id(map()) :: {:ok, Repo.t()} | {:error, term()}
  defp resolve_repo_by_installation_id(payload) when is_map(payload) do
    case extract_installation_id(payload) do
      nil ->
        {:error, :missing_installation_id}

      installation_id ->
        case Repo.read(
               query: [
                 filter: [github_app_installation_id: installation_id],
                 sort: [inserted_at: :asc],
                 limit: 1
               ],
               authorize?: false
             ) do
          {:ok, [%Repo{} = repo | _rest]} ->
            {:ok, repo}

          {:ok, []} ->
            {:error, :repo_not_found_for_installation_event}

          {:error, reason} ->
            {:error, {:repo_lookup_failed, reason}}
        end
    end
  end

  @spec get_or_create_repo_by_full_name(String.t(), integer() | nil) ::
          {:ok, Repo.t()} | {:error, term()}
  defp get_or_create_repo_by_full_name(repo_full_name, installation_id)
       when is_binary(repo_full_name) do
    case get_repo_by_full_name(repo_full_name) do
      {:ok, %Repo{} = repo} ->
        maybe_update_repo_installation(repo, installation_id)

      {:error, :repo_not_found} ->
        with {:ok, owner, name} <- split_repo_full_name(repo_full_name),
             {:ok, %Repo{} = repo} <-
               create_repo_for_event(owner, name, installation_id, repo_full_name) do
          {:ok, repo}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec create_repo_for_event(String.t(), String.t(), integer() | nil, String.t()) ::
          {:ok, Repo.t()} | {:error, term()}
  defp create_repo_for_event(owner, name, installation_id, repo_full_name)
       when is_binary(owner) and is_binary(name) do
    attributes =
      %{
        owner: owner,
        name: name
      }
      |> maybe_put_installation_id(installation_id)

    case Repo.create(attributes, authorize?: false) do
      {:ok, %Repo{} = repo} ->
        Logger.info(
          "github_webhook_repo_anchor_created repo_full_name=#{repo_full_name} installation_id=#{log_integer_value(installation_id)}"
        )

        {:ok, repo}

      {:error, reason} ->
        {:error, {:repo_create_failed, reason}}
    end
  end

  @spec maybe_update_repo_installation(Repo.t(), integer() | nil) :: {:ok, Repo.t()} | {:error, term()}
  defp maybe_update_repo_installation(%Repo{} = repo, nil), do: {:ok, repo}

  defp maybe_update_repo_installation(%Repo{} = repo, installation_id) when is_integer(installation_id) do
    current_installation_id = Map.get(repo, :github_app_installation_id)

    if current_installation_id == installation_id do
      {:ok, repo}
    else
      case Repo.update(repo, %{github_app_installation_id: installation_id}, authorize?: false) do
        {:ok, %Repo{} = updated_repo} ->
          {:ok, updated_repo}

        {:error, reason} ->
          {:error, {:repo_installation_update_failed, reason}}
      end
    end
  end

  @spec split_repo_full_name(String.t()) :: {:ok, String.t(), String.t()} | {:error, :invalid_repository_full_name}
  defp split_repo_full_name(repo_full_name) when is_binary(repo_full_name) do
    case String.split(repo_full_name, "/", parts: 2) do
      [owner, name] when owner != "" and name != "" ->
        {:ok, owner, name}

      _other ->
        {:error, :invalid_repository_full_name}
    end
  end

  @spec repository_name_candidates(map()) :: {:ok, [String.t()]} | {:error, :missing_repository_candidates}
  defp repository_name_candidates(payload) when is_map(payload) do
    candidates =
      payload
      |> repository_candidate_sources()
      |> Enum.flat_map(&extract_repository_full_names/1)
      |> Enum.uniq()

    case candidates do
      [] -> {:error, :missing_repository_candidates}
      repository_candidates -> {:ok, repository_candidates}
    end
  end

  @spec first_repository_candidate([String.t()]) ::
          {:ok, String.t()} | {:error, :missing_repository_candidates}
  defp first_repository_candidate([repo_full_name | _rest]) when is_binary(repo_full_name),
    do: {:ok, repo_full_name}

  defp first_repository_candidate(_repository_candidates), do: {:error, :missing_repository_candidates}

  @spec repository_candidate_sources(map()) :: [term()]
  defp repository_candidate_sources(payload) when is_map(payload) do
    [
      map_get(payload, :repositories, "repositories", []),
      map_get(payload, :repositories_added, "repositories_added", []),
      map_get(payload, :repositories_removed, "repositories_removed", [])
    ]
  end

  @spec extract_repository_full_names(term()) :: [String.t()]
  defp extract_repository_full_names(repositories) when is_list(repositories) do
    repositories
    |> Enum.map(&extract_repository_full_name/1)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_repository_full_names(_repositories), do: []

  @spec extract_repository_full_name(term()) :: String.t() | nil
  defp extract_repository_full_name(repository) when is_binary(repository) do
    normalize_optional_string(repository)
  end

  defp extract_repository_full_name(repository) when is_map(repository) do
    repository
    |> map_get(:full_name, "full_name")
    |> normalize_optional_string()
    |> case do
      nil ->
        owner =
          repository
          |> map_get(:owner, "owner")
          |> normalize_owner_value()

        name =
          repository
          |> map_get(:name, "name")
          |> normalize_optional_string()

        if owner && name, do: "#{owner}/#{name}", else: nil

      repository_full_name ->
        repository_full_name
    end
  end

  defp extract_repository_full_name(_repository), do: nil

  @spec normalize_owner_value(term()) :: String.t() | nil
  defp normalize_owner_value(owner) when is_binary(owner) do
    normalize_optional_string(owner)
  end

  defp normalize_owner_value(%{} = owner) do
    owner
    |> map_get(:login, "login")
    |> normalize_optional_string()
  end

  defp normalize_owner_value(_owner), do: nil

  @spec maybe_put_installation_id(map(), integer() | nil) :: map()
  defp maybe_put_installation_id(attributes, installation_id) when is_integer(installation_id) do
    Map.put(attributes, :github_app_installation_id, installation_id)
  end

  defp maybe_put_installation_id(attributes, _installation_id), do: attributes

  @spec installation_event?(String.t()) :: boolean()
  defp installation_event?(event) when is_binary(event) do
    event in ["installation", "installation_repositories"]
  end

  @spec extract_installation_id(map()) :: integer() | nil
  defp extract_installation_id(payload) when is_map(payload) do
    payload
    |> map_get(:installation, "installation", %{})
    |> map_get(:id, "id")
    |> normalize_installation_id()
  end

  defp extract_installation_id(_payload), do: nil

  @spec normalize_installation_id(term()) :: integer() | nil
  defp normalize_installation_id(value) when is_integer(value) and value > 0, do: value

  defp normalize_installation_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed_value, ""} when parsed_value > 0 -> parsed_value
      _other -> nil
    end
  end

  defp normalize_installation_id(_value), do: nil

  @spec extract_repo_full_name(map()) :: {:ok, String.t()} | {:error, :missing_repository_full_name}
  defp extract_repo_full_name(payload) when is_map(payload) do
    repository =
      Map.get(payload, "repository") ||
        Map.get(payload, :repository)

    full_name =
      case repository do
        %{} = repository_map ->
          Map.get(repository_map, "full_name") || Map.get(repository_map, :full_name)

        _other ->
          nil
      end

    normalize_required_string(full_name, :missing_repository_full_name)
  end

  @spec get_repo_by_full_name(String.t()) :: {:ok, Repo.t()} | {:error, term()}
  defp get_repo_by_full_name(repo_full_name) when is_binary(repo_full_name) do
    case Repo.get_by_full_name(repo_full_name, authorize?: false) do
      {:ok, %Repo{} = repo} ->
        {:ok, repo}

      {:ok, nil} ->
        {:error, :repo_not_found}

      {:error, reason} ->
        if ash_not_found?(reason) do
          {:error, :repo_not_found}
        else
          {:error, {:repo_lookup_failed, reason}}
        end
    end
  end

  @spec normalize_action(map()) :: String.t() | nil
  defp normalize_action(payload) when is_map(payload) do
    case Map.get(payload, "action") || Map.get(payload, :action) do
      action when is_binary(action) ->
        case String.trim(action) do
          "" -> nil
          normalized_action -> normalized_action
        end

      _other ->
        nil
    end
  end

  @spec normalize_payload(term()) :: {:ok, map()} | {:error, :missing_payload}
  defp normalize_payload(payload) when is_map(payload), do: {:ok, payload}
  defp normalize_payload(_payload), do: {:error, :missing_payload}

  @spec normalize_required_string(term(), term()) :: {:ok, String.t()} | {:error, term()}
  defp normalize_required_string(value, error_reason) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, error_reason}
      normalized_value -> {:ok, normalized_value}
    end
  end

  defp normalize_required_string(_value, error_reason), do: {:error, error_reason}

  @spec log_duplicate_delivery_ack(String.t(), String.t() | nil) :: :ok
  defp log_duplicate_delivery_ack(delivery_id, event) do
    Logger.info(
      "github_webhook_delivery_persisted outcome=duplicate_acknowledged delivery_id=#{delivery_id} event=#{log_value(event)}"
    )

    :ok
  end

  @spec ash_not_found?(term()) :: boolean()
  defp ash_not_found?(%Ash.Error.Query.NotFound{}), do: true

  defp ash_not_found?(%Ash.Error.Invalid{errors: errors}) when is_list(errors) do
    Enum.any?(errors, &ash_not_found?/1)
  end

  defp ash_not_found?(%{errors: errors}) when is_list(errors) do
    Enum.any?(errors, &ash_not_found?/1)
  end

  defp ash_not_found?(_reason), do: false

  defp maybe_sync_installation_metadata(delivery) do
    case GitHubInstallationSync.sync_verified_delivery(delivery) do
      :ignored ->
        :ok

      {:ok, summary} ->
        Logger.info(
          "github_installation_sync outcome=updated event=#{log_value(Map.get(summary, :event))} action=#{log_value(Map.get(summary, :action))} installation_id=#{log_integer_value(Map.get(summary, :installation_id))} affected_repositories=#{log_repositories(GitHubInstallationSync.repository_names(summary))}"
        )

        :ok

      {:error, summary} ->
        Logger.warning(
          "github_installation_sync outcome=stale event=#{log_value(Map.get(summary, :event))} action=#{log_value(Map.get(summary, :action))} installation_id=#{log_integer_value(Map.get(summary, :installation_id))} error_type=#{log_value(Map.get(summary, :error_type))} affected_repositories=#{log_repositories(GitHubInstallationSync.repository_names(summary))}"
        )

        :ok
    end
  end

  defp dispatch_verified_delivery(delivery) do
    dispatcher =
      Application.get_env(
        :jido_code,
        :github_webhook_verified_dispatcher,
        &__MODULE__.default_dispatcher/1
      )

    case safe_dispatch(dispatcher, delivery) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error(
          "github_webhook_pipeline_dispatch_failed reason=#{inspect(reason)} delivery_id=#{log_value(Map.get(delivery, :delivery_id))} event=#{log_value(Map.get(delivery, :event))}"
        )

        {:error, :verified_dispatch_failed}
    end
  end

  defp safe_dispatch(dispatcher, delivery) when is_function(dispatcher, 1) do
    try do
      case dispatcher.(delivery) do
        :ok -> :ok
        {:ok, _result} -> :ok
        {:error, reason} -> {:error, reason}
        other -> {:error, {:unexpected_dispatch_result, other}}
      end
    rescue
      exception ->
        {:error, {:dispatch_exception, Exception.message(exception)}}
    catch
      kind, reason ->
        {:error, {:dispatch_throw, {kind, reason}}}
    end
  end

  defp safe_dispatch(_dispatcher, _delivery), do: {:error, :invalid_dispatcher}

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(map, atom_key, string_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default

  defp log_value(value) when is_binary(value) and value != "", do: value
  defp log_value(_value), do: "unknown"

  defp log_integer_value(value) when is_integer(value) and value > 0, do: Integer.to_string(value)
  defp log_integer_value(_value), do: "unknown"

  defp log_repositories([]), do: "none"
  defp log_repositories(repositories) when is_list(repositories), do: Enum.join(repositories, ",")

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
end
