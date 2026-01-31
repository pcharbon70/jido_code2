defmodule AgentJido.Forge.SpriteLiveTest do
  @moduledoc """
  Integration tests for the live Sprites client.

  These tests require a valid SPRITES_TOKEN or SPRITE_TOKEN environment variable
  and will create real remote containers.

  Run with: mix test test/agent_jido/forge/sprite_live_test.exs --include live_sprite
  """

  use ExUnit.Case, async: false

  alias AgentJido.Forge
  alias AgentJido.Forge.SpriteClient.Live

  @moduletag :live_sprite

  setup do
    token = System.get_env("SPRITES_TOKEN") || System.get_env("SPRITE_TOKEN")

    if is_nil(token) or token == "" do
      IO.puts("\n⚠️  Skipping live sprite tests: SPRITES_TOKEN/SPRITE_TOKEN not set")
      {:ok, skip: true}
    else
      original_client = Application.get_env(:agent_jido, :forge_sprite_client)
      Application.put_env(:agent_jido, :forge_sprite_client, Live)

      on_exit(fn ->
        if original_client do
          Application.put_env(:agent_jido, :forge_sprite_client, original_client)
        else
          Application.delete_env(:agent_jido, :forge_sprite_client)
        end
      end)

      {:ok, token: token, skip: false}
    end
  end

  describe "SpriteClient.Live" do
    @tag timeout: 120_000
    test "creates and destroys a sprite", %{skip: skip} do
      unless skip do
        {:ok, client, sprite_id} = Live.create(%{})

        try do
          assert %Live{} = client
          assert is_binary(sprite_id)
        after
          Live.destroy(client, sprite_id)
        end
      end
    end

    @tag timeout: 120_000
    test "executes commands and demonstrates end-to-end flow", %{skip: skip} do
      unless skip do
        {:ok, client, sprite_id} = Live.create(%{})

        try do
          {output, exit_code} = Live.exec(client, "echo 'Hello from Sprites!'", [])
          assert exit_code == 0
          assert output =~ "Hello from Sprites!"

          {pwd_output, 0} = Live.exec(client, "pwd", [])
          assert is_binary(pwd_output)

          test_content = "Hello world"
          write_result = Live.write_file(client, "/tmp/test_file.txt", test_content)
          assert write_result == :ok, "write_file failed: #{inspect(write_result)}"

          {:ok, read_content} = Live.read_file(client, "/tmp/test_file.txt")
          assert String.trim(read_content) == test_content

          {_, 0} = Live.exec(client, "mkdir -p /tmp/data", [])
          {_, 0} = Live.exec(client, "echo 'step1' > /tmp/data/step1.txt", [])
          {_, 0} = Live.exec(client, "echo 'step2' > /tmp/data/step2.txt", [])

          {cat_output, 0} = Live.exec(client, "cat /tmp/data/*.txt", [])
          assert cat_output =~ "step1"
          assert cat_output =~ "step2"

          {echo_output, 0} = Live.exec(client, "echo 'still working'", [])
          assert echo_output =~ "still working"
        after
          Live.destroy(client, sprite_id)
        end
      end
    end
  end

  describe "full end-to-end Forge session with live sprite" do
    @tag timeout: 180_000
    test "runs a complete session with shell runner", %{skip: skip} do
      unless skip do
        session_id = "live-test-#{System.unique_integer([:positive])}"

        spec = %{
          runner: AgentJido.Forge.Runners.Shell,
          runner_config: %{},
          sprite: %{},
          env: %{
            "TEST_VAR" => "hello_from_forge"
          },
          bootstrap: [
            %{type: "exec", command: "mkdir -p /app"},
            %{type: "file", path: "/app/greeting.txt", content: "Hello from Jido Forge!\n"}
          ]
        }

        {:ok, _pid} = Forge.start_session(session_id, spec)

        try do
          wait_for_session_ready(session_id, 60_000)

          {:ok, status} = Forge.status(session_id)
          assert status.state == :ready

          {output, exit_code} = Forge.exec(session_id, "cat /app/greeting.txt", [])

          assert exit_code == 0
          assert output =~ "Hello from Jido Forge!"

          {ls_output, 0} = Forge.exec(session_id, "ls -la /app", [])
          assert ls_output =~ "greeting.txt"

          {env_output, 0} = Forge.exec(session_id, "echo $TEST_VAR", [])
          assert env_output =~ "hello_from_forge"
        after
          Forge.stop_session(session_id)
        end
      end
    end
  end

  defp wait_for_session_ready(session_id, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_for_ready(session_id, deadline)
  end

  defp do_wait_for_ready(session_id, deadline) do
    now = System.monotonic_time(:millisecond)

    if now >= deadline do
      raise "Timeout waiting for session #{session_id} to become ready"
    end

    case Forge.status(session_id) do
      {:ok, %{state: :ready}} ->
        :ok

      {:ok, %{state: state}} when state in [:provisioning, :bootstrapping, :initializing] ->
        Process.sleep(500)
        do_wait_for_ready(session_id, deadline)

      {:ok, %{state: state}} ->
        raise "Session #{session_id} in unexpected state: #{state}"

      {:error, :not_found} ->
        Process.sleep(200)
        do_wait_for_ready(session_id, deadline)

      {:error, reason} ->
        raise "Error getting session status: #{inspect(reason)}"
    end
  end
end
