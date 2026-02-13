defmodule JidoCode.Agents.SupportAgentConfig do
  @moduledoc false
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Agents,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "support_agent_configs"
    repo JidoCode.Repo
  end

  code_interface do
    define :create
    define :read
    define :update
    define :destroy
    define :get_by_project_and_agent_type, action: :read, get_by: [:project_id, :agent_type]
    define :list_for_project, action: :list_for_project
    define :enable
    define :disable
    define :touch_triggered
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:project_id, :agent_type, :enabled, :configuration, :webhook_events, :last_triggered_at]
    end

    update :update do
      primary? true
      accept [:enabled, :configuration, :webhook_events, :last_triggered_at]
    end

    update :enable do
      change set_attribute(:enabled, true)
    end

    update :disable do
      change set_attribute(:enabled, false)
    end

    update :touch_triggered do
      change set_attribute(:last_triggered_at, &DateTime.utc_now/0)
    end

    read :list_for_project do
      argument :project_id, :uuid do
        allow_nil? false
      end

      filter expr(project_id == ^arg(:project_id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :agent_type, :atom do
      constraints one_of: [:github_issue_bot, :pr_review_bot, :dependency_bot]
      allow_nil? false
      public? true
    end

    attribute :enabled, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :configuration, :map do
      default %{}
      public? true
    end

    attribute :webhook_events, {:array, :atom} do
      default []
      public? true
    end

    attribute :last_triggered_at, :utc_datetime_usec do
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
  end

  identities do
    identity :unique_project_agent_type, [:project_id, :agent_type]
  end
end
