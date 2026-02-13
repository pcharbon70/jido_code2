defmodule JidoCode.Setup.GithubAppInstallation do
  @moduledoc false
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Setup,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "github_app_installations"
    repo JidoCode.Repo
  end

  code_interface do
    define :create
    define :read
    define :update
    define :destroy
    define :get_by_installation_id, action: :read, get_by: [:installation_id]
    define :list_by_account_login, action: :list_by_account_login
    define :cache_access_token
    define :clear_cached_access_token
    define :set_selected_repos
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :installation_id,
        :account_login,
        :account_type,
        :cached_access_token,
        :token_expires_at,
        :permissions,
        :repository_selection,
        :selected_repos
      ]
    end

    update :update do
      primary? true

      accept [
        :account_login,
        :account_type,
        :cached_access_token,
        :token_expires_at,
        :permissions,
        :repository_selection,
        :selected_repos
      ]
    end

    update :cache_access_token do
      require_atomic? false

      argument :cached_access_token, :string do
        allow_nil? false
      end

      argument :token_expires_at, :utc_datetime_usec do
        allow_nil? false
      end

      change fn changeset, _context ->
        token = Ash.Changeset.get_argument(changeset, :cached_access_token)
        expires_at = Ash.Changeset.get_argument(changeset, :token_expires_at)

        changeset
        |> Ash.Changeset.force_change_attribute(:cached_access_token, token)
        |> Ash.Changeset.force_change_attribute(:token_expires_at, expires_at)
      end
    end

    update :clear_cached_access_token do
      change set_attribute(:cached_access_token, nil)
      change set_attribute(:token_expires_at, nil)
    end

    update :set_selected_repos do
      accept [:selected_repos]
      change set_attribute(:repository_selection, :selected)
    end

    read :list_by_account_login do
      argument :account_login, :string do
        allow_nil? false
      end

      filter expr(account_login == ^arg(:account_login))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :installation_id, :integer do
      allow_nil? false
      public? true
    end

    attribute :account_login, :string do
      allow_nil? false
      public? true
    end

    attribute :account_type, :atom do
      constraints one_of: [:user, :organization]
      allow_nil? false
      public? true
    end

    attribute :cached_access_token, :string do
      sensitive? true
    end

    attribute :token_expires_at, :utc_datetime_usec do
      public? true
    end

    attribute :permissions, :map do
      default %{}
      public? true
    end

    attribute :repository_selection, :atom do
      constraints one_of: [:all, :selected]
      allow_nil? false
      default :all
      public? true
    end

    attribute :selected_repos, {:array, :string} do
      default []
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_installation_id, [:installation_id]
  end
end
