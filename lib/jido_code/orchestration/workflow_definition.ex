defmodule JidoCode.Orchestration.WorkflowDefinition do
  @moduledoc false
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Orchestration,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "workflow_definitions"
    repo JidoCode.Repo
  end

  code_interface do
    define :create
    define :read
    define :update
    define :destroy
    define :get_by_name, action: :read, get_by: [:name]
    define :list_builtin, action: :list_builtin
    define :list_custom, action: :list_custom
    define :bump_version
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :name,
        :display_name,
        :description,
        :category,
        :version,
        :definition,
        :input_schema,
        :default_inputs,
        :triggers,
        :approval_required
      ]
    end

    update :update do
      primary? true

      accept [
        :display_name,
        :description,
        :category,
        :definition,
        :input_schema,
        :default_inputs,
        :triggers,
        :approval_required
      ]
    end

    update :bump_version do
      require_atomic? false
      change atomic_update(:version, expr(version + 1))
    end

    read :list_builtin do
      filter expr(category == :builtin)
    end

    read :list_custom do
      filter expr(category == :custom)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :display_name, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :category, :atom do
      constraints one_of: [:builtin, :custom]
      allow_nil? false
      default :builtin
      public? true
    end

    attribute :version, :integer do
      allow_nil? false
      default 1
      public? true
    end

    attribute :definition, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :input_schema, :map do
      default %{}
      public? true
    end

    attribute :default_inputs, :map do
      default %{}
      public? true
    end

    attribute :triggers, {:array, :atom} do
      constraints items: [one_of: [:manual, :webhook, :schedule]]
      default [:manual]
      public? true
    end

    attribute :approval_required, :boolean do
      allow_nil? false
      default true
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :workflow_runs, JidoCode.Orchestration.WorkflowRun do
      destination_attribute :workflow_definition_id
    end
  end

  identities do
    identity :unique_workflow_definition_name, [:name]
  end
end
