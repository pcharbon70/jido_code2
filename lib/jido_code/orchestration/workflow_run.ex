defmodule JidoCode.Orchestration.WorkflowRun do
  @moduledoc false
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Orchestration,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "workflow_runs"
    repo JidoCode.Repo
  end

  code_interface do
    define :create
    define :read
    define :update
    define :destroy
    define :list_for_project, action: :list_for_project
    define :list_running, action: :list_running
    define :start
    define :await_approval
    define :complete
    define :fail
    define :cancel
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :project_id,
        :workflow_definition_id,
        :status,
        :trigger,
        :trigger_metadata,
        :inputs,
        :current_step,
        :step_results,
        :error,
        :started_at,
        :completed_at,
        :total_cost_usd
      ]
    end

    update :update do
      primary? true
      accept [:current_step, :step_results, :error, :total_cost_usd]
    end

    update :start do
      change set_attribute(:status, :running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
      change set_attribute(:error, nil)
    end

    update :await_approval do
      change set_attribute(:status, :awaiting_approval)
    end

    update :complete do
      accept [:step_results, :total_cost_usd]
      change set_attribute(:status, :completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :fail do
      accept [:error, :step_results, :total_cost_usd]
      change set_attribute(:status, :failed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :cancel do
      change set_attribute(:status, :cancelled)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    read :list_for_project do
      argument :project_id, :uuid do
        allow_nil? false
      end

      filter expr(project_id == ^arg(:project_id))
    end

    read :list_running do
      filter expr(status in [:pending, :running, :awaiting_approval])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :status, :atom do
      constraints one_of: [:pending, :running, :awaiting_approval, :completed, :failed, :cancelled]
      allow_nil? false
      default :pending
      public? true
    end

    attribute :trigger, :atom do
      constraints one_of: [:manual, :webhook, :schedule, :support_agent]
      allow_nil? false
      default :manual
      public? true
    end

    attribute :trigger_metadata, :map do
      default %{}
      public? true
    end

    attribute :inputs, :map do
      default %{}
      public? true
    end

    attribute :current_step, :string do
      public? true
    end

    attribute :step_results, :map do
      default %{}
      public? true
    end

    attribute :error, :string do
      public? true
    end

    attribute :started_at, :utc_datetime_usec do
      public? true
    end

    attribute :completed_at, :utc_datetime_usec do
      public? true
    end

    attribute :total_cost_usd, :decimal do
      default Decimal.new("0")
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, JidoCode.Projects.Project do
      allow_nil? false
      public? true
    end

    belongs_to :workflow_definition, JidoCode.Orchestration.WorkflowDefinition do
      allow_nil? false
      public? true
    end

    has_many :artifacts, JidoCode.Orchestration.Artifact do
      destination_attribute :workflow_run_id
    end

    has_one :pull_request, JidoCode.Orchestration.PullRequest do
      destination_attribute :workflow_run_id
    end
  end
end
