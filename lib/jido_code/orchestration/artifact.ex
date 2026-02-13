defmodule JidoCode.Orchestration.Artifact do
  @moduledoc false
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Orchestration,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "artifacts"
    repo JidoCode.Repo
  end

  code_interface do
    define :create
    define :read
    define :update
    define :destroy
    define :list_for_run, action: :list_for_run
    define :list_for_run_by_type, action: :list_for_run_by_type
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    read :list_for_run do
      argument :workflow_run_id, :uuid do
        allow_nil? false
      end

      filter expr(workflow_run_id == ^arg(:workflow_run_id))
    end

    read :list_for_run_by_type do
      argument :workflow_run_id, :uuid do
        allow_nil? false
      end

      argument :type, :atom do
        allow_nil? false

        constraints one_of: [
                      :log,
                      :diff,
                      :report,
                      :transcript,
                      :pr_url,
                      :cost_summary,
                      :research_doc,
                      :design_doc,
                      :prompt_file
                    ]
      end

      filter expr(workflow_run_id == ^arg(:workflow_run_id) and type == ^arg(:type))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :type, :atom do
      constraints one_of: [
                    :log,
                    :diff,
                    :report,
                    :transcript,
                    :pr_url,
                    :cost_summary,
                    :research_doc,
                    :design_doc,
                    :prompt_file
                  ]

      allow_nil? false
      public? true
    end

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :content_type, :string do
      allow_nil? false
      public? true
    end

    attribute :content, :string do
      public? true
    end

    attribute :file_path, :string do
      public? true
    end

    attribute :metadata, :map do
      default %{}
      public? true
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :workflow_run, JidoCode.Orchestration.WorkflowRun do
      allow_nil? false
      public? true
    end
  end
end
