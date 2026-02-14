defmodule JidoCode.Orchestration.WorkflowRun do
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Orchestration,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @statuses [:pending, :running, :awaiting_approval, :completed, :failed, :cancelled]
  @terminal_statuses [:completed, :failed, :cancelled]
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
        :started_at
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

    status_transitions =
      changeset
      |> Ash.Changeset.get_data(:status_transitions)
      |> normalize_status_transitions()
      |> Kernel.++([transition_entry(from_status, to_status, current_step, transitioned_at)])

    changeset
    |> Ash.Changeset.force_change_attribute(:status, to_status)
    |> Ash.Changeset.force_change_attribute(:current_step, current_step)
    |> Ash.Changeset.force_change_attribute(:status_transitions, status_transitions)
    |> maybe_set_started_at(to_status, transitioned_at)
    |> maybe_set_completed_at(to_status, transitioned_at)
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

  defp allowed_transition?(from_status, to_status) when is_atom(from_status) and is_atom(to_status),
    do: @allowed_transitions |> Map.get(from_status, MapSet.new()) |> MapSet.member?(to_status)

  defp allowed_transition?(_from_status, _to_status), do: false

  defp transition_entry(from_status, to_status, current_step, transitioned_at) do
    %{
      "from_status" => stringify_status(from_status),
      "to_status" => stringify_status(to_status),
      "current_step" => normalize_current_step(current_step),
      "transitioned_at" => DateTime.to_iso8601(transitioned_at)
    }
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

  defp stringify_status(nil), do: nil
  defp stringify_status(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_status(value) when is_binary(value), do: value
  defp stringify_status(_value), do: nil
end
