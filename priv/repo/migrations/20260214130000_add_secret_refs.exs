defmodule JidoCode.Repo.Migrations.AddSecretRefs do
  use Ecto.Migration

  def up do
    create table(:secret_refs, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :scope, :text, null: false
      add :name, :text, null: false
      add :ciphertext, :text, null: false
      add :key_version, :bigint, null: false, default: 1
      add :source, :text, null: false, default: "onboarding"
      add :last_rotated_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:secret_refs, [:scope, :name],
             name: "secret_refs_unique_scope_name_index"
           )
  end

  def down do
    drop_if_exists unique_index(:secret_refs, [:scope, :name],
                     name: "secret_refs_unique_scope_name_index"
                   )

    drop table(:secret_refs)
  end
end
