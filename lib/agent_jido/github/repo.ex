defmodule AgentJido.GitHub.Repo do
  use Ash.Resource,
    otp_app: :agent_jido,
    domain: AgentJido.GitHub,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "github_repos"
    repo AgentJido.Repo
  end

  code_interface do
    define :create
    define :read
    define :get_by_id, action: :read, get_by: [:id]
    define :get_by_full_name, action: :read, get_by: [:full_name]
    define :update
    define :disable
    define :enable
    define :list_enabled, action: :list_enabled
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:owner, :name, :webhook_secret, :webhook_id, :settings, :github_app_installation_id]
      primary? true

      change fn changeset, _ctx ->
        owner = Ash.Changeset.get_attribute(changeset, :owner)
        name = Ash.Changeset.get_attribute(changeset, :name)

        if owner && name do
          Ash.Changeset.force_change_attribute(changeset, :full_name, "#{owner}/#{name}")
        else
          changeset
        end
      end
    end

    update :update do
      accept [:webhook_secret, :webhook_id, :settings, :enabled, :github_app_installation_id]
      primary? true
    end

    update :disable do
      change set_attribute(:enabled, false)
    end

    update :enable do
      change set_attribute(:enabled, true)
    end

    read :list_enabled do
      filter expr(enabled == true)
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

    attribute :owner, :string do
      allow_nil? false
      public? true
      description "GitHub repository owner (user or organization)"
    end

    attribute :name, :string do
      allow_nil? false
      public? true
      description "GitHub repository name"
    end

    attribute :full_name, :string do
      allow_nil? false
      public? true
      description "Full repository name (owner/name)"
    end

    attribute :webhook_secret, :string do
      allow_nil? false
      sensitive? true
      description "Secret for verifying webhook signatures"
    end

    attribute :webhook_id, :integer do
      allow_nil? true
      public? true
      description "GitHub webhook ID (if auto-configured)"
    end

    attribute :enabled, :boolean do
      allow_nil? false
      default true
      public? true
      description "Whether webhook processing is enabled for this repo"
    end

    attribute :settings, :map do
      allow_nil? true
      default %{}
      public? true
      description "Repository-specific settings (auto_label, auto_comment, etc.)"
    end

    attribute :github_app_installation_id, :integer do
      allow_nil? true
      public? true
      description "GitHub App installation ID (if using GitHub App auth)"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, AgentJido.Accounts.User do
      allow_nil? true
      public? true
      description "User who owns this watched repository"
    end

    has_many :webhook_deliveries, AgentJido.GitHub.WebhookDelivery do
      destination_attribute :repo_id
    end

    has_many :issue_analyses, AgentJido.GitHub.IssueAnalysis do
      destination_attribute :repo_id
    end
  end

  identities do
    identity :unique_full_name, [:full_name]
  end
end
