defmodule JidoCode.Projects.Project do
  @moduledoc false
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Projects,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "projects"
    repo JidoCode.Repo
  end

  code_interface do
    define :create
    define :read
    define :update
    define :destroy
    define :get_by_full_name, action: :read, get_by: [:github_full_name]
    define :list_ready, action: :list_ready
    define :list_by_environment, action: :list_by_environment
    define :set_clone_status
    define :mark_synced
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :name,
        :github_owner,
        :github_repo,
        :default_branch,
        :environment_type,
        :local_path,
        :sprite_spec,
        :clone_status,
        :last_synced_at,
        :settings
      ]

      change fn changeset, _ctx ->
        owner = Ash.Changeset.get_attribute(changeset, :github_owner)
        repo = Ash.Changeset.get_attribute(changeset, :github_repo)

        if owner && repo do
          Ash.Changeset.force_change_attribute(changeset, :github_full_name, "#{owner}/#{repo}")
        else
          changeset
        end
      end
    end

    update :update do
      primary? true

      accept [
        :name,
        :default_branch,
        :environment_type,
        :local_path,
        :sprite_spec,
        :clone_status,
        :last_synced_at,
        :settings
      ]
    end

    update :set_clone_status do
      require_atomic? false

      accept [:local_path]

      argument :clone_status, :atom do
        allow_nil? false
        constraints one_of: [:pending, :cloning, :ready, :error]
      end

      change fn changeset, _context ->
        status = Ash.Changeset.get_argument(changeset, :clone_status)
        Ash.Changeset.force_change_attribute(changeset, :clone_status, status)
      end
    end

    update :mark_synced do
      change set_attribute(:last_synced_at, &DateTime.utc_now/0)
    end

    read :list_ready do
      filter expr(clone_status == :ready)
    end

    read :list_by_environment do
      argument :environment_type, :atom do
        allow_nil? false
        constraints one_of: [:local, :sprite]
      end

      filter expr(environment_type == ^arg(:environment_type))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :github_owner, :string do
      allow_nil? false
      public? true
    end

    attribute :github_repo, :string do
      allow_nil? false
      public? true
    end

    attribute :github_full_name, :string do
      allow_nil? false
      public? true
    end

    attribute :default_branch, :string do
      allow_nil? false
      default "main"
      public? true
    end

    attribute :environment_type, :atom do
      constraints one_of: [:local, :sprite]
      allow_nil? false
      default :local
      public? true
    end

    attribute :local_path, :string do
      public? true
    end

    attribute :sprite_spec, :map do
      public? true
    end

    attribute :clone_status, :atom do
      constraints one_of: [:pending, :cloning, :ready, :error]
      allow_nil? false
      default :pending
      public? true
    end

    attribute :last_synced_at, :utc_datetime_usec do
      public? true
    end

    attribute :settings, :map do
      default %{}
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :project_secrets, JidoCode.Projects.ProjectSecret do
      destination_attribute :project_id
    end

    has_many :workflow_runs, JidoCode.Orchestration.WorkflowRun do
      destination_attribute :project_id
    end

    has_many :support_agent_configs, JidoCode.Agents.SupportAgentConfig do
      destination_attribute :project_id
    end

    has_many :pull_requests, JidoCode.Orchestration.PullRequest do
      destination_attribute :project_id
    end
  end

  identities do
    identity :unique_github_full_name, [:github_full_name]
  end
end
