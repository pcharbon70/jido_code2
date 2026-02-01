defmodule AgentJido.Folio.InboxItem do
  @moduledoc """
  GTD Inbox Item resource - the capture bucket for raw thoughts.

  Brain dump anything here, then process it into Actions or Projects.
  """
  use Ash.Resource,
    domain: AgentJido.Folio,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshJido]

  ets do
    private? false
  end

  jido do
    action :capture,
      name: "capture_thought",
      description: "Capture a thought to inbox for later processing",
      tags: ["folio", "inbox", "gtd"]

    action :process_to_action,
      name: "clarify_to_action",
      description: "Turn an inbox item into a next action",
      tags: ["folio", "inbox", "gtd"]

    action :process_to_project,
      name: "clarify_to_project",
      description: "Turn an inbox item into a project",
      tags: ["folio", "inbox", "gtd"]

    action :discard,
      name: "discard_thought",
      description: "Discard a non-actionable inbox item",
      tags: ["folio", "inbox", "gtd"]

    action :inbox,
      name: "list_inbox",
      description: "List unprocessed inbox items",
      tags: ["folio", "inbox", "gtd"]
  end

  actions do
    defaults [:read]

    create :capture do
      accept [:content, :source, :notes]
      change set_attribute(:status, :inbox)
      change set_attribute(:captured_at, &DateTime.utc_now/0)
    end

    update :process_to_action do
      accept [:notes]
      require_atomic? false
      argument :title, :string, allow_nil?: false

      change fn changeset, _context ->
        title = Ash.Changeset.get_argument(changeset, :title)

        case Ash.create(AgentJido.Folio.Action, %{title: title, status: :next}, domain: AgentJido.Folio) do
          {:ok, action} ->
            changeset
            |> Ash.Changeset.force_change_attribute(:created_action_id, action.id)
            |> Ash.Changeset.force_change_attribute(:status, :processed)

          {:error, _} ->
            changeset
        end
      end
    end

    update :process_to_project do
      accept [:notes]
      require_atomic? false
      argument :title, :string, allow_nil?: false
      argument :outcome, :string

      change fn changeset, _context ->
        title = Ash.Changeset.get_argument(changeset, :title)
        outcome = Ash.Changeset.get_argument(changeset, :outcome)

        attrs = %{title: title, status: :active}
        attrs = if outcome, do: Map.put(attrs, :outcome, outcome), else: attrs

        case Ash.create(AgentJido.Folio.Project, attrs, domain: AgentJido.Folio) do
          {:ok, project} ->
            changeset
            |> Ash.Changeset.force_change_attribute(:created_project_id, project.id)
            |> Ash.Changeset.force_change_attribute(:status, :processed)

          {:error, _} ->
            changeset
        end
      end
    end

    update :discard do
      accept []
      change set_attribute(:status, :discarded)
    end

    read :inbox do
      filter expr(status == :inbox)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :content, :string, allow_nil?: false, public?: true
    attribute :source, :string, public?: true

    attribute :status, :atom,
      default: :inbox,
      constraints: [one_of: [:inbox, :processed, :discarded]],
      public?: true

    attribute :captured_at, :utc_datetime, public?: true
    attribute :notes, :string, public?: true

    attribute :created_action_id, :uuid, public?: true
    attribute :created_project_id, :uuid, public?: true

    timestamps()
  end

  relationships do
    belongs_to :created_action, AgentJido.Folio.Action do
      source_attribute :created_action_id
      define_attribute? false
    end

    belongs_to :created_project, AgentJido.Folio.Project do
      source_attribute :created_project_id
      define_attribute? false
    end
  end
end
