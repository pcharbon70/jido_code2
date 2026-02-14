defmodule JidoCode.Orchestration.WorkflowRun do
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Orchestration,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias JidoCode.Orchestration.RunPubSub

  @statuses [:pending, :running, :awaiting_approval, :completed, :failed, :cancelled]
  @terminal_statuses [:completed, :failed, :cancelled]
  @approval_action_error_type "workflow_run_approval_action_failed"
  @retry_action_error_type "workflow_run_retry_action_failed"
  @approval_action_operation "approve_run"
  @rejection_action_operation "reject_run"
  @retry_action_operation "retry_run"
  @approval_resume_step "resume_execution"
  @full_run_retry_policy "full_run"
  @retry_initial_step "queued"
  @retryable_terminal_statuses [:failed, :cancelled]
  @rejection_policy_default "cancel"
  @allowed_transitions %{
    pending: MapSet.new([:running, :cancelled]),
    running: MapSet.new([:awaiting_approval, :completed, :failed, :cancelled]),
    awaiting_approval: MapSet.new([:running, :cancelled]),
    completed: MapSet.new(),
    failed: MapSet.new(),
    cancelled: MapSet.new()
  }

  postgres do
    table "workflow_runs"
    repo JidoCode.Repo
  end

  code_interface do
    define :create
    define :read
    define :get_by_project_and_run_id, action: :by_project_and_run_id
    define :transition_status
  end

  actions do
    defaults [:destroy]

    create :create do
      primary? true

      accept [
        :run_id,
        :project_id,
        :workflow_name,
        :workflow_version,
        :trigger,
        :inputs,
        :input_metadata,
        :initiating_actor,
        :current_step,
        :step_results,
        :error,
        :started_at,
        :retry_of_run_id,
        :retry_attempt,
        :retry_lineage
      ]

      change set_attribute(:status, :pending)

      change fn changeset, _context ->
        started_at =
          changeset
          |> Ash.Changeset.get_attribute(:started_at)
          |> normalize_datetime()

        current_step =
          changeset
          |> Ash.Changeset.get_attribute(:current_step)
          |> normalize_current_step()

        changeset
        |> Ash.Changeset.force_change_attribute(:started_at, started_at)
        |> Ash.Changeset.force_change_attribute(:current_step, current_step)
        |> Ash.Changeset.force_change_attribute(
          :status_transitions,
          [transition_entry(nil, :pending, current_step, started_at)]
        )
        |> publish_run_started_event(started_at, current_step)
      end
    end

    read :read do
      primary? true
    end

    read :by_project_and_run_id do
      argument :project_id, :uuid, allow_nil?: false
      argument :run_id, :string, allow_nil?: false
      get? true
      filter expr(project_id == ^arg(:project_id) and run_id == ^arg(:run_id))
    end

    update :transition_status do
      require_atomic? false

      argument :to_status, :atom do
        allow_nil? false
        constraints one_of: @statuses
      end

      argument :current_step, :string do
        allow_nil? true
      end

      argument :transitioned_at, :utc_datetime_usec do
        allow_nil? true
      end

      argument :transition_metadata, :map do
        allow_nil? true
      end

      change fn changeset, _context ->
        from_status = Ash.Changeset.get_data(changeset, :status)
        to_status = Ash.Changeset.get_argument(changeset, :to_status)

        if allowed_transition?(from_status, to_status) do
          apply_transition(changeset, from_status, to_status)
        else
          Ash.Changeset.add_error(
            changeset,
            field: :status,
            message: "invalid lifecycle transition from #{from_status} to #{to_status}",
            vars: [from_status: from_status, to_status: to_status]
          )
        end
      end
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if always()
    end

    policy action_type(:update) do
      authorize_if always()
    end

    policy action_type(:destroy) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :run_id, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :workflow_name, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :workflow_version, :integer do
      allow_nil? false
      constraints min: 1
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :pending
      constraints one_of: @statuses
      public? true
    end

    attribute :trigger, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :inputs, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :input_metadata, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :initiating_actor, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :current_step, :string do
      allow_nil? false
      default "unknown"
      public? true
    end

    attribute :status_transitions, {:array, :map} do
      allow_nil? false
      default []
      public? true
    end

    attribute :step_results, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :error, :map do
      allow_nil? true
      public? true
    end

    attribute :retry_of_run_id, :string do
      allow_nil? true
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :retry_attempt, :integer do
      allow_nil? false
      default 1
      constraints min: 1
      public? true
    end

    attribute :retry_lineage, {:array, :map} do
      allow_nil? false
      default []
      public? true
    end

    attribute :started_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :completed_at, :utc_datetime_usec do
      allow_nil? true
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, JidoCode.Projects.Project do
      allow_nil? false
      public? true
      attribute_type :uuid
    end
  end

  identities do
    identity :unique_run_per_project, [:project_id, :run_id]
  end

  @spec approve(t(), map() | nil) :: {:ok, t()} | {:error, map()}
  def approve(run, params \\ nil)

  def approve(run, params) when is_struct(run, __MODULE__) do
    params = if(is_map(params), do: params, else: %{})
    persisted_run = reload_run(run)
    approved_at = params |> map_get(:approved_at, "approved_at") |> normalize_datetime()
    actor = params |> map_get(:actor, "actor", %{}) |> normalize_actor()
    current_step = approval_resume_step(params, persisted_run)

    with :ok <- validate_approval_preconditions(persisted_run),
         transition_metadata <- %{"approval_decision" => approval_decision(actor, approved_at)},
         {:ok, approved_run} <-
           transition_status(persisted_run, %{
             to_status: :running,
             current_step: current_step,
             transitioned_at: approved_at,
             transition_metadata: transition_metadata
           }) do
      {:ok, approved_run}
    else
      {:error, typed_failure} when is_map(typed_failure) ->
        {:error, typed_failure}

      {:error, reason} ->
        {:error,
         approval_action_failure(
           "status_transition_failed",
           "Approve action could not be applied while run remained blocked.",
           "Retry approval from run detail after resolving the blocking condition.",
           reason
         )}
    end
  end

  def approve(_run, _params) do
    {:error,
     approval_action_failure(
       "invalid_run",
       "Run reference is invalid and cannot be approved.",
       "Reload run detail and retry approval."
     )}
  end

  @spec reject(t(), map() | nil) :: {:ok, t()} | {:error, map()}
  def reject(run, params \\ nil)

  def reject(run, params) when is_struct(run, __MODULE__) do
    params = if(is_map(params), do: params, else: %{})
    persisted_run = reload_run(run)
    rejected_at = params |> map_get(:rejected_at, "rejected_at") |> normalize_datetime()
    actor = params |> map_get(:actor, "actor", %{}) |> normalize_actor()
    rationale = params |> map_get(:rationale, "rationale") |> normalize_optional_string()

    with :ok <- validate_rejection_preconditions(persisted_run),
         {:ok, transition_target} <- rejection_transition_target(persisted_run),
         transition_metadata <- %{
           "approval_decision" => rejection_decision(actor, rejected_at, rationale, transition_target)
         },
         {:ok, rejected_run} <-
           transition_status(persisted_run, %{
             to_status: transition_target.to_status,
             current_step: transition_target.current_step,
             transitioned_at: rejected_at,
             transition_metadata: transition_metadata
           }) do
      {:ok, rejected_run}
    else
      {:error, typed_failure} when is_map(typed_failure) ->
        {:error, typed_failure}

      {:error, reason} ->
        {:error,
         rejection_action_failure(
           "status_transition_failed",
           "Reject action could not be applied while run remained blocked.",
           "Retry rejection from run detail after resolving the blocking condition.",
           reason
         )}
    end
  end

  def reject(_run, _params) do
    {:error,
     rejection_action_failure(
       "invalid_run",
       "Run reference is invalid and cannot be rejected.",
       "Reload run detail and retry rejection."
     )}
  end

  @spec retry(t(), map() | nil) :: {:ok, t()} | {:error, map()}
  def retry(run, params \\ nil)

  def retry(run, params) when is_struct(run, __MODULE__) do
    params = if(is_map(params), do: params, else: %{})
    persisted_run = reload_run(run)
    retry_started_at = params |> map_get(:retry_started_at, "retry_started_at") |> normalize_datetime()
    actor = params |> map_get(:actor, "actor", %{}) |> normalize_actor()

    with :ok <- validate_retry_preconditions(persisted_run),
         {:ok, retry_policy} <- validate_full_run_retry_policy(persisted_run),
         next_retry_attempt <- next_retry_attempt(persisted_run),
         next_retry_run_id <- next_retry_run_id(persisted_run, next_retry_attempt),
         retry_lineage <- build_retry_lineage(persisted_run, actor, retry_started_at),
         retry_trigger <-
           build_retry_trigger(
             persisted_run,
             retry_policy,
             actor,
             retry_started_at,
             next_retry_attempt
           ),
         {:ok, retried_run} <-
           create(%{
             run_id: next_retry_run_id,
             project_id: Map.get(persisted_run, :project_id),
             workflow_name: Map.get(persisted_run, :workflow_name),
             workflow_version: Map.get(persisted_run, :workflow_version),
             trigger: retry_trigger,
             inputs: persisted_run |> Map.get(:inputs, %{}) |> normalize_map(),
             input_metadata: persisted_run |> Map.get(:input_metadata, %{}) |> normalize_map(),
             initiating_actor: retry_initiating_actor(persisted_run, actor),
             current_step: retry_initial_step(),
             step_results: retry_context_step_results(persisted_run, next_retry_attempt),
             started_at: retry_started_at,
             retry_of_run_id: Map.get(persisted_run, :run_id),
             retry_attempt: next_retry_attempt,
             retry_lineage: retry_lineage
           }) do
      {:ok, retried_run}
    else
      {:error, typed_failure} when is_map(typed_failure) ->
        {:error, typed_failure}

      {:error, reason} ->
        {:error,
         retry_action_failure(
           "run_creation_failed",
           "Full-run retry could not start a new run attempt.",
           "Retry from run detail after resolving run creation preconditions.",
           reason
         )}
    end
  end

  def retry(_run, _params) do
    {:error,
     retry_action_failure(
       "invalid_run",
       "Run reference is invalid and cannot be retried.",
       "Reload run detail and retry once the failed run is available."
     )}
  end

  defp apply_transition(changeset, from_status, to_status) do
    transitioned_at =
      changeset
      |> Ash.Changeset.get_argument(:transitioned_at)
      |> normalize_datetime()

    current_step =
      changeset
      |> Ash.Changeset.get_argument(:current_step)
      |> normalize_current_step(
        changeset
        |> Ash.Changeset.get_data(:current_step)
        |> normalize_current_step()
      )

    transition_metadata =
      changeset
      |> Ash.Changeset.get_argument(:transition_metadata)
      |> normalize_map()

    status_transitions =
      changeset
      |> Ash.Changeset.get_data(:status_transitions)
      |> normalize_status_transitions()
      |> Kernel.++([transition_entry(from_status, to_status, current_step, transitioned_at, transition_metadata)])

    changeset
    |> Ash.Changeset.force_change_attribute(:status, to_status)
    |> Ash.Changeset.force_change_attribute(:current_step, current_step)
    |> Ash.Changeset.force_change_attribute(:status_transitions, status_transitions)
    |> maybe_capture_approval_context(to_status)
    |> maybe_capture_transition_audit(from_status, to_status, transition_metadata)
    |> maybe_set_started_at(to_status, transitioned_at)
    |> maybe_set_completed_at(to_status, transitioned_at)
    |> publish_transition_events(from_status, to_status, current_step, transitioned_at, transition_metadata)
  end

  defp maybe_set_started_at(changeset, :running, transitioned_at) do
    case Ash.Changeset.get_data(changeset, :started_at) do
      %DateTime{} ->
        changeset

      _other ->
        Ash.Changeset.force_change_attribute(changeset, :started_at, transitioned_at)
    end
  end

  defp maybe_set_started_at(changeset, _to_status, _transitioned_at), do: changeset

  defp maybe_set_completed_at(changeset, to_status, transitioned_at) when to_status in @terminal_statuses do
    Ash.Changeset.force_change_attribute(changeset, :completed_at, transitioned_at)
  end

  defp maybe_set_completed_at(changeset, _to_status, _transitioned_at) do
    Ash.Changeset.force_change_attribute(changeset, :completed_at, nil)
  end

  defp publish_run_started_event(changeset, timestamp, current_step) do
    correlation_id = Ecto.UUID.generate()

    publish_required_events(changeset, ["run_started"], fn event_name ->
      build_event_payload(
        changeset,
        event_name,
        nil,
        :pending,
        current_step,
        timestamp,
        correlation_id
      )
    end)
  end

  defp publish_transition_events(
         changeset,
         from_status,
         to_status,
         current_step,
         transitioned_at,
         transition_metadata
       ) do
    correlation_id = Ecto.UUID.generate()
    events = required_transition_events(from_status, to_status, transition_metadata)

    publish_required_events(changeset, events, fn event_name ->
      build_event_payload(
        changeset,
        event_name,
        from_status,
        to_status,
        current_step,
        transitioned_at,
        correlation_id
      )
    end)
  end

  defp publish_required_events(changeset, events, payload_builder) when is_list(events) do
    diagnostics =
      Enum.reduce(events, [], fn event_name, acc ->
        payload = payload_builder.(event_name)

        case RunPubSub.broadcast_run_event(payload["run_id"], payload) do
          :ok ->
            acc

          {:error, typed_diagnostic} ->
            [typed_diagnostic | acc]
        end
      end)
      |> Enum.reverse()

    case diagnostics do
      [] -> changeset
      _diagnostics -> capture_event_channel_diagnostics(changeset, diagnostics)
    end
  end

  defp required_transition_events(from_status, to_status, transition_metadata) do
    case {from_status, to_status, transition_approval_decision(transition_metadata)} do
      {:awaiting_approval, :running, "rejected"} -> ["approval_rejected", "step_started"]
      {:awaiting_approval, :running, _decision} -> ["approval_granted", "step_started"]
      {_from, :running, _decision} -> ["step_started"]
      {_from, :awaiting_approval, _decision} -> ["approval_requested"]
      {:awaiting_approval, :cancelled, _decision} -> ["approval_rejected", "run_cancelled"]
      {_from, :completed, _decision} -> ["step_completed", "run_completed"]
      {_from, :failed, _decision} -> ["step_failed", "run_failed"]
      {_from, :cancelled, _decision} -> ["run_cancelled"]
      _other -> []
    end
  end

  defp transition_approval_decision(transition_metadata) do
    transition_metadata
    |> normalize_map()
    |> map_get(:approval_decision, "approval_decision", %{})
    |> map_get(:decision, "decision")
    |> normalize_optional_string()
  end

  defp build_event_payload(
         changeset,
         event_name,
         from_status,
         to_status,
         current_step,
         timestamp,
         correlation_id
       ) do
    %{
      "event" => event_name,
      "run_id" => changeset_attribute(changeset, :run_id),
      "workflow_name" => changeset_attribute(changeset, :workflow_name),
      "workflow_version" => normalize_workflow_version(changeset_attribute(changeset, :workflow_version)),
      "timestamp" => timestamp |> normalize_datetime() |> DateTime.to_iso8601(),
      "correlation_id" => correlation_id,
      "from_status" => stringify_status(from_status),
      "to_status" => stringify_status(to_status),
      "current_step" => normalize_current_step(current_step)
    }
  end

  defp capture_event_channel_diagnostics(changeset, diagnostics) do
    existing_error =
      changeset
      |> changeset_attribute(:error)
      |> normalize_error_map()

    existing_diagnostics =
      existing_error
      |> Map.get("event_channel_diagnostics", [])
      |> normalize_diagnostics()

    Ash.Changeset.force_change_attribute(
      changeset,
      :error,
      Map.put(existing_error, "event_channel_diagnostics", existing_diagnostics ++ diagnostics)
    )
  end

  defp maybe_capture_approval_context(changeset, :awaiting_approval) do
    step_results =
      changeset
      |> Ash.Changeset.get_data(:step_results)
      |> normalize_step_results()

    case build_approval_context(step_results) do
      {:ok, approval_context} ->
        changeset
        |> Ash.Changeset.force_change_attribute(
          :step_results,
          Map.put(step_results, "approval_context", approval_context)
        )
        |> clear_approval_context_diagnostics()

      {:error, diagnostic} ->
        changeset
        |> Ash.Changeset.force_change_attribute(:step_results, Map.delete(step_results, "approval_context"))
        |> capture_approval_context_diagnostic(diagnostic)
    end
  end

  defp maybe_capture_approval_context(changeset, _to_status), do: changeset

  defp maybe_capture_transition_audit(
         changeset,
         :awaiting_approval,
         to_status,
         %{"approval_decision" => approval_decision}
       )
       when to_status in [:running, :cancelled] do
    normalized_approval_decision = normalize_map(approval_decision)

    if map_size(normalized_approval_decision) == 0 do
      changeset
    else
      step_results =
        changeset
        |> Ash.Changeset.get_data(:step_results)
        |> normalize_step_results()

      approval_decision_history =
        step_results
        |> map_get(:approval_decisions, "approval_decisions", [])
        |> normalize_map_list()

      Ash.Changeset.force_change_attribute(
        changeset,
        :step_results,
        step_results
        |> Map.put("approval_decision", normalized_approval_decision)
        |> Map.put("approval_decisions", approval_decision_history ++ [normalized_approval_decision])
      )
    end
  end

  defp maybe_capture_transition_audit(changeset, _from_status, _to_status, _transition_metadata),
    do: changeset

  defp build_approval_context(step_results) when is_map(step_results) do
    context_source =
      step_results
      |> map_get(:approval_context, "approval_context", %{})
      |> normalize_map()

    case approval_context_generation_error(step_results, context_source) do
      nil ->
        diff_summary =
          context_source
          |> map_get(:diff_summary, "diff_summary", map_get(step_results, :diff_summary, "diff_summary"))
          |> normalize_summary("Diff summary unavailable. Generate a git diff summary and retry.")

        test_summary =
          context_source
          |> map_get(:test_summary, "test_summary", map_get(step_results, :test_summary, "test_summary"))
          |> normalize_summary("Test summary unavailable. Capture test output and retry.")

        risk_notes =
          context_source
          |> map_get(:risk_notes, "risk_notes", map_get(step_results, :risk_notes, "risk_notes"))
          |> normalize_risk_notes([
            "No explicit risk notes were provided. Review the diff and test summary before approving."
          ])

        {:ok,
         %{
           "diff_summary" => diff_summary,
           "test_summary" => test_summary,
           "risk_notes" => risk_notes
         }}

      reason ->
        {:error, approval_context_generation_diagnostic(reason)}
    end
  end

  defp build_approval_context(_step_results) do
    {:error, approval_context_generation_diagnostic("Step results are unavailable for approval payload generation.")}
  end

  defp approval_context_generation_error(step_results, context_source) do
    step_results
    |> map_get(
      :approval_context_generation_error,
      "approval_context_generation_error",
      map_get(context_source, :generation_error, "generation_error")
    )
    |> normalize_optional_string()
  end

  defp approval_context_generation_diagnostic(reason) do
    %{
      "error_type" => "approval_context_generation_failed",
      "operation" => "build_approval_context",
      "reason_type" => "approval_payload_blocked",
      "message" => "Approval context generation failed and run remains blocked in awaiting_approval.",
      "detail" => reason,
      "remediation" =>
        "Publish diff summary, test summary, and risk notes from prior steps, then regenerate approval context.",
      "timestamp" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  defp capture_approval_context_diagnostic(changeset, diagnostic) do
    existing_error =
      changeset
      |> changeset_attribute(:error)
      |> normalize_error_map()

    existing_diagnostics =
      existing_error
      |> Map.get("approval_context_diagnostics", [])
      |> normalize_diagnostics()

    Ash.Changeset.force_change_attribute(
      changeset,
      :error,
      Map.put(existing_error, "approval_context_diagnostics", existing_diagnostics ++ [diagnostic])
    )
  end

  defp clear_approval_context_diagnostics(changeset) do
    existing_error =
      changeset
      |> changeset_attribute(:error)
      |> normalize_error_map()
      |> Map.delete("approval_context_diagnostics")

    case existing_error do
      map when map_size(map) == 0 ->
        Ash.Changeset.force_change_attribute(changeset, :error, nil)

      map ->
        Ash.Changeset.force_change_attribute(changeset, :error, map)
    end
  end

  defp changeset_attribute(changeset, attribute) when is_atom(attribute) do
    case Ash.Changeset.get_attribute(changeset, attribute) do
      nil ->
        changeset
        |> Ash.Changeset.get_data(attribute)
        |> normalize_changeset_attribute(attribute)

      value ->
        normalize_changeset_attribute(value, attribute)
    end
  end

  defp normalize_changeset_attribute(value, :run_id), do: normalize_string(value, "unknown")
  defp normalize_changeset_attribute(value, :workflow_name), do: normalize_string(value, "unknown")
  defp normalize_changeset_attribute(value, :error), do: normalize_error_map(value)
  defp normalize_changeset_attribute(value, _attribute), do: value

  defp normalize_workflow_version(value) when is_integer(value), do: value

  defp normalize_workflow_version(value) when is_binary(value) do
    case Integer.parse(value) do
      {version, ""} -> version
      _other -> 0
    end
  end

  defp normalize_workflow_version(_value), do: 0

  defp normalize_diagnostics(diagnostics) when is_list(diagnostics) do
    Enum.filter(diagnostics, &is_map/1)
  end

  defp normalize_diagnostics(_diagnostics), do: []

  defp normalize_map_list(list) when is_list(list) do
    list
    |> Enum.filter(&is_map/1)
    |> Enum.map(&normalize_map/1)
  end

  defp normalize_map_list(_list), do: []

  defp normalize_step_results(%{} = step_results), do: step_results
  defp normalize_step_results(_step_results), do: %{}

  defp normalize_map(%{} = map), do: map
  defp normalize_map(_value), do: %{}

  defp normalize_summary(value, fallback) do
    case normalize_optional_string(value) do
      nil -> fallback
      normalized_summary -> normalized_summary
    end
  end

  defp normalize_risk_notes(value, fallback) when is_list(value) do
    value
    |> Enum.map(&normalize_optional_string/1)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> fallback
      notes -> notes
    end
  end

  defp normalize_risk_notes(value, fallback) do
    value
    |> normalize_optional_string()
    |> case do
      nil -> fallback
      note -> [note]
    end
  end

  defp normalize_error_map(%{} = map), do: map
  defp normalize_error_map(_value), do: %{}

  defp normalize_string(value, _fallback) when is_binary(value) and value != "", do: value

  defp normalize_string(value, fallback) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_string(fallback)

  defp normalize_string(_value, fallback), do: fallback

  defp allowed_transition?(from_status, to_status) when is_atom(from_status) and is_atom(to_status),
    do: @allowed_transitions |> Map.get(from_status, MapSet.new()) |> MapSet.member?(to_status)

  defp allowed_transition?(_from_status, _to_status), do: false

  defp transition_entry(from_status, to_status, current_step, transitioned_at, transition_metadata \\ %{}) do
    base_entry = %{
      "from_status" => stringify_status(from_status),
      "to_status" => stringify_status(to_status),
      "current_step" => normalize_current_step(current_step),
      "transitioned_at" => DateTime.to_iso8601(transitioned_at)
    }

    normalized_transition_metadata = normalize_map(transition_metadata)

    if map_size(normalized_transition_metadata) == 0 do
      base_entry
    else
      Map.put(base_entry, "metadata", normalized_transition_metadata)
    end
  end

  defp normalize_status_transitions(status_transitions) when is_list(status_transitions), do: status_transitions
  defp normalize_status_transitions(_status_transitions), do: []

  defp normalize_current_step(current_step, fallback \\ "unknown")

  defp normalize_current_step(current_step, fallback) when is_binary(current_step) do
    case String.trim(current_step) do
      "" -> normalize_current_step(nil, fallback)
      normalized_step -> normalized_step
    end
  end

  defp normalize_current_step(_current_step, fallback) do
    normalized_fallback =
      fallback
      |> stringify_status()
      |> case do
        nil -> "unknown"
        value -> value
      end

    normalized_fallback
  end

  defp normalize_datetime(%DateTime{} = datetime), do: DateTime.truncate(datetime, :second)
  defp normalize_datetime(_datetime), do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp reload_run(run) when is_struct(run, __MODULE__) do
    run_id = run |> Map.get(:run_id) |> normalize_optional_string()

    project_id =
      run
      |> Map.get(:project_id)
      |> normalize_optional_string()

    case {project_id, run_id} do
      {nil, _run_id} ->
        run

      {_project_id, nil} ->
        run

      {resolved_project_id, resolved_run_id} ->
        case get_by_project_and_run_id(%{project_id: resolved_project_id, run_id: resolved_run_id}) do
          {:ok, persisted_run} when is_struct(persisted_run, __MODULE__) -> persisted_run
          _other -> run
        end
    end
  end

  defp validate_approval_preconditions(run) when is_struct(run, __MODULE__) do
    cond do
      not awaiting_approval_status?(Map.get(run, :status)) ->
        {:error,
         approval_action_failure(
           "invalid_run_status",
           "Approve action is only allowed when run status is awaiting_approval.",
           "Reload run detail and retry once run enters awaiting_approval."
         )}

      approval_context_blocked?(run) ->
        {:error,
         approval_action_failure(
           "approval_context_blocked",
           "Approve action is blocked because approval context generation failed.",
           "Regenerate diff summary, test summary, and risk notes before retrying approval."
         )}

      true ->
        :ok
    end
  end

  defp validate_approval_preconditions(_run) do
    {:error,
     approval_action_failure(
       "invalid_run",
       "Run reference is invalid and cannot be approved.",
       "Reload run detail and retry approval."
     )}
  end

  defp validate_rejection_preconditions(run) when is_struct(run, __MODULE__) do
    if awaiting_approval_status?(Map.get(run, :status)) do
      :ok
    else
      {:error,
       rejection_action_failure(
         "invalid_run_status",
         "Reject action is only allowed when run status is awaiting_approval.",
         "Reload run detail and retry once run enters awaiting_approval."
       )}
    end
  end

  defp validate_rejection_preconditions(_run) do
    {:error,
     rejection_action_failure(
       "invalid_run",
       "Run reference is invalid and cannot be rejected.",
       "Reload run detail and retry rejection."
     )}
  end

  defp validate_retry_preconditions(run) when is_struct(run, __MODULE__) do
    if retryable_terminal_status?(Map.get(run, :status)) do
      :ok
    else
      {:error,
       retry_action_failure(
         "invalid_run_status",
         "Full-run retry is only allowed when run status is failed or cancelled.",
         "Retry this action after the run reaches a terminal failure state."
       )}
    end
  end

  defp validate_retry_preconditions(_run) do
    {:error,
     retry_action_failure(
       "invalid_run",
       "Run reference is invalid and cannot be retried.",
       "Reload run detail and retry once the failed run is available."
     )}
  end

  defp validate_full_run_retry_policy(run) when is_struct(run, __MODULE__) do
    retry_policy =
      run
      |> Map.get(:trigger, %{})
      |> normalize_map()
      |> trigger_retry_policy()

    if full_run_retry_allowed?(retry_policy) do
      {:ok, retry_policy}
    else
      {:error, retry_policy_violation_failure(retry_policy)}
    end
  end

  defp validate_full_run_retry_policy(_run), do: {:ok, %{}}

  defp retry_policy_violation_failure(retry_policy) do
    retry_mode =
      retry_policy
      |> map_get(:mode, "mode")
      |> normalize_retry_mode()

    detail =
      case retry_mode do
        nil ->
          "Full-run retry is disallowed by workflow policy."

        mode ->
          "Full-run retry is disallowed by workflow policy mode #{inspect(mode)}."
      end

    retry_action_failure(
      "policy_violation",
      detail,
      "Update workflow retry policy to permit full-run retry, or start a fresh manual run."
    )
    |> Map.put(:policy, retry_policy)
  end

  defp retryable_terminal_status?(status) when is_atom(status), do: status in @retryable_terminal_statuses

  defp retryable_terminal_status?(status) when is_binary(status) do
    status
    |> String.trim()
    |> case do
      "failed" -> true
      "cancelled" -> true
      _other -> false
    end
  end

  defp retryable_terminal_status?(_status), do: false

  defp retry_initial_step, do: @retry_initial_step

  defp next_retry_attempt(run) when is_struct(run, __MODULE__) do
    run
    |> Map.get(:retry_attempt)
    |> normalize_optional_positive_integer()
    |> case do
      nil -> 2
      retry_attempt -> retry_attempt + 1
    end
  end

  defp next_retry_attempt(_run), do: 2

  defp next_retry_run_id(run, retry_attempt) when is_struct(run, __MODULE__) and is_integer(retry_attempt) do
    project_id =
      run
      |> Map.get(:project_id)
      |> normalize_optional_string()

    run_root_id =
      run
      |> retry_root_run_id()
      |> normalize_string("run")

    ensure_unique_retry_run_id(project_id, run_root_id, retry_attempt, 0)
  end

  defp next_retry_run_id(run, _retry_attempt) do
    run
    |> Map.get(:run_id)
    |> normalize_string("run")
    |> Kernel.<>("-retry-2")
  end

  defp ensure_unique_retry_run_id(_project_id, run_root_id, retry_attempt, suffix)
       when not is_integer(retry_attempt) do
    "#{run_root_id}-retry-#{suffix + 2}"
  end

  defp ensure_unique_retry_run_id(project_id, run_root_id, retry_attempt, suffix)
       when is_binary(project_id) and suffix < 100 do
    candidate_run_id =
      case suffix do
        0 -> "#{run_root_id}-retry-#{retry_attempt}"
        _other -> "#{run_root_id}-retry-#{retry_attempt}-#{suffix + 1}"
      end

    case get_by_project_and_run_id(%{project_id: project_id, run_id: candidate_run_id}) do
      {:ok, persisted_run} when is_struct(persisted_run, __MODULE__) ->
        ensure_unique_retry_run_id(project_id, run_root_id, retry_attempt, suffix + 1)

      _other ->
        candidate_run_id
    end
  end

  defp ensure_unique_retry_run_id(_project_id, run_root_id, retry_attempt, _suffix),
    do: "#{run_root_id}-retry-#{retry_attempt}"

  defp retry_root_run_id(run) when is_struct(run, __MODULE__) do
    run_id =
      run
      |> Map.get(:run_id)
      |> normalize_string("run")

    run
    |> Map.get(:retry_lineage, [])
    |> normalize_map_list()
    |> List.first()
    |> case do
      %{} = retry_root ->
        retry_root
        |> map_get(:run_id, "run_id")
        |> normalize_optional_string() || run_id

      _other ->
        run_id
    end
  end

  defp retry_root_run_id(_run), do: "run"

  defp build_retry_lineage(run, actor, retry_started_at) when is_struct(run, __MODULE__) do
    existing_lineage =
      run
      |> Map.get(:retry_lineage, [])
      |> normalize_map_list()

    existing_lineage ++ [retry_lineage_entry(run, actor, retry_started_at)]
  end

  defp build_retry_lineage(_run, _actor, _retry_started_at), do: []

  defp retry_lineage_entry(run, actor, retry_started_at) do
    %{
      "run_id" => run |> Map.get(:run_id) |> normalize_string("unknown"),
      "status" => run |> Map.get(:status) |> stringify_status() || "unknown",
      "retry_attempt" =>
        run
        |> Map.get(:retry_attempt)
        |> normalize_optional_positive_integer() || 1,
      "current_step" => run |> Map.get(:current_step) |> normalize_current_step(),
      "completed_at" => run |> Map.get(:completed_at) |> format_optional_datetime(),
      "failure_artifacts" => run |> Map.get(:step_results, %{}) |> normalize_step_results(),
      "typed_failure" => run |> Map.get(:error, %{}) |> normalize_error_map(),
      "retry_actor" => actor,
      "retried_at" => DateTime.to_iso8601(retry_started_at)
    }
  end

  defp build_retry_trigger(run, retry_policy, actor, retry_started_at, retry_attempt) do
    trigger =
      run
      |> Map.get(:trigger, %{})
      |> normalize_map()

    retry_metadata = %{
      "policy" => @full_run_retry_policy,
      "source_run_id" => run |> Map.get(:run_id) |> normalize_string("unknown"),
      "attempt" => retry_attempt,
      "actor" => actor,
      "timestamp" => DateTime.to_iso8601(retry_started_at)
    }

    trigger
    |> Map.put("retry", retry_metadata)
    |> maybe_put_retry_policy(retry_policy)
  end

  defp maybe_put_retry_policy(trigger, retry_policy) when is_map(retry_policy) do
    if map_size(retry_policy) == 0 do
      trigger
    else
      Map.put(trigger, "retry_policy", retry_policy)
    end
  end

  defp maybe_put_retry_policy(trigger, _retry_policy), do: trigger

  defp retry_initiating_actor(run, actor) when is_struct(run, __MODULE__) do
    if actor == %{"id" => "unknown", "email" => nil} do
      run
      |> Map.get(:initiating_actor, %{})
      |> normalize_map()
    else
      actor
    end
  end

  defp retry_initiating_actor(_run, actor), do: actor

  defp retry_context_step_results(run, retry_attempt) do
    %{
      "retry_context" => %{
        "policy" => @full_run_retry_policy,
        "retry_of_run_id" => run |> Map.get(:run_id) |> normalize_string("unknown"),
        "retry_attempt" => retry_attempt
      }
    }
  end

  defp awaiting_approval_status?(status) when is_atom(status), do: status == :awaiting_approval
  defp awaiting_approval_status?(status) when is_binary(status), do: String.trim(status) == "awaiting_approval"
  defp awaiting_approval_status?(_status), do: false

  defp approval_context_blocked?(run) when is_struct(run, __MODULE__) do
    step_results =
      run
      |> Map.get(:step_results, %{})
      |> normalize_step_results()

    approval_context =
      step_results
      |> map_get(:approval_context, "approval_context", %{})
      |> normalize_map()

    approval_context_diagnostics =
      run
      |> Map.get(:error, %{})
      |> normalize_error_map()
      |> Map.get("approval_context_diagnostics", [])
      |> normalize_diagnostics()

    map_size(approval_context) == 0 or approval_context_diagnostics != []
  end

  defp approval_context_blocked?(_run), do: true

  defp approval_resume_step(params, run) do
    params
    |> map_get(:current_step, "current_step", Map.get(run, :current_step))
    |> normalize_current_step(@approval_resume_step)
  end

  defp rejection_transition_target(run) do
    current_step =
      run
      |> Map.get(:current_step)
      |> normalize_current_step()

    case rejection_policy(run) do
      {:ok, :cancel} ->
        {:ok, %{to_status: :cancelled, current_step: current_step, outcome: "cancelled"}}

      {:ok, {:retry_route, retry_step}} ->
        {:ok, %{to_status: :running, current_step: retry_step, outcome: "retry_route"}}

      {:error, typed_failure} ->
        {:error, typed_failure}
    end
  end

  defp rejection_policy(run) when is_struct(run, __MODULE__) do
    on_reject =
      run
      |> Map.get(:trigger, %{})
      |> normalize_map()
      |> trigger_approval_policy()
      |> map_get(:on_reject, "on_reject", @rejection_policy_default)

    normalize_rejection_policy(on_reject)
  end

  defp rejection_policy(_run), do: {:ok, :cancel}

  defp trigger_approval_policy(trigger) when is_map(trigger) do
    case map_get(trigger, :approval_policy, "approval_policy") do
      %{} = direct_policy ->
        normalize_map(direct_policy)

      _other ->
        nested_policy =
          trigger
          |> map_get(:policy, "policy", %{})
          |> normalize_map()

        cond do
          is_map(map_get(nested_policy, :approval_policy, "approval_policy")) ->
            nested_policy
            |> map_get(:approval_policy, "approval_policy")
            |> normalize_map()

          is_map(map_get(nested_policy, :approval, "approval")) ->
            nested_policy
            |> map_get(:approval, "approval")
            |> normalize_map()

          true ->
            nested_policy
        end
    end
  end

  defp trigger_approval_policy(_trigger), do: %{}

  defp trigger_retry_policy(trigger) when is_map(trigger) do
    case map_get(trigger, :retry_policy, "retry_policy") do
      %{} = direct_policy ->
        normalize_map(direct_policy)

      _other ->
        nested_policy =
          trigger
          |> map_get(:policy, "policy", %{})
          |> normalize_map()

        cond do
          is_map(map_get(nested_policy, :retry_policy, "retry_policy")) ->
            nested_policy
            |> map_get(:retry_policy, "retry_policy")
            |> normalize_map()

          is_map(map_get(nested_policy, :retry, "retry")) ->
            nested_policy
            |> map_get(:retry, "retry")
            |> normalize_map()

          true ->
            %{}
        end
    end
  end

  defp trigger_retry_policy(_trigger), do: %{}

  defp full_run_retry_allowed?(retry_policy) when is_map(retry_policy) do
    retry_mode =
      retry_policy
      |> map_get(:mode, "mode")
      |> normalize_retry_mode()

    full_run_allowed =
      retry_policy
      |> map_get(:full_run, "full_run", map_get(retry_policy, :allow_full_run, "allow_full_run", true))
      |> normalize_boolean(true)

    cond do
      full_run_allowed == false ->
        false

      retry_mode in ["disabled", "disallow", "blocked", "step_only", "step_level_only"] ->
        false

      true ->
        true
    end
  end

  defp full_run_retry_allowed?(_retry_policy), do: true

  defp normalize_retry_mode(mode) do
    mode
    |> normalize_optional_string()
    |> case do
      nil -> nil
      normalized_mode -> String.downcase(normalized_mode)
    end
  end

  defp normalize_rejection_policy(on_reject) when is_map(on_reject) do
    case normalize_rejection_policy_action(map_get(on_reject, :action, "action")) do
      :cancel ->
        {:ok, :cancel}

      :retry_route ->
        case rejection_retry_step(on_reject) do
          nil ->
            {:error,
             rejection_action_failure(
               "policy_invalid",
               "Reject action policy configured a retry route but no retry step was provided.",
               "Update workflow rejection policy with a retry route step, then retry rejection."
             )}

          retry_step ->
            {:ok, {:retry_route, retry_step}}
        end

      :invalid ->
        {:error,
         rejection_action_failure(
           "policy_invalid",
           "Reject action policy is invalid and cannot determine a rejection route.",
           "Review workflow rejection policy settings, then retry rejection."
         )}
    end
  end

  defp normalize_rejection_policy(on_reject) do
    case normalize_rejection_policy_action(on_reject) do
      :cancel ->
        {:ok, :cancel}

      :retry_route ->
        {:error,
         rejection_action_failure(
           "policy_invalid",
           "Reject action policy selected retry routing but did not declare a retry step.",
           "Update workflow rejection policy with a retry route step, then retry rejection."
         )}

      :invalid ->
        {:error,
         rejection_action_failure(
           "policy_invalid",
           "Reject action policy is invalid and cannot determine a rejection route.",
           "Review workflow rejection policy settings, then retry rejection."
         )}
    end
  end

  defp normalize_rejection_policy_action(action) do
    case action |> normalize_optional_string() do
      nil -> :cancel
      "cancel" -> :cancel
      "retry_route" -> :retry_route
      "route_retry" -> :retry_route
      "route_to_retry" -> :retry_route
      "reroute" -> :retry_route
      "retry" -> :retry_route
      _other -> :invalid
    end
  end

  defp rejection_retry_step(on_reject) when is_map(on_reject) do
    on_reject
    |> map_get(
      :retry_step,
      "retry_step",
      map_get(
        on_reject,
        :route_step,
        "route_step",
        map_get(on_reject, :step, "step")
      )
    )
    |> normalize_optional_string()
    |> case do
      nil -> nil
      retry_step -> normalize_current_step(retry_step)
    end
  end

  defp rejection_retry_step(_on_reject), do: nil

  defp approval_decision(actor, approved_at) do
    %{
      "decision" => "approved",
      "actor" => actor,
      "timestamp" => DateTime.to_iso8601(approved_at)
    }
  end

  defp rejection_decision(actor, rejected_at, rationale, transition_target) do
    %{
      "decision" => "rejected",
      "actor" => actor,
      "timestamp" => DateTime.to_iso8601(rejected_at),
      "outcome" => Map.get(transition_target, :outcome)
    }
    |> maybe_put_optional_string("rationale", rationale)
    |> maybe_put_optional_string(
      "retry_step",
      if(Map.get(transition_target, :to_status) == :running,
        do: Map.get(transition_target, :current_step),
        else: nil
      )
    )
  end

  defp normalize_actor(actor) when is_map(actor) do
    %{
      "id" => actor |> map_get(:id, "id") |> normalize_optional_string() || "unknown",
      "email" => actor |> map_get(:email, "email") |> normalize_optional_string()
    }
  end

  defp normalize_actor(_actor), do: %{"id" => "unknown", "email" => nil}

  defp approval_action_failure(reason_type, detail, remediation, reason \\ nil) do
    action_failure(@approval_action_operation, reason_type, detail, remediation, reason)
  end

  defp rejection_action_failure(reason_type, detail, remediation, reason \\ nil) do
    action_failure(@rejection_action_operation, reason_type, detail, remediation, reason)
  end

  defp retry_action_failure(reason_type, detail, remediation, reason \\ nil) do
    action_failure(
      @retry_action_operation,
      reason_type,
      detail,
      remediation,
      reason,
      @retry_action_error_type
    )
  end

  defp action_failure(operation, reason_type, detail, remediation, reason) do
    action_failure(operation, reason_type, detail, remediation, reason, @approval_action_error_type)
  end

  defp action_failure(operation, reason_type, detail, remediation, reason, error_type) do
    %{
      error_type: error_type,
      operation: operation,
      reason_type: normalize_reason_type(reason_type),
      detail: format_failure_detail(detail, reason),
      remediation: remediation,
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  defp format_failure_detail(detail, nil), do: detail
  defp format_failure_detail(detail, ""), do: detail

  defp format_failure_detail(detail, reason) do
    "#{detail} (#{format_failure_reason(reason)})"
  end

  defp format_failure_reason(reason) when is_binary(reason), do: reason

  defp format_failure_reason(reason) do
    reason
    |> Exception.message()
    |> normalize_optional_string()
    |> case do
      nil -> inspect(reason)
      message -> message
    end
  rescue
    _exception -> inspect(reason)
  end

  defp normalize_reason_type(reason_type) do
    reason_type
    |> normalize_optional_string()
    |> case do
      nil -> "unknown"
      value -> String.replace(value, ~r/[^a-zA-Z0-9._-]/, "_")
    end
  end

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value) when is_boolean(value), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized_value -> normalized_value
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(value) when is_float(value), do: :erlang.float_to_binary(value)
  defp normalize_optional_string(_value), do: nil

  defp normalize_optional_positive_integer(value) when is_integer(value) and value > 0, do: value

  defp normalize_optional_positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> parsed
      _other -> nil
    end
  end

  defp normalize_optional_positive_integer(_value), do: nil

  defp format_optional_datetime(%DateTime{} = datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp format_optional_datetime(datetime) when is_binary(datetime) do
    case DateTime.from_iso8601(datetime) do
      {:ok, parsed_datetime, _offset} -> format_optional_datetime(parsed_datetime)
      _other -> nil
    end
  end

  defp format_optional_datetime(_datetime), do: nil

  defp normalize_boolean(value, _default) when is_boolean(value), do: value

  defp normalize_boolean(value, _default) when is_integer(value) do
    value != 0
  end

  defp normalize_boolean(value, default) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      "true" -> true
      "1" -> true
      "yes" -> true
      "on" -> true
      "false" -> false
      "0" -> false
      "no" -> false
      "off" -> false
      _other -> default
    end
  end

  defp normalize_boolean(_value, default), do: default

  defp maybe_put_optional_string(map, _key, nil), do: map

  defp maybe_put_optional_string(map, key, value) do
    Map.put(map, key, value)
  end

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(map, atom_key, string_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default

  defp stringify_status(nil), do: nil
  defp stringify_status(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_status(value) when is_binary(value), do: value
  defp stringify_status(_value), do: nil
end
