defmodule JidoCode.Repo.Migrations.AddSetupProjectsOrchestrationAndAgentsResources do
  use Ecto.Migration

  def up do
    create table(:system_configs, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :onboarding_completed, :boolean, null: false, default: false
      add :onboarding_step, :bigint, null: false, default: 0
      add :default_environment, :text, null: false, default: "local"
      add :local_workspace_root, :text, null: false, default: "~/.jido_code/workspaces"
      add :sprites_api_configured, :boolean, null: false, default: false
      timestamps(type: :utc_datetime_usec)
    end

    create table(:credentials, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :provider, :text, null: false
      add :name, :text, null: false
      add :env_var_name, :text, null: false
      add :metadata, :map, default: %{}
      add :verified_at, :utc_datetime_usec
      add :status, :text, null: false, default: "not_set"
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:credentials, [:provider, :env_var_name],
             name: "credentials_unique_provider_env_var_name_index"
           )

    create table(:github_app_installations, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :installation_id, :bigint, null: false
      add :account_login, :text, null: false
      add :account_type, :text, null: false
      add :cached_access_token, :text
      add :token_expires_at, :utc_datetime_usec
      add :permissions, :map, default: %{}
      add :repository_selection, :text, null: false, default: "all"
      add :selected_repos, {:array, :text}, default: []
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:github_app_installations, [:installation_id],
             name: "github_app_installations_unique_installation_id_index"
           )

    create table(:projects, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :name, :text, null: false
      add :github_owner, :text, null: false
      add :github_repo, :text, null: false
      add :github_full_name, :text, null: false
      add :default_branch, :text, null: false, default: "main"
      add :environment_type, :text, null: false, default: "local"
      add :local_path, :text
      add :sprite_spec, :map
      add :clone_status, :text, null: false, default: "pending"
      add :last_synced_at, :utc_datetime_usec
      add :settings, :map, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:projects, [:github_full_name],
             name: "projects_unique_github_full_name_index"
           )

    create table(:workflow_definitions, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :name, :text, null: false
      add :display_name, :text, null: false
      add :description, :text
      add :category, :text, null: false, default: "builtin"
      add :version, :bigint, null: false, default: 1
      add :definition, :map, null: false, default: %{}
      add :input_schema, :map, default: %{}
      add :default_inputs, :map, default: %{}
      add :triggers, {:array, :text}, default: ["manual"]
      add :approval_required, :boolean, null: false, default: true
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:workflow_definitions, [:name],
             name: "workflow_definitions_unique_name_index"
           )

    create table(:workflow_runs, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :status, :text, null: false, default: "pending"
      add :trigger, :text, null: false, default: "manual"
      add :trigger_metadata, :map, default: %{}
      add :inputs, :map, default: %{}
      add :current_step, :text
      add :step_results, :map, default: %{}
      add :error, :text
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :total_cost_usd, :decimal, default: "0"

      add :project_id,
          references(:projects,
            column: :id,
            name: "workflow_runs_project_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false

      add :workflow_definition_id,
          references(:workflow_definitions,
            column: :id,
            name: "workflow_runs_workflow_definition_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:workflow_runs, [:project_id])
    create index(:workflow_runs, [:workflow_definition_id])
    create index(:workflow_runs, [:status])

    create table(:project_secrets, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :key, :text, null: false
      add :env_var_name, :text
      add :configured, :boolean, null: false, default: false
      add :inject_to_env, :boolean, null: false, default: true

      add :project_id,
          references(:projects,
            column: :id,
            name: "project_secrets_project_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:project_secrets, [:project_id, :key],
             name: "project_secrets_unique_project_secret_key_index"
           )

    create index(:project_secrets, [:project_id])

    create table(:support_agent_configs, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :agent_type, :text, null: false
      add :enabled, :boolean, null: false, default: false
      add :configuration, :map, default: %{}
      add :webhook_events, {:array, :text}, default: []
      add :last_triggered_at, :utc_datetime_usec

      add :project_id,
          references(:projects,
            column: :id,
            name: "support_agent_configs_project_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:support_agent_configs, [:project_id, :agent_type],
             name: "support_agent_configs_unique_project_agent_type_index"
           )

    create index(:support_agent_configs, [:project_id])

    create table(:pull_requests, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :github_pr_number, :bigint, null: false
      add :github_pr_url, :text, null: false
      add :branch_name, :text, null: false
      add :title, :text, null: false
      add :body, :text
      add :status, :text, null: false, default: "open"
      add :created_at, :utc_datetime_usec
      add :merged_at, :utc_datetime_usec

      add :project_id,
          references(:projects,
            column: :id,
            name: "pull_requests_project_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false

      add :workflow_run_id,
          references(:workflow_runs,
            column: :id,
            name: "pull_requests_workflow_run_id_fkey",
            type: :uuid,
            prefix: "public"
          )

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:pull_requests, [:project_id, :github_pr_number],
             name: "pull_requests_unique_project_pr_number_index"
           )

    create index(:pull_requests, [:project_id])
    create index(:pull_requests, [:workflow_run_id])

    create table(:artifacts, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :type, :text, null: false
      add :name, :text, null: false
      add :content_type, :text, null: false
      add :content, :text
      add :file_path, :text
      add :metadata, :map, default: %{}

      add :workflow_run_id,
          references(:workflow_runs,
            column: :id,
            name: "artifacts_workflow_run_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create index(:artifacts, [:workflow_run_id])
    create index(:artifacts, [:type])
  end

  def down do
    drop_if_exists index(:artifacts, [:type])
    drop_if_exists index(:artifacts, [:workflow_run_id])
    drop table(:artifacts)

    drop_if_exists index(:pull_requests, [:workflow_run_id])
    drop_if_exists index(:pull_requests, [:project_id])

    drop_if_exists unique_index(:pull_requests, [:project_id, :github_pr_number],
                     name: "pull_requests_unique_project_pr_number_index"
                   )

    drop table(:pull_requests)

    drop_if_exists index(:support_agent_configs, [:project_id])

    drop_if_exists unique_index(:support_agent_configs, [:project_id, :agent_type],
                     name: "support_agent_configs_unique_project_agent_type_index"
                   )

    drop table(:support_agent_configs)

    drop_if_exists index(:project_secrets, [:project_id])

    drop_if_exists unique_index(:project_secrets, [:project_id, :key],
                     name: "project_secrets_unique_project_secret_key_index"
                   )

    drop table(:project_secrets)

    drop_if_exists index(:workflow_runs, [:status])
    drop_if_exists index(:workflow_runs, [:workflow_definition_id])
    drop_if_exists index(:workflow_runs, [:project_id])
    drop table(:workflow_runs)

    drop_if_exists unique_index(:workflow_definitions, [:name],
                     name: "workflow_definitions_unique_name_index"
                   )

    drop table(:workflow_definitions)

    drop_if_exists unique_index(:projects, [:github_full_name],
                     name: "projects_unique_github_full_name_index"
                   )

    drop table(:projects)

    drop_if_exists unique_index(:github_app_installations, [:installation_id],
                     name: "github_app_installations_unique_installation_id_index"
                   )

    drop table(:github_app_installations)

    drop_if_exists unique_index(:credentials, [:provider, :env_var_name],
                     name: "credentials_unique_provider_env_var_name_index"
                   )

    drop table(:credentials)
    drop table(:system_configs)
  end
end
