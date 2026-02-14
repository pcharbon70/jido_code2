defmodule JidoCode.Repo.Migrations.AddWorkflowRunRetryLineage do
  use Ecto.Migration

  def up do
    alter table(:workflow_runs) do
      add(:retry_of_run_id, :text)
      add(:retry_attempt, :bigint, null: false, default: 1)
      add(:retry_lineage, {:array, :map}, null: false, default: [])
    end

    create(
      index(:workflow_runs, [:project_id, :retry_of_run_id],
        name: "workflow_runs_retry_parent_index"
      )
    )
  end

  def down do
    drop_if_exists(
      index(:workflow_runs, [:project_id, :retry_of_run_id],
        name: "workflow_runs_retry_parent_index"
      )
    )

    alter table(:workflow_runs) do
      remove(:retry_lineage)
      remove(:retry_attempt)
      remove(:retry_of_run_id)
    end
  end
end
