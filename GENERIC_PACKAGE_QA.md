# Jido Ecosystem Package Quality Standards

This document defines the quality standards for all public OSS packages in the Jido ecosystem. These patterns are derived from `req_llm`, `llm_db`, `jido_action`, and `jido_signal`.

All packages MUST:

- Support **Elixir `~> 1.18`** as the baseline.
- Follow the conventions in this document unless there is a strong, documented reason not to.

---

## Package Structure

### Required Files

```text
my_package/
├── .github/
│   └── workflows/
│       ├── ci.yml              # Lint + test matrix
│       └── release.yml         # Hex publish workflow
├── config/
│   ├── config.exs              # Base configuration
│   ├── dev.exs                 # Development overrides
│   └── test.exs                # Test overrides
├── guides/                     # Optional: Additional documentation
│   └── getting-started.md
├── lib/
│   └── my_package.ex
├── test/
│   ├── support/                # Test helpers, fixtures
│   └── my_package_test.exs
├── .formatter.exs              # Formatter configuration
├── .gitignore
├── AGENTS.md                   # AI agent instructions
├── CHANGELOG.md                # Conventional changelog
├── CONTRIBUTING.md             # Contribution guidelines
├── LICENSE                     # Apache-2.0 or MIT
├── mix.exs
├── mix.lock
├── README.md
└── usage-rules.md              # LLM usage rules (for Cursor/etc)
```

---

## Standard Ecosystem Modules

All ecosystem packages should use shared building blocks consistently.

### Zoi Schemas (Canonical Validation)

Use **Zoi** as the canonical schema + struct validation library.

#### Pattern

```elixir
defmodule MyPackage.Model do
  @moduledoc """
  Brief description of what this model represents.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(),
              name: Zoi.string() |> Zoi.nullish(),
              tags: Zoi.array(Zoi.string()) |> Zoi.default([])
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for this struct."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Builds a new struct from a map, validating with Zoi."
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs), do: Zoi.parse(@schema, attrs)

  @doc "Like new/1 but raises on validation errors."
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, value} -> value
      {:error, reason} -> raise ArgumentError, "Invalid #{inspect(__MODULE__)}: #{inspect(reason)}"
    end
  end
end
```

#### Zoi Checklist

- [ ] Core structs define a `@schema` using `Zoi.struct(__MODULE__, ...)`.
- [ ] `@type t :: unquote(Zoi.type_spec(@schema))` is present.
- [ ] `@enforce_keys` and `defstruct` are derived via `Zoi.Struct`.
- [ ] `schema/0`, `new/1`, and (optionally) `new!/1` are defined.
- [ ] Validation logic is in the Zoi schema, not scattered across callers.

---

### Splode Errors (Tight, Project-Relevant Types)

Use **Splode** for error composition and classification. Keep error types **tight and specific to the package**.

#### Pattern

```elixir
defmodule MyPackage.Error do
  @moduledoc """
  Centralized error handling for MyPackage using Splode.

  Error classes are for classification; concrete `...Error` structs are for raising/matching.
  """

  use Splode,
    error_classes: [
      invalid: Invalid,
      execution: Execution,
      config: Config,
      internal: Internal
    ],
    unknown_error: __MODULE__.Internal.UnknownError

  # Error classes – classification only
  defmodule Invalid do
    @moduledoc "Invalid input error class for Splode."
    use Splode.ErrorClass, class: :invalid
  end

  defmodule Execution do
    @moduledoc "Execution error class for Splode."
    use Splode.ErrorClass, class: :execution
  end

  defmodule Config do
    @moduledoc "Configuration error class for Splode."
    use Splode.ErrorClass, class: :config
  end

  defmodule Internal do
    @moduledoc "Internal error class for Splode."
    use Splode.ErrorClass, class: :internal

    defmodule UnknownError do
      @moduledoc false
      defexception [:message, :details]
    end
  end

  # Concrete exception structs – raise/rescue these
  defmodule InvalidInputError do
    @moduledoc "Error for invalid input parameters."
    defexception [:message, :field, :value, :details]
  end

  defmodule ExecutionFailureError do
    @moduledoc "Error for runtime execution failures."
    defexception [:message, :details]
  end

  # Helper functions
  @spec validation_error(String.t(), map()) :: InvalidInputError.t()
  def validation_error(message, details \\ %{}) do
    InvalidInputError.exception(Keyword.merge([message: message], Map.to_list(details)))
  end

  @spec execution_error(String.t(), map()) :: ExecutionFailureError.t()
  def execution_error(message, details \\ %{}) do
    ExecutionFailureError.exception(message: message, details: details)
  end
end
```

#### Splode Checklist

- [ ] Single `MyPackage.Error` module exists.
- [ ] Uses **a small set of error classes** (e.g. `:invalid`, `:execution`, `:config`, `:internal`).
- [ ] Concrete exception structs end in `Error` and are **package-specific**.
- [ ] Helpers like `validation_error/2`, `config_error/2` exist for common errors.
- [ ] External errors are normalized to `MyPackage.Error` types.

---

### Igniter Installs

Use **Igniter** to provide a consistent install experience for packages that need configuration, files, or scaffolding.

#### Pattern

- Expose an installer module (e.g. `MyPackage.Igniter`) following patterns from other Jido packages.
- Document in `README.md`:

```markdown
## Installation via Igniter

```bash
mix igniter.install my_package
```
```

#### Igniter Checklist

- [ ] Non-trivial packages provide an Igniter installer module.
- [ ] Install steps (config, files, migrations) are handled via Igniter.
- [ ] `README.md` includes "Installation via Igniter" section if supported.

---

### Documentation Coverage (`mix doctor`)

Use **`mix doctor`** to enforce documentation coverage consistently.

#### Doctor Checklist

- [ ] `doctor` is listed in dev deps.
- [ ] `mix doctor --raise` runs in `mix quality` and CI.
- [ ] Public APIs are documented; `@moduledoc false` is used intentionally for internals.

---

## mix.exs Configuration

### Standard Project Configuration

```elixir
defmodule MyPackage.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/agentjido/my_package"
  @description "Brief description of the package"

  def project do
    [
      app: :my_package,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),

      # Documentation
      name: "My Package",
      description: @description,
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs(),

      # Test Coverage
      test_coverage: [
        tool: ExCoveralls,
        summary: [threshold: 90]
      ],

      # Dialyzer
      dialyzer: [
        plt_local_path: "priv/plts/project.plt",
        plt_core_path: "priv/plts/core.plt"
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.github": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Runtime
      {:jason, "~> 1.4"},
      {:zoi, "~> 0.14"},
      {:splode, "~> 0.2"},

      # Dev/Test
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test]},
      {:doctor, "~> 0.21", only: :dev, runtime: false},
      {:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false},
      {:git_ops, "~> 2.9", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "git_hooks.install"],
      test: "test --exclude flaky",
      q: ["quality"],
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --min-priority higher",
        "dialyzer",
        "doctor --raise"
      ]
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE", "CHANGELOG.md", "usage-rules.md"],
      maintainers: ["Your Name"],
      licenses: ["Apache-2.0"],
      links: %{
        "Changelog" => "https://hexdocs.pm/my_package/changelog.html",
        "Discord" => "https://agentjido.xyz/discord",
        "Documentation" => "https://hexdocs.pm/my_package",
        "GitHub" => @source_url,
        "Website" => "https://agentjido.xyz"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "CONTRIBUTING.md"
      ]
    ]
  end
end
```

---

## Quality Checks

### The `mix quality` Alias

All packages MUST define a `quality` alias that runs:

```elixir
quality: [
  "format --check-formatted",      # Code formatting
  "compile --warnings-as-errors",  # No compiler warnings
  "credo --min-priority higher",   # Linting
  "dialyzer",                      # Type checking
  "doctor --raise"                 # Documentation coverage
]
```

### Running Quality Checks

```bash
mix quality   # or mix q

# Individual checks
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --min-priority higher
mix dialyzer
mix doctor --raise
```

---

## Testing Standards

### Coverage Requirements

- **Minimum threshold**: 90% line coverage
- **Tool**: ExCoveralls
- **CI enforcement**: Coverage check in GitHub Actions

### Test Configuration

```elixir
test_coverage: [
  tool: ExCoveralls,
  summary: [threshold: 90],
  export: "cov",
  ignore_modules: [~r/^MyPackageTest\./]
]
```

### Running Tests

```bash
mix test                    # Run tests (excludes flaky)
mix coveralls               # Run with coverage
mix coveralls.html          # Generate HTML report
mix test --include flaky    # Include all tests
```

### Test Organization

```text
test/
├── support/
│   ├── fixtures.ex         # Test fixtures
│   ├── helpers.ex          # Test helper functions
│   └── case.ex             # Custom ExUnit case modules
├── my_package_test.exs     # High-level API tests
└── my_package/
    ├── module_a_test.exs   # Unit tests for ModuleA
    └── module_b_test.exs   # Unit tests for ModuleB
```

---

## Conventional Commits

| Type | Description |
|------|-------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation changes |
| `style` | Formatting, no code change |
| `refactor` | Code change, no fix or feature |
| `perf` | Performance improvement |
| `test` | Adding/fixing tests |
| `chore` | Maintenance, deps, tooling |
| `ci` | CI/CD changes |

**Examples:**

```bash
git commit -m "feat(schema): add validation for email fields"
git commit -m "fix: resolve timeout in async operations"
git commit -m "feat!: breaking change to API"
```

---

## Documentation Standards

### Module Documentation

```elixir
defmodule MyPackage.Core do
  @moduledoc """
  Core functionality for MyPackage.

  ## Overview

  Brief description of what this module does.

  ## Examples

      iex> MyPackage.Core.do_thing(:input)
      {:ok, :result}
  """

  @doc """
  Does a specific thing.

  ## Parameters

    * `input` - Description of input
    * `opts` - Keyword list of options
      * `:timeout` - Timeout in milliseconds (default: 5000)

  ## Returns

    * `{:ok, result}` - On success
    * `{:error, reason}` - On failure
  """
  @spec do_thing(atom(), keyword()) :: {:ok, term()} | {:error, term()}
  def do_thing(input, opts \\ [])
end
```

### Required Documentation Files

| File | Purpose |
|------|---------|
| `README.md` | Overview, installation (incl. Igniter if relevant), quick start |
| `CHANGELOG.md` | Version history (conventional changelog) |
| `CONTRIBUTING.md` | How to contribute |
| `AGENTS.md` | AI agent instructions |
| `usage-rules.md` | LLM usage rules |
| `LICENSE` | License text |

---

## Gitignore Configuration

### Standard `.gitignore`

```text
# Build artifacts
/_build/
/deps/

# Coverage
/cover/

# Dialyzer PLT files - do NOT commit these
/priv/plts/
*.plt
*.plt.hash

# Editor/IDE
.elixir_ls/
.vscode/
*.swp
*.swo

# Generated files
/doc/
erl_crash.dump

# OS
.DS_Store
Thumbs.db
```

---

## Formatter Configuration

### Standard `.formatter.exs`

```elixir
[
  inputs: [
    "{mix,.formatter,.credo}.exs",
    "{config,lib,test}/**/*.{ex,exs}"
  ],
  line_length: 120
]
```

---

## Dependencies

### Standard Dev/Test Dependencies

```elixir
# Linting & Static Analysis
{:credo, "~> 1.7", only: [:dev, :test], runtime: false},
{:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},

# Documentation
{:ex_doc, "~> 0.31", only: :dev, runtime: false},
{:doctor, "~> 0.21", only: :dev, runtime: false},

# Test Coverage
{:excoveralls, "~> 0.18", only: [:dev, :test]},

# Git Tooling
{:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false},
{:git_ops, "~> 2.9", only: :dev, runtime: false},

# Optional
{:quokka, "~> 2.10", only: [:dev, :test], runtime: false},  # Advanced formatting
{:stream_data, "~> 1.0", only: [:dev, :test]},              # Property testing
{:mimic, "~> 2.0", only: :test}                             # Mocking
```

### Common Runtime Dependencies

```elixir
{:zoi, "~> 0.14"}              # Canonical schema validation
{:splode, "~> 0.2"}            # Canonical error composition
{:jason, "~> 1.4"}             # JSON
{:uniq, "~> 0.6"}              # UUID generation
```

### Deprecated Dependencies (Replace with Zoi)

The following should be migrated to Zoi when encountered in existing code:

- `nimble_options` → Use Zoi schemas for option validation
- `typedstruct` / `typed_struct` → Use `Zoi.struct/3` pattern (see above)

### IMPORTANT: No jido_dep Helper Functions

**DO NOT use `jido_dep/4` or similar helper functions in mix.exs files.** This pattern causes dependency resolution conflicts and should be removed when encountered.

Instead, use plain direct dependencies:

```elixir
defp deps do
  [
    # Jido ecosystem - use Hex versions directly
    {:jido, "~> 2.0.0-rc.2"},
    {:jido_action, "~> 2.0.0-rc.2"},
    {:jido_signal, "~> 2.0.0-rc.2"},
    
    # For unpublished deps, use github
    {:req_llm, github: "agentjido/req_llm", branch: "main"},
    
    # Runtime deps
    {:jason, "~> 1.4"},
    {:zoi, "~> 0.16"},
    {:splode, "~> 0.3.0"},
    
    # Dev/Test
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    # ...
  ]
end
```

This approach:
- Works reliably for both workspace and external developers
- Avoids dependency conflict errors from `override: true` clashes
- Simplifies mix.exs files
- Works correctly with `mix hex.publish`

---

## Checklist for New Packages

### Before First Commit

- [ ] `mix.exs` follows standard configuration (Elixir `~> 1.18`).
- [ ] `quality` alias defined (includes `doctor --raise`).
- [ ] `.formatter.exs` configured.
- [ ] `.gitignore` includes `_build/`, `deps/`, `cover/`, `priv/plts/`, `*.plt`, `.elixir_ls/`.
- [ ] `README.md` with installation (Hex + Igniter if applicable) and quick start.
- [ ] `LICENSE` file present.
- [ ] `AGENTS.md` for AI agent instructions.
- [ ] `MyPackage.Error` module using Splode is defined (for non-trivial libs).
- [ ] Core structs use Zoi schema pattern.

### Before First Release

- [ ] `mix quality` passes.
- [ ] `mix test` passes with >90% coverage.
- [ ] `mix docs` builds without errors.
- [ ] `mix doctor --raise` passes.
- [ ] `CHANGELOG.md` has initial entry.
- [ ] `CONTRIBUTING.md` describes workflow.
- [ ] GitHub Actions CI configured.
- [ ] Release workflow configured.
- [ ] Hex.pm package metadata complete.
- [ ] Igniter installer documented (if provided).

### Ongoing Maintenance

- [ ] All PRs pass CI.
- [ ] Coverage maintained above threshold.
- [ ] Documentation coverage maintained (doctor).
- [ ] Conventional commits enforced.
- [ ] CHANGELOG updated on releases.
- [ ] Dependencies kept up to date.
- [ ] Security advisories addressed promptly.

---

## Quick Reference

```bash
mix setup              # Setup dev environment
mix quality            # Run all quality checks
mix coveralls.html     # Run tests with coverage report
mix docs               # Generate documentation
mix doctor --raise     # Check documentation coverage
mix git_ops.check_message  # Check commit message format
mix git_ops.release    # Create a release
git push && git push --tags
```
