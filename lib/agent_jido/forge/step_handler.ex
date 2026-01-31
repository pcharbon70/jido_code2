defmodule AgentJido.Forge.StepHandler do
  @moduledoc """
  Behavior for custom workflow step handlers.

  Implement this for complex logic that can't be expressed in data.
  """

  @type sprite_client :: term()
  @type args :: map()
  @type opts :: keyword()

  @type execute_result ::
          {:ok, map()}
          | {:needs_input, String.t()}
          | {:error, term()}

  @callback execute(sprite_client, args, opts) :: execute_result()
end
