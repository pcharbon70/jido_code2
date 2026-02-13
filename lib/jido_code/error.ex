defmodule JidoCode.Error do
  @moduledoc """
  Centralized error handling for JidoCode using Splode.

  Error classes are for classification; concrete `...Error` structs are for raising/matching.

  ## Error Classes

  - `:invalid` - Invalid input or validation errors
  - `:execution` - Runtime execution failures
  - `:config` - Configuration errors
  - `:internal` - Internal/unexpected errors

  ## Usage

      # Using helper functions
      JidoCode.Error.validation_error("Email is required", %{field: :email})
      JidoCode.Error.execution_error("Failed to process request", %{reason: :timeout})

      # Raising errors
      raise JidoCode.Error.InvalidInputError, message: "Invalid email format", field: :email
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
      @moduledoc "Unknown/unexpected error."
      use Splode.Error, class: :internal

      def message(%{error: error}) do
        "Unknown error: #{inspect(error)}"
      end
    end
  end

  # Concrete exception structs – raise/rescue these
  defmodule InvalidInputError do
    @moduledoc "Error for invalid input parameters."
    use Splode.Error, class: :invalid

    def message(%{message: message}), do: message
  end

  defmodule ValidationError do
    @moduledoc "Error for validation failures."
    use Splode.Error, class: :invalid

    def message(%{message: message, field: field}) when not is_nil(field) do
      "Validation failed for #{field}: #{message}"
    end

    def message(%{message: message}), do: message
  end

  defmodule ExecutionFailureError do
    @moduledoc "Error for runtime execution failures."
    use Splode.Error, class: :execution

    def message(%{message: message}), do: message
  end

  defmodule ConfigurationError do
    @moduledoc "Error for configuration issues."
    use Splode.Error, class: :config

    def message(%{message: message}), do: message
  end

  # Helper functions

  @doc "Creates a validation error with optional details."
  @spec validation_error(String.t(), map()) :: Exception.t()
  def validation_error(message, details \\ %{}) do
    ValidationError.exception(details_to_opts(message, details))
  end

  @doc "Creates an invalid input error."
  @spec invalid_input_error(String.t(), map()) :: Exception.t()
  def invalid_input_error(message, details \\ %{}) do
    InvalidInputError.exception(details_to_opts(message, details))
  end

  @doc "Creates an execution failure error."
  @spec execution_error(String.t(), map()) :: Exception.t()
  def execution_error(message, details \\ %{}) do
    ExecutionFailureError.exception(details_to_opts(message, details))
  end

  @doc "Creates a configuration error."
  @spec config_error(String.t(), map()) :: Exception.t()
  def config_error(message, details \\ %{}) do
    ConfigurationError.exception(details_to_opts(message, details))
  end

  defp details_to_opts(message, details) when is_map(details) do
    Keyword.merge([message: message], Map.to_list(details))
  end
end
