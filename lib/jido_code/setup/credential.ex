defmodule JidoCode.Setup.Credential do
  @moduledoc false
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Setup,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "credentials"
    repo JidoCode.Repo
  end

  code_interface do
    define :create
    define :read
    define :update
    define :destroy
    define :get_by_provider_and_env_var, action: :read, get_by: [:provider, :env_var_name]
    define :list_active, action: :list_active
    define :list_by_provider, action: :list_by_provider
    define :mark_verified
    define :set_status
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:provider, :name, :env_var_name, :metadata, :verified_at, :status]
    end

    update :update do
      primary? true
      accept [:name, :metadata, :verified_at, :status]
    end

    update :mark_verified do
      accept [:metadata]
      change set_attribute(:verified_at, &DateTime.utc_now/0)
      change set_attribute(:status, :active)
    end

    update :set_status do
      require_atomic? false

      argument :status, :atom do
        allow_nil? false
        constraints one_of: [:active, :invalid, :expired, :not_set]
      end

      change fn changeset, _context ->
        status = Ash.Changeset.get_argument(changeset, :status)
        Ash.Changeset.force_change_attribute(changeset, :status, status)
      end
    end

    read :list_active do
      filter expr(status == :active)
    end

    read :list_by_provider do
      argument :provider, :atom do
        allow_nil? false
        constraints one_of: [:anthropic, :openai, :google, :github_app, :github_pat, :sprites]
      end

      filter expr(provider == ^arg(:provider))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :provider, :atom do
      constraints one_of: [:anthropic, :openai, :google, :github_app, :github_pat, :sprites]
      allow_nil? false
      public? true
    end

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :env_var_name, :string do
      allow_nil? false
      public? true
    end

    attribute :metadata, :map do
      default %{}
      public? true
    end

    attribute :verified_at, :utc_datetime_usec do
      public? true
    end

    attribute :status, :atom do
      constraints one_of: [:active, :invalid, :expired, :not_set]
      allow_nil? false
      default :not_set
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_provider_env_var_name, [:provider, :env_var_name]
  end
end
