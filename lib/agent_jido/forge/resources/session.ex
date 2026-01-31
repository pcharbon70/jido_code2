defmodule AgentJido.Forge.Resources.Session do
  use Ash.Resource,
    otp_app: :agent_jido,
    domain: AgentJido.Forge.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "forge_sessions"
    repo AgentJido.Repo
  end

  actions do
    defaults [:read, :destroy, :create, :update]
  end

  attributes do
    uuid_primary_key :id

    attribute :session_id, :string, allow_nil?: false, public?: true
    attribute :sprite_id, :string, public?: true
    attribute :runner, :atom, public?: true
    attribute :state, :atom, public?: true
    attribute :iteration, :integer, default: 0, public?: true
    attribute :spec_snapshot, :map, default: %{}, public?: true
    attribute :last_activity_at, :utc_datetime_usec, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_session_id, [:session_id]
  end
end
