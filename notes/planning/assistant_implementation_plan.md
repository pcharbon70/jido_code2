# Implementation Plan: JidoCode1 → JidoCode2 Integration

## Overview

Create a new **Assistant subsystem** in JidoCode2 that provides JidoCode1's chat/coding assistant functionality using Phoenix LiveView, following Forge's proven patterns for session management and real-time UI.

**Key Decision**: Build Assistant as a subsystem parallel to Forge (not replacing it):
- **Forge** = sprite-based execution (containers, workflows, iterations)
- **Assistant** = conversational AI (chat, coding help, streaming)

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      JidoCode.Assistant (Public API)              │
│                     start_session, send_message, cancel              │
├─────────────────────────────────────────────────────────────────────────┤
│  Assistant.Manager      │  Assistant.Session     │  Assistant.PubSub  │
│  (Lifecycle +         │  (Per-chat GenServer)  │  (Events helper)   │
│   Concurrency)         │  - Conversation state  │  - broadcast          │
│                       │  - Message history    │  - subscribe         │
│                       │  - Tool execution     │                     │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Assistant.Runner (Behaviour)                      │
│  ┌─────────────┬──────────────┬──────────────┬─────────────┐│
│  │ ReAct       │ ClaudeCodeCLI │ Workflow     │ Custom       ││
│  │ (chat+tools)│ (external)     │ (steps)       │ (user)       ││
│  └─────────────┴──────────────┴──────────────┴─────────────┘│
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                       Tool System                                │
│  ┌──────────────┬─────────────┬─────────────┬────────────┐ │
│  │ File         │ Shell       │ Git         │ Settings   │ │
│  │ read/write/   │ exec with  │ status/      │ global/    │ │
│  │ search       │ allowlist   │ commit/diff  │ project    │ │
│  └──────────────┴─────────────┴─────────────┴────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Core Infrastructure (Week 1)

### Goal
Create the Assistant subsystem foundation using Forge patterns.

### Files to Create

**lib/jido_code/assistant/manager.ex**
```elixir
defmodule JidoCode.Assistant.Manager do
  use GenServer

  # Responsibilities:
  # - Start sessions under DynamicSupervisor
  # - Enforce concurrency limits (default: 20 concurrent chats)
  # - Registry registration for PID lookup
  # - Broadcast global events on PubSub

  # API:
  # start_session(id, spec) -> {:ok, pid} | {:error, reason}
  # stop_session(id) -> :ok | {:error, reason}
  # list_sessions() -> [id]
  # get_session(id) -> {:ok, pid} | {:error, :not_found}
end
```

**lib/jido_code/assistant/session.ex**
```elixir
defmodule JidoCode.Assistant.Session do
  use GenServer

  # State machine: :initializing → :ready → :processing → :needs_input → :ready
  # Follows Forge.SpriteSession pattern

  # State:
  #   - id, status, messages, settings, runner_state
  #   - conversation_history, tool_context

  # Callbacks:
  # - init: validate config, register in Registry
  # - handle_call: :send_message, :get_status, :set_config
  # - handle_info: :llm_chunk, :tool_complete, :error
  # - terminate: cleanup, broadcast :session_stopped

  # PubSub broadcasts:
  # - {:status, %{phase: ..., iteration: ...}}
  # - {:message_delta, %{role: ..., content: ...}}
  # - {:tool_call, %{tool: ..., input: ...}}
  # - {:tool_result, %{tool: ..., output: ...}}
end
```

**lib/jido_code/assistant/pubsub.ex**
```elixir
defmodule JidoCode.Assistant.PubSub do
  # Topic constants
  @sessions_topic "assistant:sessions"
  def session_topic(id), do: "assistant:session:#{id}"

  # Events (following Forge pattern):
  # {:session_started, id}
  # {:session_stopped, id, reason}
  # {:status, %{status: ..., messages: ...}}
  # {:message_delta, %{content: ..., role: ...}}
  # {:tool_call, %{tool: ..., args: ...}}
  # {:tool_result, %{tool: ..., result: ...}}
end
```

**lib/jido_code/assistant/resources/session.ex** (Ash resource)
```elixir
defmodule JidoCode.Assistant.Resources.Session do
  use Ash.Resource

  # For persistence and audit
  # Fields: id, user_id, title, status, message_count
  # State: :creating, :active, :paused, :completed, :failed
  # Relationships: messages, settings
end
```

**lib/jido_code/assistant/resources/message.ex** (Ash resource)
```elixir
defmodule JidoCode.Assistant.Resources.Message do
  use Ash.Resource

  # Conversation history
  # Fields: session_id, role (:user/:assistant/:system/:tool), content
  # Metadata: tool_calls, tokens, timestamp
end
```

### Integration Points
- Add `Assistant.Supervisor` to `lib/jido_code/application.ex` supervision tree
- Add PubSub topics to configuration
- Create Ash migration for resources

---

## Phase 2: Runner System + Streaming (Week 2)

### Goal
Implement pluggable runners for different AI backends with streaming.

### Files to Create

**lib/jido_code/assistant/runner.ex**
```elixir
defmodule JidoCode.Assistant.Runner do
  @callback init(config :: map()) :: {:ok, state :: term()} | {:error, term()}
  @callback send_message(state :: term(), message :: String.t(), history :: list()) ::
    {:ok, response :: map()} | {:error, term()}
  @callback stream_message(state :: term(), message :: String.t(), history :: list(),
    send_fn :: function()) :: {:ok, state :: term()} | {:error, term()}
  @callback apply_input(state :: term(), input :: term()) :: :ok | {:error, term()}
  @callback terminate(state :: term(), reason :: term()) :: :ok
end
```

**lib/jido_code/assistant/runners/react.ex**
```elixir
defmodule JidoCode.Assistant.Runners.ReAct do
  @behaviour JidoCode.Assistant.Runner

  # Uses Jido.AI.ReActAgent
  # - Tool-using chat agent
  # - Streaming token support
  # - Handles multi-turn conversations

  # Integrates with existing JidoCode.Jido supervisor
  # Uses req_llm for LLM calls
end
```

**lib/jido_code/assistant/runners/claude_code.ex**
```elixir
defmodule JidoCode.Assistant.Runners.ClaudeCode do
  @behaviour JidoCode.Assistant.Runner

  # External Claude Code CLI integration
  # Spawns claude-code process
  # Parses --output-format stream-json
  # Similar to Forge.Runners.ClaudeCode pattern
end
```

### Integration Points
- Register runners with Manager
- Add runner selection to session spec
- Wire streaming through Session to PubSub

---

## Phase 3: Tool System (Week 2-3)

### Goal
Implement secure tool system with Registry, Executor, and Policies.

### Files to Create

**lib/jido_code/tools/registry.ex**
```elixir
defmodule JidoCode.Tools.Registry do
  # Tool registration and discovery
  # All tools define schema/1
  # validate_input/2
  # execute/2

  # Built-in tools:
  # - File: read, write, list, search, grep
  # - Shell: exec (with allowlist)
  # - Git: status, commit, diff, log, branch
end
```

**lib/jido_code/tools/executor.ex**
```elixir
defmodule JidoCode.Tools.Executor do
  # Execute tools with:
  # - Timeout enforcement (default 30s)
  # - Output size limits (max 10MB)
  # - Logging to session events
  # - Error handling
end
```

**lib/jido_code/tools/policies.ex**
```elixir
defmodule JidoCode.Tools.Policies do
  # Security policies:
  # - Path validation (workspace root only)
  # - Command allowlist for shell
  # - File extension blacklist
  # - Output size limits
end
```

**lib/jido_code/tools/file/read.ex** (example tool)
```elixir
defmodule JidoCode.Tools.File.Read do
  use Jido.Action

  def schema do
    [
      arg(:path, type: :string, required: true),
      arg(:offset, type: :integer, default: 0),
      arg(:limit, type: :integer, default: nil)
    ]
  end

  def run(params, context) do
    # Path validation via Policies
    # Read file content
    # Return {:ok, %{content: ...}}
  end
end
```

**lib/jido_code/tools/shell.ex**
```elixir
defmodule JidoCode.Tools.Shell do
  use Jido.Action

  # Allowlist of safe commands
  @allowed_commands ~w(ls cat cd pwd echo grep find head tail)

  def schema do
    [arg(:command, type: :string, required: true)]
  end

  def run(%{"command" => cmd}, _context) do
    # Check allowlist
    # Execute with timeout
    # Return {:ok, %{exit_code: ..., output: ...}}
  end
end
```

---

## Phase 4: Settings + Slash Commands (Week 3-4)

### Goal
Two-level settings management and slash command parsing.

### Files to Create

**lib/jido_code/settings.ex**
```elixir
defmodule JidoCode.Settings do
  # Load order (highest to lowest):
  # 1. Environment variables (ANTHROPIC_API_KEY, etc.)
  # 2. Project settings (./.jido/settings.json)
  # 3. Global settings (~/.jido/settings.json)

  defstruct [:provider, :model, :temperature, :max_tokens,
    :allowed_paths, :tool_allowlist]

  def load(), do: ...
  def save(settings), do: ...
  def get(key), do: ...
end
```

**lib/jido_code/assistant/commands/parser.ex**
```elixir
defmodule JidoCode.Assistant.Commands.Parser do
  # Parse slash commands from input
  # /provider <name>
  # /model <name>
  # /models
  # /config [key=value]
  # /clear

  def parse(input) :: {:command, term()} | {:chat, String.t()}
end
```

**lib/jido_code/assistant/commands/router.ex**
```elixir
defmodule JidoCode.Assistant.Commands.Router do
  # Route parsed commands to actions
  def route(:provider, name, session), do: set_provider(session, name)
  def route(:model, name, session), do: set_model(session, name)
  def route(:models, _, session), do: list_models(session)
  def route(:config, kv_pairs, session), do: update_config(session, kv_pairs)
  def route(:clear, _, session), do: clear_history(session)
end
```

---

## Phase 5: LiveView UI (Week 4-5)

### Goal
Chat interface with PubSub streaming (no polling).

### Files to Create

**lib/jido_code_web/live/assistant_live/index.ex**
```elixir
defmodule JidoCodeWeb.AssistantLive.Index do
  use JidoCodeWeb, :live_view

  # Session list page
  # - Shows active/completed sessions
  # - Create new session button
  # - Follows Forge session list pattern
end
```

**lib/jido_code_web/live/assistant_live/show.ex**
```elixir
defmodule JidoCodeWeb.AssistantLive.Show do
  use JidoCodeWeb, :live_view

  # Single chat session page
  # Subscribes to "assistant:session:<id>"
  # Streams messages with LV stream
  # Input form with submit handler
  # Slash command parsing
  # Tool visualization (planning → executing → done)

  def mount(%{"id" => id}, _session, socket) do
    Assistant.PubSub.subscribe_session(id)
    # Load session from Ash
    {:ok, assign(socket, session_id: id, messages: [])}
  end

  def handle_info({:message_delta, delta}, socket) do
    # Append to message stream
    {:noreply, stream_insert(socket, :messages, delta)}
  end

  def handle_info({:tool_call, call}, socket) do
    # Update tool status in UI
    {:noreply, stream_insert(socket, :tool_calls, call)}
  end

  def handle_event("send_message", %{"text" => text}, socket) do
    # Check for slash command
    case Commands.Parser.parse(text) do
      {:command, cmd} -> Commands.Router.route(cmd, socket.assigns.session_id)
      {:chat, msg} -> Assistant.send_message(socket.assigns.session_id, msg)
    end
    {:noreply, socket}
  end
end
```

**lib/jido_code_web/components/assistant/message.ex**
```elixir
defmodule JidoCodeWeb.Assistant.Message do
  use Phoenix.Component

  # Message rendering with:
  # - User/assistant/system/tool roles
  # - Markdown rendering
  # - Syntax highlighting for code blocks
  # - Timestamps
end
```

---

## Supervision Tree

Add to `lib/jido_code/application.ex`:

```elixir
children = [
  # ... existing children ...

  # Assistant subsystem
  {JidoCode.Assistant.PubSub, []},
  {Registry, keys: :unique, name: JidoCode.Assistant.SessionRegistry},
  {DynamicSupervisor, name: JidoCode.Assistant.SessionSupervisor, strategy: :one_for_one},
  {JidoCode.Assistant.Manager, name: JidoCode.Assistant.Manager}
]
```

---

## Router Additions

Add to `lib/jido_code_web/router.ex`:

```elixir
scope "/", JidoCodeWeb do
  pipe_through [:browser, :require_authenticated_user]

  live "/assistant", AssistantLive.Index, :index
  live "/assistant/:id", AssistantLive.Show, :show
end
```

---

## Critical Files Summary

### New Modules to Create
| File | Purpose |
|-------|---------|
| `lib/jido_code/assistant/manager.ex` | Session lifecycle, concurrency |
| `lib/jido_code/assistant/session.ex` | Per-chat GenServer runtime |
| `lib/jido_code/assistant/pubsub.ex` | Event broadcasting |
| `lib/jido_code/assistant/runner.ex` | Backend behaviour |
| `lib/jido_code/assistant/runners/react.ex` | ReActAgent runner |
| `lib/jido_code/assistant/runners/claude_code.ex` | Claude Code CLI runner |
| `lib/jido_code/assistant/resources/session.ex` | Ash persistence |
| `lib/jido_code/assistant/resources/message.ex` | Ash persistence |
| `lib/jido_code/tools/registry.ex` | Tool discovery |
| `lib/jido_code/tools/executor.ex` | Tool execution |
| `lib/jido_code/tools/policies.ex` | Security layer |
| `lib/jido_code/tools/file/*.ex` | File tools |
| `lib/jido_code/tools/shell.ex` | Shell tool |
| `lib/jido_code/tools/git.ex` | Git tools |
| `lib/jido_code/settings.ex` | Settings management |
| `lib/jido_code/assistant/commands/parser.ex` | Command parsing |
| `lib/jido_code/assistant/commands/router.ex` | Command routing |
| `lib/jido_code_web/live/assistant_live/index.ex` | Session list UI |
| `lib/jido_code_web/live/assistant_live/show.ex` | Chat UI |

### Files to Modify
| File | Changes |
|-------|---------|
| `lib/jido_code/application.ex` | Add supervisor children |
| `lib/jido_code_web/router.ex` | Add assistant routes |
| `config/runtime.exs` | Add assistant config |

---

## Testing Strategy

1. **Unit tests** for each Runner implementation
2. **Integration tests** for Session lifecycle
3. **Tool tests** with mock filesystem
4. **LiveView tests** following existing ChatLive patterns

---

## Implementation Order

1. **Phase 1**: Manager + Session + PubSub + Ash resources
2. **Phase 2**: ReAct runner + streaming
3. **Phase 3**: Tool system (file first, then shell/git)
4. **Phase 4**: Settings + slash commands
5. **Phase 5**: LiveView UI with proper streaming
