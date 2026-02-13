defmodule JidoCode.Orchestration.PullRequest do
  @moduledoc false
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Orchestration,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "pull_requests"
    repo JidoCode.Repo
  end

  code_interface do
    define :create
    define :read
    define :update
    define :destroy
    define :get_by_project_and_pr_number, action: :read, get_by: [:project_id, :github_pr_number]
    define :list_open, action: :list_open
    define :mark_merged
    define :mark_closed
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :project_id,
        :workflow_run_id,
        :github_pr_number,
        :github_pr_url,
        :branch_name,
        :title,
        :body,
        :status,
        :created_at,
        :merged_at
      ]
    end

    update :update do
      primary? true
      accept [:title, :body, :status, :merged_at]
    end

    update :mark_merged do
      change set_attribute(:status, :merged)
      change set_attribute(:merged_at, &DateTime.utc_now/0)
    end

    update :mark_closed do
      change set_attribute(:status, :closed)
    end

    read :list_open do
      filter expr(status == :open)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :github_pr_number, :integer do
      allow_nil? false
      public? true
    end

    attribute :github_pr_url, :string do
      allow_nil? false
      public? true
    end

    attribute :branch_name, :string do
      allow_nil? false
      public? true
    end

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :body, :string do
      public? true
    end

    attribute :status, :atom do
      constraints one_of: [:open, :merged, :closed]
      allow_nil? false
      default :open
      public? true
    end

    attribute :created_at, :utc_datetime_usec do
      public? true
    end

    attribute :merged_at, :utc_datetime_usec do
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

    belongs_to :workflow_run, JidoCode.Orchestration.WorkflowRun do
      public? true
    end
  end

  identities do
    identity :unique_project_pr_number, [:project_id, :github_pr_number]
  end
end
