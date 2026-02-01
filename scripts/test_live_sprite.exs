# Test script for live sprite round-trip
# Run with: mix run scripts/test_live_sprite.exs
#
# Requires SPRITES_TOKEN or SPRITE_TOKEN environment variable to be set

# Load .env file if present
if File.exists?(".env") do
  Dotenvy.source!(".env")
end

alias AgentJido.Forge.SpriteClient
alias AgentJido.Forge.SpriteClient.Live

IO.puts("=" |> String.duplicate(60))
IO.puts("Live Sprite Round-Trip Test")
IO.puts("=" |> String.duplicate(60))

# Check for token (accept both names)
token = System.get_env("SPRITES_TOKEN") || System.get_env("SPRITE_TOKEN")

if is_nil(token) or token == "" do
  IO.puts("\n❌ ERROR: SPRITES_TOKEN/SPRITE_TOKEN environment variable not set")
  IO.puts("Please set the token in .env or environment and try again")
  System.halt(1)
end

IO.puts("\n✓ Sprite token is set")

# Step 1: Create a live sprite
IO.puts("\n[1/7] Creating live sprite...")

spec = %{
  name: "test-sprite-#{:rand.uniform(100_000)}"
}

{:ok, client, sprite_id} = Live.create(spec)
IO.puts("✓ Created sprite with ID: #{sprite_id}")
IO.puts("  Client type: #{inspect(client.__struct__)}")

# Step 2: Wait for sprite to be ready
IO.puts("\n[2/7] Waiting for sprite to start (3 seconds)...")
Process.sleep(3_000)
IO.puts("✓ Wait complete")

# Step 3: Test exec through the facade (this was the bug!)
IO.puts("\n[3/7] Testing exec through SpriteClient facade...")
IO.puts("  Running: echo 'Hello from live sprite!'")

{output, exit_code} = SpriteClient.exec(client, "echo 'Hello from live sprite!'", [])
IO.puts("  Exit code: #{exit_code}")
IO.puts("  Output: #{String.trim(output)}")

if exit_code == 0 and String.contains?(output, "Hello from live sprite!") do
  IO.puts("✓ Facade dispatch working correctly!")
else
  IO.puts("❌ Unexpected result")
end

# Step 4: Test file write
IO.puts("\n[4/7] Testing file write...")
test_content = "This is test content written at #{DateTime.utc_now()}"

case SpriteClient.write_file(client, "/tmp/test_file.txt", test_content) do
  :ok ->
    IO.puts("✓ File written successfully")

  {:error, reason} ->
    IO.puts("❌ Write failed: #{inspect(reason)}")
end

# Step 5: Test file read
IO.puts("\n[5/7] Testing file read...")

case SpriteClient.read_file(client, "/tmp/test_file.txt") do
  {:ok, content} ->
    IO.puts("✓ File read successfully")
    IO.puts("  Content: #{String.trim(content)}")

  {:error, reason} ->
    IO.puts("❌ Read failed: #{inspect(reason)}")
end

# Step 6: Test environment injection
IO.puts("\n[6/7] Testing environment injection...")

case SpriteClient.inject_env(client, %{"MY_VAR" => "test_value", "ANOTHER" => "hello"}) do
  :ok ->
    IO.puts("✓ Environment injected")

    # Verify env is available
    {env_output, _} = SpriteClient.exec(client, "echo $MY_VAR", [])
    IO.puts("  MY_VAR value: #{String.trim(env_output)}")

  {:error, reason} ->
    IO.puts("❌ Inject failed: #{inspect(reason)}")
end

# Step 7: Cleanup - destroy the sprite
IO.puts("\n[7/7] Destroying sprite...")

case SpriteClient.destroy(client, sprite_id) do
  :ok ->
    IO.puts("✓ Sprite destroyed successfully")

  {:error, reason} ->
    IO.puts("❌ Destroy failed: #{inspect(reason)}")
end

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("Test complete!")
IO.puts(String.duplicate("=", 60))
