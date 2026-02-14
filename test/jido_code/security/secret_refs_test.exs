defmodule JidoCode.Security.SecretRefsTest do
  use JidoCode.DataCase, async: false

  require Ash.Query

  alias JidoCode.Security
  alias JidoCode.Security.{SecretRef, SecretRefs}

  @valid_test_encryption_key "MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE="

  setup do
    original_key = Application.get_env(:jido_code, :secret_ref_encryption_key, :__missing__)

    on_exit(fn ->
      restore_env(:secret_ref_encryption_key, original_key)
    end)

    Application.put_env(:jido_code, :secret_ref_encryption_key, @valid_test_encryption_key)
    :ok
  end

  test "persist_operational_secret stores encrypted ciphertext and metadata remains queryable" do
    name = "github/webhook_secret_#{System.unique_integer([:positive])}"
    plaintext_value = "super-secret-#{System.unique_integer([:positive])}"

    assert {:ok, metadata} =
             SecretRefs.persist_operational_secret(%{
               scope: :integration,
               name: name,
               value: plaintext_value,
               source: :onboarding
             })

    query =
      SecretRef
      |> Ash.Query.filter(scope == :integration and name == ^name)
      |> Ash.Query.limit(1)

    assert {:ok, [stored_secret_ref]} = Ash.read(query, domain: Security, authorize?: false)
    assert stored_secret_ref.name == name
    assert stored_secret_ref.scope == :integration
    assert is_binary(stored_secret_ref.ciphertext)
    refute stored_secret_ref.ciphertext == plaintext_value

    assert {:ok, metadata_list} = SecretRefs.list_secret_metadata()
    metadata_id = metadata.id

    assert %{
             id: ^metadata_id,
             scope: :integration,
             name: ^name,
             source: :onboarding,
             key_version: 1
           } = Enum.find(metadata_list, &(&1.id == metadata_id))

    metadata_row = Enum.find(metadata_list, &(&1.id == metadata_id))
    refute Map.has_key?(metadata_row, :ciphertext)
    refute Enum.any?(Map.values(metadata_row), &(&1 == plaintext_value))
  end

  test "persist_operational_secret blocks writes with typed remediation when encryption is unavailable" do
    Application.delete_env(:jido_code, :secret_ref_encryption_key)

    name = "github/encryption_missing_#{System.unique_integer([:positive])}"

    assert {:error, typed_error} =
             SecretRefs.persist_operational_secret(%{
               scope: :integration,
               name: name,
               value: "must-not-store"
             })

    assert typed_error.error_type == "secret_encryption_unavailable"
    assert typed_error.message == "Secret encryption is unavailable and no secret was persisted."
    assert typed_error.recovery_instruction =~ "JIDO_CODE_SECRET_REF_ENCRYPTION_KEY"

    query =
      SecretRef
      |> Ash.Query.filter(scope == :integration and name == ^name)
      |> Ash.Query.limit(1)

    assert {:ok, []} = Ash.read(query, domain: Security, authorize?: false)
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
