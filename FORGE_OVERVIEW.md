# Jido Forge Overview

Forge is a **parallel sandbox execution** subsystem within AgentJido. It provisions isolated **sprites** (containers/sandboxes), runs **pluggable runners** inside them in discrete **iterations**, and persists/broadcasts session lifecycle and output so UIs and services can observe and control execution.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          AgentJido.Forge                                │
│                       (Public API Facade)                               │
├─────────────────────────────────────────────────────────────────────────┤
│  start_session/2 │ stop_session/2 │ exec/3 │ cmd/4 │ run_loop/2        │
└────────────────────────────┬────────────────────────────────────────────┘
                             │
         ┌───────────────────┼───────────────────┐
         ▼                   ▼                   ▼
┌─────────────────┐  ┌───────────────────┐  ┌─────────────────────┐
│     Manager     │  │   SpriteSession   │  │     Operations      │
│  (Lifecycle +   │  │  (Per-Session     │  │ (resume, cancel,    │
│   Concurrency)  │  │    Runtime)       │  │  checkpoint, etc.)  │
└────────┬────────┘  └────────┬──────────┘  └─────────────────────┘
         │                    │
         │           ┌────────┴────────┐
         │           ▼                 ▼
         │   ┌───────────────┐  ┌─────────────┐
         │   │ SpriteClient  │  │   Runner    │
         │   │ (Sandbox API) │  │ (Execution  │
         │   │ Fake / Live   │  │   Model)    │
         │   └───────────────┘  └─────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         Infrastructure                                  │
├──────────────────┬───────────────────┬──────────────────────────────────┤
│ DynamicSupervisor│     Registry      │          PubSub                  │
│ (SpriteSupervisor)│ (SessionRegistry) │ (forge:sessions, forge:session:*)│
└──────────────────┴───────────────────┴──────────────────────────────────┘
```

## Core Modules

### 1. `AgentJido.Forge` (Public API)

The facade module exposing the primary interface:

| Function | Purpose |
|----------|---------|
| `start_session/2` | Start a new session with a spec |
| `stop_session/2` | Stop a running session |
| `get_handle/1` | Get a `SessionHandle` for ergonomic command execution |
| `list_sessions/0` | List all active session IDs |
| `status/1` | Get current session status |
| `exec/3` | Execute raw command string in sprite |
| `cmd/4` | Execute command with args (shell-escaped) |
| `run_iteration/2` | Run single runner iteration |
| `run_loop/2` | Run iterations until done/blocked/needs_input |
| `apply_input/2` | Provide input when session is blocked |
| `resume/1` | Resume from checkpoint |
| `cancel/1` | Cancel running session |
| `create_checkpoint/2` | Snapshot session state |

### 2. `AgentJido.Forge.Manager`

Global lifecycle and concurrency management:

- Starts sessions under `DynamicSupervisor`
- Registers sessions in `Registry` by `session_id`
- Enforces concurrency limits (default: 50 total; per runner type limits)
- Broadcasts global session events via PubSub

### 3. `AgentJido.Forge.SpriteSession`

Per-session GenServer runtime that:

1. Provisions a sprite (container/sandbox)
2. Bootstraps environment (env vars, files, commands)
3. Initializes the runner
4. Executes iterations on demand
5. Handles input when blocked
6. Cleans up on termination

**Runtime States**: `:starting` → `:bootstrapping` → `:initializing` → `:ready` → `:running` ↔ `:needs_input`

### 4. `AgentJido.Forge.SpriteClient`

Abstraction layer for sprite operations:

| Operation | Purpose |
|-----------|---------|
| `create/1` | Provision a new sprite |
| `exec/3` | Execute command synchronously |
| `spawn/4` | Spawn command with streaming |
| `write_file/3` | Write file to sprite filesystem |
| `read_file/2` | Read file from sprite filesystem |
| `inject_env/2` | Set environment variables |
| `destroy/2` | Tear down sprite |

**Implementations**:
- `SpriteClient.Fake` - Local tmp dir + `System.cmd` (dev/test)
- `SpriteClient.Live` - Real Sprites SDK with API token

### 5. Runner Behaviour

Runners define the execution model—what happens each iteration:

```elixir
@callback init(client :: term(), config :: map()) :: {:ok, state} | {:error, term()}
@callback run_iteration(client :: term(), state :: term(), opts :: keyword()) :: 
  {:ok, result_map()} | {:error, term()}
@callback apply_input(client :: term(), input :: term(), state :: term()) :: 
  :ok | {:error, term()}
```

**Built-in Runners**:

| Runner | Purpose |
|--------|---------|
| `Runners.Shell` | Execute a single command |
| `Runners.Workflow` | Multi-step data-driven workflows |
| `Runners.ClaudeCode` | Claude Code CLI integration |
| `Runners.Custom` | Bring-your-own module/function |

## Session Lifecycle

### Starting a Session

```elixir
spec = %{
  runner: :shell,
  runner_config: %{command: "echo hello"},
  sprite: %{image: "ubuntu:latest"},
  bootstrap: [
    %{type: :exec, command: "apt-get update"}
  ],
  env: %{"MY_VAR" => "value"}
}

{:ok, handle} = Forge.start_session("my-session", spec)
```

**Flow**:
1. Manager checks concurrency limits
2. Persists session start event
3. Starts `SpriteSession` under supervisor
4. SpriteSession provisions sprite
5. Runs bootstrap steps
6. Initializes runner
7. Transitions to `:ready`

### Executing Work

```elixir
# Single iteration
{:ok, result} = Forge.run_iteration("my-session")

# Run until complete
{:ok, final} = Forge.run_loop("my-session", max_iterations: 100)

# Direct command execution
{output, exit_code} = Forge.cmd(handle, "ls", ["-la", "/app"])
```

### Handling Input

When a runner needs user input:

```elixir
{:ok, %{status: :needs_input, question: "What next?"}} = Forge.run_iteration(session_id)

# Provide input
:ok = Forge.apply_input(session_id, "user response")

# Continue execution
{:ok, result} = Forge.run_iteration(session_id)
```

### Stopping

```elixir
:ok = Forge.stop_session("my-session")
```

## Workflow Runner

The Workflow runner supports multi-step data-driven workflows:

```elixir
spec = %{
  runner: :workflow,
  runner_config: %{
    workflow: %{
      name: "deploy",
      steps: [
        %{id: "build", type: :exec, command: "make build"},
        %{id: "test", type: :exec, command: "make test"},
        %{id: "confirm", type: :prompt, question: "Deploy to prod?"},
        %{id: "deploy", type: :exec, command: "make deploy"}
      ]
    }
  }
}
```

**Step Types**:
- `:exec` - Run shell command
- `:prompt` - Request user input (returns `:needs_input`)
- `:condition` - Evaluate and branch based on prior results
- `:call` - Invoke custom `StepHandler` module
- `:noop` - No operation, continue

Supports string interpolation: `"{{build.output}}"` references prior step results.

## PubSub Events

Two topic families for real-time updates:

### Global: `"forge:sessions"`
- `{:session_started, session_id}`
- `{:session_stopped, session_id}`

### Per-Session: `"forge:session:<id>"`
- `{:status, %{state: ..., iteration: ...}}`
- `{:output, %{text: ..., exit_code: ...}}`
- `{:needs_input, %{prompt: ...}}`
- `{:stopped, reason}`

## Persistence (Ash Resources)

Durable audit/observability via Ash:

| Resource | Purpose |
|----------|---------|
| `Session` | Session metadata, phase, config, counts |
| `ExecSession` | Per-command execution records |
| `Event` | Append-only event log (output chunks, etc.) |
| `Checkpoint` | Session snapshots for resumption |
| `Workflow` | Stored workflow definitions |
| `SpriteSpec` | Sprite configuration catalog |

## Concurrency Limits

Default limits enforced by Manager:

| Limit | Default |
|-------|---------|
| Max total sessions | 50 |
| Max `claude_code` runners | 10 |
| Max `shell` runners | 20 |
| Max `workflow` runners | 10 |

## Usage Examples

### Basic Shell Execution

```elixir
{:ok, handle} = Forge.start_session("test", %{
  runner: :shell,
  runner_config: %{command: "echo 'Hello World'"}
})

{:ok, result} = Forge.run_loop("test")
# result.output => "Hello World\n"
```

### Direct Command Execution

```elixir
{:ok, handle} = Forge.start_session("workspace", %{
  runner: :shell,
  runner_config: %{}
})

{output, 0} = Forge.cmd(handle, "git", ["status"])
{output, 0} = Forge.cmd(handle, "mix", ["test"])
```

### Claude Code Integration

```elixir
{:ok, handle} = Forge.start_session("claude", %{
  runner: :claude_code,
  runner_config: %{
    task: "Implement a REST API endpoint",
    cwd: "/app"
  }
})

# Run until Claude finishes or needs input
{:ok, result} = Forge.run_loop("claude")
```

## Key Design Decisions

1. **Separation of Runtime vs Persistence**: GenServer state is authoritative for "now"; Ash DB is best-effort eventual consistency for audit/replay.

2. **Pluggable Everything**: Runners and SpriteClients are swappable, enabling different execution models and sandbox implementations.

3. **Iteration-Based Model**: Work happens in discrete iterations, enabling pause/resume, input handling, and observability.

4. **Concurrency Control**: Global limits prevent resource exhaustion; per-runner-type limits enable fair scheduling.

5. **PubSub for Real-Time**: UIs can subscribe to session updates without polling.

## Current Limitations

- **Checkpoint/Resume**: Partially implemented; sprite-level checkpointing is stubbed
- **Runner State Propagation**: Some inconsistency in how runner state flows between iterations
- **StreamingExecSessionWorker**: Separate execution path for streaming; not fully integrated with SpriteSession
