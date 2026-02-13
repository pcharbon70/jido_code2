defmodule JidoCode.Projects.ProjectSecret do
  @moduledoc false
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Projects,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "project_secrets"
    repo JidoCode.Repo
  end

  code_interface do
    define :create
    define :read
    define :update
    define :destroy
    define :get_by_project_and_key, action: :read, get_by: [:project_id, :key]
    define :list_for_project, action: :list_for_project
    define :mark_configured
    define :mark_missing
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:project_id, :key, :env_var_name, :configured, :inject_to_env]
    end

    update :update do
      primary? true
      accept [:env_var_name, :configured, :inject_to_env]
    end

    update :mark_configured do
      change set_attribute(:configured, true)
    end

    update :mark_missing do
      change set_attribute(:configured, false)
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

    attribute :key, :string do
      allow_nil? false
      public? true
    end

    attribute :env_var_name, :string do
      public? true
    end

    attribute :configured, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :inject_to_env, :boolean do
      allow_nil? false
      default true
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
    identity :unique_project_secret_key, [:project_id, :key]
  end
end
