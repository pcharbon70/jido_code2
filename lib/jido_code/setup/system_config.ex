defmodule JidoCode.Setup.SystemConfig do
  @moduledoc false
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Setup,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "system_configs"
    repo JidoCode.Repo
  end

  code_interface do
    define :create
    define :read
    define :update
    define :destroy
    define :complete_onboarding
    define :set_onboarding_step
    define :set_default_environment
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :onboarding_completed,
        :onboarding_step,
        :default_environment,
        :local_workspace_root,
        :sprites_api_configured
      ]
    end

    update :update do
      primary? true

      accept [
        :onboarding_completed,
        :onboarding_step,
        :default_environment,
        :local_workspace_root,
        :sprites_api_configured
      ]
    end

    update :complete_onboarding do
      change set_attribute(:onboarding_completed, true)
    end

    update :set_onboarding_step do
      require_atomic? false

      argument :onboarding_step, :integer do
        allow_nil? false
      end

      change fn changeset, _context ->
        step = Ash.Changeset.get_argument(changeset, :onboarding_step)
        Ash.Changeset.force_change_attribute(changeset, :onboarding_step, step)
      end
    end

    update :set_default_environment do
      require_atomic? false

      argument :default_environment, :atom do
        allow_nil? false
        constraints one_of: [:local, :sprite]
      end

      change fn changeset, _context ->
        environment = Ash.Changeset.get_argument(changeset, :default_environment)
        Ash.Changeset.force_change_attribute(changeset, :default_environment, environment)
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :onboarding_completed, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :onboarding_step, :integer do
      allow_nil? false
      default 0
      public? true
    end

    attribute :default_environment, :atom do
      constraints one_of: [:local, :sprite]
      allow_nil? false
      default :local
      public? true
    end

    attribute :local_workspace_root, :string do
      allow_nil? false
      default "~/.jido_code/workspaces"
      public? true
    end

    attribute :sprites_api_configured, :boolean do
      allow_nil? false
      default false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end
end
