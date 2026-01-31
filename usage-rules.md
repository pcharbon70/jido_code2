# AgentJido Usage Rules for LLMs

This document provides usage rules for AI assistants working with this codebase.

## Project Overview

AgentJido is a Phoenix 1.8 application in the Jido AI agent ecosystem. It uses:

- **Phoenix 1.8** with LiveView
- **Ash Framework** for data modeling and authentication
- **PostgreSQL** for persistence
- **Tailwind CSS v4** for styling

## Key Commands

```bash
# Setup
mix setup                    # Full setup including DB and assets

# Development
mix phx.server              # Start the server
iex -S mix phx.server       # Start with IEx

# Quality
mix quality                 # Run all quality checks
mix precommit               # Pre-commit checks (compile, format, test)

# Testing
mix test                    # Run tests
mix coveralls.html          # Tests with coverage report

# Database
mix ash.setup               # Setup Ash resources
mix ecto.migrate            # Run migrations
mix ecto.reset              # Reset database
```

## Architecture

### Directory Structure

```
lib/
├── agent_jido/              # Core business logic
│   ├── accounts.ex          # Ash resource domain
│   ├── error.ex             # Centralized error handling (Splode)
│   └── repo.ex              # Ecto repository
├── agent_jido_web/          # Web layer
│   ├── components/          # Phoenix components
│   ├── controllers/         # Controllers
│   └── live/                # LiveView modules
└── agent_jido.ex            # Application entry
```

### Error Handling

Use `AgentJido.Error` for all error handling:

```elixir
# Creating errors
AgentJido.Error.validation_error("Invalid email", %{field: :email})
AgentJido.Error.execution_error("Request failed", %{reason: :timeout})

# Raising errors
raise AgentJido.Error.InvalidInputError, message: "Bad input"
```

## Code Conventions

1. **Phoenix 1.8 patterns** - Use `<Layouts.app>` wrapper, `<.form>` component
2. **LiveView streams** - Use for all collections
3. **Ash resources** - Define in domain modules under `lib/agent_jido/`
4. **Components** - Use `core_components.ex` imports when available
5. **Error handling** - Use Splode via `AgentJido.Error`

## Testing

- Use `Phoenix.LiveViewTest` for LiveView tests
- Use `LazyHTML` for HTML assertions
- Always add DOM IDs to key elements for testing
- Run `mix test --failed` for re-running failed tests

## Quality Standards

All code must pass:
- `mix compile --warnings-as-errors`
- `mix format --check-formatted`
- `mix credo --strict`
- `mix doctor --raise`
