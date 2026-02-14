defmodule JidoCode.WorkflowRuntime.StepHandlers.CommitAndPR do
  @moduledoc """
  Handles the `CommitAndPR` shipping step branch setup and pre-ship policy phases.

  This MVP implementation derives deterministic run branch names using
  `jidocode/<workflow>/<short-run-id>`, attempts branch setup, and returns
  structured artifacts for downstream commit/push/PR phases.
  """

  @behaviour JidoCode.Forge.StepHandler

  @branch_pattern "jidocode/<workflow>/<short-run-id>"
  @branch_prefix "jidocode"
  @workflow_segment_fallback "workflow"
  @run_segment_fallback "run"
  @max_workflow_segment_length 32
  @max_short_run_id_length 24
  @hash_suffix_length 8
  @branch_collision_retry_suffix_length 8
  @branch_collision_retry_prefix "retry"
  @branch_collision_retry_limit 1
  @branch_collision_retry_strategy "deterministic_hash_suffix"
  @branch_collision_reason_fragments [
    "already exists",
    "already_exists",
    "branch exists",
    "branch_exists",
    "branch collision",
    "branch_collision",
    "reference already exists",
    "reference_exists",
    "remote branch exists",
    "remote_branch_exists",
    "name already in use"
  ]

  @branch_setup_error_type "workflow_commit_and_pr_branch_setup_failed"
  @branch_setup_operation "setup_run_branch"
  @branch_setup_remediation "Resolve branch creation preconditions and retry CommitAndPR shipping."
  @workspace_policy_error_type "workflow_commit_and_pr_workspace_policy_failed"
  @workspace_policy_operation "validate_workspace_cleanliness"
  @workspace_policy_stage "pre_ship_workspace_policy"
  @workspace_policy_remediation """
  Clean or discard unintended workspace changes, then retry CommitAndPR shipping.
  """
  @workspace_policy_check_id "workspace_cleanliness"
  @workspace_policy_check_name "Workspace cleanliness policy check"
  @workspace_policy_mode "clean_room"
  @required_workspace_state "clean"
  @secret_scan_policy_error_type "workflow_commit_and_pr_secret_scan_policy_failed"
  @secret_scan_policy_operation "validate_secret_scan"
  @secret_scan_policy_stage "pre_ship_secret_scan_policy"
  @secret_scan_policy_remediation """
  Remove detected secrets or restore secret-scan tooling health, then retry CommitAndPR shipping.
  """
  @secret_scan_check_id "secret_scan"
  @secret_scan_check_name "Secret scan policy check"
  @secret_scan_clean_state "clean"
  @secret_scan_violation_state "violations_detected"
  @secret_scan_tooling_error_state "tooling_error"
  @diff_size_policy_error_type "workflow_commit_and_pr_diff_size_policy_failed"
  @diff_size_policy_operation "validate_diff_size_threshold"
  @diff_size_policy_stage "pre_ship_diff_size_policy"
  @diff_size_policy_remediation """
  Split the change set into smaller commits or request explicit policy override, then retry CommitAndPR shipping.
  """
  @diff_size_check_id "diff_size_threshold"
  @diff_size_check_name "Diff size threshold policy check"
  @default_diff_max_changed_lines 800
  @blocked_shipping_actions ["commit", "push", "create_pr"]

  @impl true
  def execute(_sprite_client, args, opts) when is_map(args) and is_list(opts) do
    with {:ok, branch_context} <- derive_branch_context(args),
         {:ok, %{branch_context: resolved_branch_context, branch_setup: branch_setup}} <-
           setup_branch(branch_context, opts),
         {:ok, workspace_policy_check} <-
           validate_workspace_cleanliness(args, resolved_branch_context),
         {:ok, secret_scan_policy_check} <-
           validate_secret_scan(args, resolved_branch_context, opts),
         {:ok, diff_size_policy_check} <-
           validate_diff_size_threshold(args, resolved_branch_context, opts) do
      maybe_probe_commit(resolved_branch_context, opts)

      {:ok,
       %{
         run_artifacts: %{
           branch_name: Map.fetch!(resolved_branch_context, :branch_name),
           branch_derivation: Map.fetch!(resolved_branch_context, :branch_derivation),
           collision_handling: branch_setup |> map_get(:collision_handling, "collision_handling") |> normalize_map(),
           policy_checks: %{
             workspace_cleanliness: workspace_policy_check,
             secret_scan: secret_scan_policy_check,
             diff_size_threshold: diff_size_policy_check
           }
         },
         branch_setup: branch_setup,
         policy_checks: %{
           workspace_cleanliness: workspace_policy_check,
           secret_scan: secret_scan_policy_check,
           diff_size_threshold: diff_size_policy_check
         },
         shipping_flow: %{
           completed_stage: "diff_size_policy_check",
           next_stage: "commit_changes"
         }
       }}
    end
  end

  def execute(_sprite_client, _args, _opts) do
    {:error,
     branch_setup_error(
       "invalid_arguments",
       "CommitAndPR shipping step requires map args.",
       nil
     )}
  end

  @doc false
  @spec default_branch_setup_runner(map()) :: {:ok, map()}
  def default_branch_setup_runner(branch_context) when is_map(branch_context) do
    {:ok,
     %{
       status: "created",
       adapter: "default_noop",
       command_intent: "git checkout -b #{Map.get(branch_context, :branch_name)}"
     }}
  end

  defp derive_branch_context(args) when is_map(args) do
    workflow_name =
      args |> map_get(:workflow_name, "workflow_name") |> normalize_optional_string()

    run_id = args |> map_get(:run_id, "run_id") |> normalize_optional_string()

    cond do
      is_nil(workflow_name) ->
        {:error,
         branch_setup_error(
           "workflow_name_missing",
           "CommitAndPR branch derivation requires workflow_name metadata.",
           nil
         )}

      is_nil(run_id) ->
        {:error,
         branch_setup_error(
           "run_id_missing",
           "CommitAndPR branch derivation requires run_id metadata.",
           nil
         )}

      true ->
        {workflow_segment, workflow_segment_strategy} =
          normalize_branch_segment(
            workflow_name,
            @workflow_segment_fallback,
            @max_workflow_segment_length
          )

        {short_run_id, short_run_id_strategy} =
          normalize_branch_segment(run_id, @run_segment_fallback, @max_short_run_id_length)

        branch_name = "#{@branch_prefix}/#{workflow_segment}/#{short_run_id}"

        {:ok,
         %{
           branch_name: branch_name,
           branch_derivation: %{
             pattern: @branch_pattern,
             workflow_name: workflow_name,
             workflow_segment: workflow_segment,
             workflow_segment_strategy: workflow_segment_strategy,
             run_id: run_id,
             short_run_id: short_run_id,
             short_run_id_strategy: short_run_id_strategy
           }
         }}
    end
  end

  defp derive_branch_context(_args) do
    {:error,
     branch_setup_error(
       "invalid_arguments",
       "CommitAndPR branch derivation requires map args.",
       nil
     )}
  end

  defp setup_branch(branch_context, opts) when is_map(branch_context) and is_list(opts) do
    branch_setup_runner =
      Keyword.get(opts, :branch_setup_runner, &__MODULE__.default_branch_setup_runner/1)

    if is_function(branch_setup_runner, 1) do
      safe_invoke_branch_setup_runner(branch_setup_runner, branch_context)
    else
      {:error,
       branch_setup_error(
         "branch_setup_runner_invalid",
         "CommitAndPR branch setup runner configuration is invalid.",
         branch_context
       )}
    end
  end

  defp setup_branch(branch_context, _opts) do
    {:error,
     branch_setup_error(
       "branch_setup_runner_invalid",
       "CommitAndPR branch setup runner configuration is invalid.",
       branch_context
     )}
  end

  defp safe_invoke_branch_setup_runner(branch_setup_runner, branch_context)
       when is_function(branch_setup_runner, 1) and is_map(branch_context) do
    case invoke_branch_setup_runner(branch_setup_runner, branch_context) do
      {:ok, branch_setup} ->
        {:ok, %{branch_context: branch_context, branch_setup: branch_setup}}

      {:error, first_failure} ->
        maybe_retry_branch_collision(
          branch_setup_runner,
          branch_context,
          normalize_map(first_failure)
        )
    end
  end

  defp maybe_retry_branch_collision(branch_setup_runner, branch_context, first_failure)
       when is_function(branch_setup_runner, 1) and is_map(branch_context) and
              is_map(first_failure) do
    first_failure_reason = map_get(first_failure, :reason, "reason")

    if branch_collision_reason?(first_failure_reason) do
      retry_branch_context = build_collision_retry_branch_context(branch_context, first_failure)

      case invoke_branch_setup_runner(branch_setup_runner, retry_branch_context) do
        {:ok, retry_branch_setup} ->
          {:ok,
           %{
             branch_context: retry_branch_context,
             branch_setup:
               merge_collision_retry_success(
                 retry_branch_setup,
                 branch_context,
                 retry_branch_context,
                 first_failure
               )
           }}

        {:error, retry_failure} ->
          {:error,
           branch_collision_retry_error(
             branch_context,
             retry_branch_context,
             first_failure,
             normalize_map(retry_failure)
           )}
      end
    else
      {:error,
       branch_setup_error(
         map_get(first_failure, :reason_type, "reason_type", "branch_setup_failed"),
         map_get(
           first_failure,
           :detail,
           "detail",
           "Run branch creation failed and shipping halted before commit."
         ),
         branch_context,
         first_failure_reason
       )}
    end
  end

  defp maybe_retry_branch_collision(_branch_setup_runner, branch_context, first_failure) do
    {:error,
     branch_setup_error(
       map_get(first_failure, :reason_type, "reason_type", "branch_setup_failed"),
       map_get(
         first_failure,
         :detail,
         "detail",
         "Run branch creation failed and shipping halted before commit."
       ),
       branch_context,
       map_get(first_failure, :reason, "reason")
     )}
  end

  defp invoke_branch_setup_runner(branch_setup_runner, branch_context)
       when is_function(branch_setup_runner, 1) and is_map(branch_context) do
    try do
      case branch_setup_runner.(branch_context) do
        :ok ->
          {:ok, %{status: "created"}}

        {:ok, result} when is_map(result) ->
          {:ok, result}

        {:ok, result} ->
          {:ok, %{status: "created", detail: "Branch setup runner returned #{inspect(result)}."}}

        {:error, reason} ->
          {:error,
           %{
             reason_type: "branch_setup_failed",
             detail: "Run branch creation failed and shipping halted before commit.",
             reason: reason
           }}

        other ->
          {:error,
           %{
             reason_type: "branch_setup_invalid_result",
             detail: "Branch setup runner returned an invalid result (#{inspect(other)}).",
             reason: other
           }}
      end
    rescue
      exception ->
        {:error,
         %{
           reason_type: "branch_setup_runner_crashed",
           detail: "Branch setup runner crashed (#{Exception.message(exception)}).",
           reason: exception
         }}
    catch
      kind, reason ->
        {:error,
         %{
           reason_type: "branch_setup_runner_threw",
           detail: "Branch setup runner threw #{inspect({kind, reason})}.",
           reason: {kind, reason}
         }}
    end
  end

  defp build_collision_retry_branch_context(branch_context, first_failure)
       when is_map(branch_context) and is_map(first_failure) do
    source_branch_name =
      branch_context |> map_get(:branch_name, "branch_name") |> normalize_optional_string()

    retry_suffix = branch_collision_retry_suffix(source_branch_name)
    retry_branch_name = build_collision_retry_branch_name(source_branch_name, retry_suffix)

    branch_derivation =
      branch_context
      |> map_get(:branch_derivation, "branch_derivation")
      |> normalize_map()
      |> Map.put(:collision_retry_strategy, @branch_collision_retry_strategy)
      |> Map.put(:collision_retry_suffix, retry_suffix)
      |> Map.put(:collision_source_branch_name, source_branch_name)
      |> Map.put(:collision_retry_branch_name, retry_branch_name)
      |> Map.put(:collision_retry_attempt, 1)

    collision_handling =
      collision_handling_context(
        source_branch_name,
        retry_branch_name,
        first_failure,
        nil
      )

    branch_context
    |> Map.put(:branch_name, retry_branch_name)
    |> Map.put(:branch_derivation, branch_derivation)
    |> Map.put(:collision_handling, collision_handling)
  end

  defp build_collision_retry_branch_context(branch_context, _first_failure), do: branch_context

  defp merge_collision_retry_success(
         retry_branch_setup,
         branch_context,
         retry_branch_context,
         first_failure
       )
       when is_map(retry_branch_context) and is_map(first_failure) do
    source_branch_name =
      branch_context |> map_get(:branch_name, "branch_name") |> normalize_optional_string()

    retry_branch_name =
      retry_branch_context |> map_get(:branch_name, "branch_name") |> normalize_optional_string()

    retry_branch_setup
    |> normalize_map()
    |> Map.put(:status, "created_after_collision_retry")
    |> Map.put(:branch_name, retry_branch_name)
    |> Map.put(
      :collision_handling,
      collision_handling_context(source_branch_name, retry_branch_name, first_failure, nil)
    )
  end

  defp merge_collision_retry_success(
         retry_branch_setup,
         _branch_context,
         _retry_branch_context,
         _first_failure
       ),
       do: normalize_map(retry_branch_setup)

  defp branch_collision_retry_error(
         branch_context,
         retry_branch_context,
         first_failure,
         retry_failure
       )
       when is_map(branch_context) and is_map(retry_branch_context) and is_map(first_failure) and
              is_map(retry_failure) do
    source_branch_name =
      branch_context |> map_get(:branch_name, "branch_name") |> normalize_optional_string()

    retry_branch_name =
      retry_branch_context |> map_get(:branch_name, "branch_name") |> normalize_optional_string()

    retry_reason = map_get(retry_failure, :reason, "reason")

    branch_setup_error(
      "branch_collision_retry_failed",
      "Run branch collision retry failed and shipping halted before commit.",
      retry_branch_context,
      retry_reason
    )
    |> Map.merge(%{
      collision_handling:
        collision_handling_context(
          source_branch_name,
          retry_branch_name,
          first_failure,
          retry_failure
        ),
      source_branch_name: source_branch_name,
      retry_branch_name: retry_branch_name
    })
  end

  defp branch_collision_reason?(reason) do
    reason
    |> collision_reason_fragments()
    |> Enum.any?(fn fragment ->
      Enum.any?(@branch_collision_reason_fragments, &String.contains?(fragment, &1))
    end)
  end

  defp collision_reason_fragments(reason) when is_map(reason) do
    [
      map_get(reason, :reason_type, "reason_type"),
      map_get(reason, :error_type, "error_type"),
      map_get(reason, :detail, "detail"),
      map_get(reason, :message, "message"),
      map_get(reason, :reason, "reason")
    ]
    |> Enum.flat_map(&collision_reason_fragments/1)
  end

  defp collision_reason_fragments(reason) when is_tuple(reason) do
    reason |> Tuple.to_list() |> Enum.flat_map(&collision_reason_fragments/1)
  end

  defp collision_reason_fragments(reason) when is_list(reason),
    do: Enum.flat_map(reason, &collision_reason_fragments/1)

  defp collision_reason_fragments(reason) when is_atom(reason) do
    reason |> Atom.to_string() |> collision_reason_fragments()
  end

  defp collision_reason_fragments(reason) when is_binary(reason) do
    [String.downcase(reason)]
  end

  defp collision_reason_fragments(reason) do
    case normalize_optional_string(format_failure_reason(reason)) do
      nil -> []
      formatted_reason -> [String.downcase(formatted_reason)]
    end
  rescue
    _exception -> []
  end

  defp branch_collision_retry_suffix(branch_name)
       when is_binary(branch_name) and branch_name != "" do
    hash =
      "collision:#{branch_name}"
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
      |> String.slice(0, @branch_collision_retry_suffix_length)

    "#{@branch_collision_retry_prefix}-#{hash}"
  end

  defp branch_collision_retry_suffix(_branch_name) do
    random_fallback =
      "collision:fallback"
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
      |> String.slice(0, @branch_collision_retry_suffix_length)

    "#{@branch_collision_retry_prefix}-#{random_fallback}"
  end

  defp build_collision_retry_branch_name(source_branch_name, retry_suffix)
       when is_binary(source_branch_name) and source_branch_name != "" and is_binary(retry_suffix) and
              retry_suffix != "" do
    "#{source_branch_name}-#{retry_suffix}"
  end

  defp build_collision_retry_branch_name(source_branch_name, _retry_suffix),
    do: source_branch_name

  defp collision_handling_context(
         source_branch_name,
         retry_branch_name,
         first_failure,
         retry_failure
       )
       when is_map(first_failure) do
    %{
      collision_detected: true,
      strategy: @branch_collision_retry_strategy,
      retry_limit: @branch_collision_retry_limit,
      retry_attempted: true,
      source_branch_name: source_branch_name,
      retry_branch_name: retry_branch_name,
      overwrite_existing_remote: false,
      force_push: false,
      initial_reason_type: first_failure |> map_get(:reason_type, "reason_type") |> normalize_reason_type(),
      initial_reason: first_failure |> map_get(:reason, "reason") |> format_failure_reason()
    }
    |> maybe_add_retry_failure_context(retry_failure)
  end

  defp collision_handling_context(
         source_branch_name,
         retry_branch_name,
         _first_failure,
         _retry_failure
       ) do
    %{
      collision_detected: true,
      strategy: @branch_collision_retry_strategy,
      retry_limit: @branch_collision_retry_limit,
      retry_attempted: true,
      source_branch_name: source_branch_name,
      retry_branch_name: retry_branch_name,
      overwrite_existing_remote: false,
      force_push: false
    }
  end

  defp maybe_add_retry_failure_context(collision_handling_context, retry_failure)
       when is_map(collision_handling_context) and is_map(retry_failure) do
    collision_handling_context
    |> Map.put(
      :retry_failure_reason_type,
      retry_failure |> map_get(:reason_type, "reason_type") |> normalize_reason_type()
    )
    |> Map.put(
      :retry_failure_reason,
      retry_failure |> map_get(:reason, "reason") |> format_failure_reason()
    )
  end

  defp maybe_add_retry_failure_context(collision_handling_context, _retry_failure),
    do: collision_handling_context

  defp validate_workspace_cleanliness(args, branch_context)
       when is_map(args) and is_map(branch_context) do
    workspace_policy_check = build_workspace_policy_check(args, branch_context)

    if workspace_policy_check.status == "passed" do
      {:ok, workspace_policy_check}
    else
      {:error,
       workspace_policy_error(
         workspace_policy_reason_type(workspace_policy_check),
         Map.get(
           workspace_policy_check,
           :detail,
           "Workspace cleanliness policy blocked shipping."
         ),
         branch_context,
         workspace_policy_check
       )}
    end
  end

  defp validate_workspace_cleanliness(_args, branch_context) do
    fallback_policy_check =
      %{
        id: @workspace_policy_check_id,
        name: @workspace_policy_check_name,
        status: "failed",
        policy_mode: @workspace_policy_mode,
        required_state: @required_workspace_state,
        observed_state: "unknown",
        environment_mode: "cloud",
        detail: "Workspace cleanliness state is unavailable and shipping is blocked.",
        remediation: @workspace_policy_remediation,
        run_metadata: %{},
        step_metadata: default_step_metadata(),
        checked_at: timestamp_now()
      }

    {:error,
     workspace_policy_error(
       "workspace_state_unknown",
       "Workspace cleanliness state is unavailable and shipping is blocked.",
       branch_context,
       fallback_policy_check
     )}
  end

  @doc false
  @spec default_secret_scan_runner(map(), map()) :: {:ok, map()} | {:error, map()}
  def default_secret_scan_runner(args, _branch_context) when is_map(args) do
    case secret_scan_signal_from_args(args) do
      {:passed, _violation_count, _findings} ->
        {:ok,
         %{
           status: "passed",
           scan_status: @secret_scan_clean_state,
           violation_count: 0,
           findings: [],
           detail: "Secret scan passed with no detected plaintext secrets."
         }}

      {:violation, violation_count, findings} ->
        {:ok,
         %{
           status: "failed",
           scan_status: @secret_scan_violation_state,
           violation_count: violation_count,
           findings: findings,
           detail: "Secret scan detected potential plaintext secrets and blocked shipping."
         }}

      {:tooling_error, reason} ->
        {:error,
         %{
           reason_type: "secret_scan_tooling_error",
           detail: "Secret scan tooling failed and shipping is blocked by fail-closed policy.",
           reason: reason
         }}
    end
  end

  def default_secret_scan_runner(_args, _branch_context) do
    {:error,
     %{
       reason_type: "secret_scan_tooling_error",
       detail: "Secret scan input payload is invalid and shipping is blocked by fail-closed policy.",
       reason: :invalid_secret_scan_args
     }}
  end

  defp validate_secret_scan(args, branch_context, opts)
       when is_map(args) and is_map(branch_context) and is_list(opts) do
    secret_scan_runner =
      Keyword.get(opts, :secret_scan_runner, &__MODULE__.default_secret_scan_runner/2)

    case invoke_secret_scan_runner(secret_scan_runner, args, branch_context) do
      {:ok, secret_scan_result} ->
        secret_scan_policy_check =
          build_secret_scan_policy_check(args, branch_context, secret_scan_result)

        if secret_scan_policy_check.status == "passed" do
          {:ok, secret_scan_policy_check}
        else
          {:error,
           secret_scan_policy_error(
             "policy_violation",
             Map.get(secret_scan_policy_check, :detail, "Secret scan policy blocked shipping."),
             branch_context,
             secret_scan_policy_check,
             map_get(secret_scan_result, :reason, "reason")
           )}
        end

      {:error, secret_scan_runner_failure} ->
        secret_scan_policy_check =
          build_secret_scan_tooling_failure_policy_check(
            args,
            branch_context,
            secret_scan_runner_failure
          )

        {:error,
         secret_scan_policy_error(
           "policy_violation",
           Map.get(
             secret_scan_policy_check,
             :detail,
             "Secret scan tooling failed and shipping is blocked by fail-closed policy."
           ),
           branch_context,
           secret_scan_policy_check,
           secret_scan_runner_failure
         )}
    end
  end

  defp validate_secret_scan(_args, branch_context, _opts) do
    secret_scan_policy_check =
      build_secret_scan_tooling_failure_policy_check(
        %{},
        branch_context,
        :invalid_secret_scan_args
      )

    {:error,
     secret_scan_policy_error(
       "policy_violation",
       Map.get(
         secret_scan_policy_check,
         :detail,
         "Secret scan tooling failed and shipping is blocked by fail-closed policy."
       ),
       branch_context,
       secret_scan_policy_check,
       :invalid_secret_scan_args
     )}
  end

  defp invoke_secret_scan_runner(secret_scan_runner, args, branch_context)
       when is_function(secret_scan_runner, 2) and is_map(args) and is_map(branch_context) do
    safe_invoke_secret_scan_runner(secret_scan_runner, args, branch_context)
  end

  defp invoke_secret_scan_runner(secret_scan_runner, args, branch_context)
       when is_function(secret_scan_runner, 1) and is_map(args) and is_map(branch_context) do
    safe_invoke_secret_scan_runner(
      fn _args, context -> secret_scan_runner.(context) end,
      args,
      branch_context
    )
  end

  defp invoke_secret_scan_runner(_secret_scan_runner, _args, _branch_context) do
    {:error,
     %{
       reason_type: "secret_scan_runner_invalid",
       detail: "Secret scan runner configuration is invalid."
     }}
  end

  defp safe_invoke_secret_scan_runner(secret_scan_runner, args, branch_context)
       when is_function(secret_scan_runner, 2) and is_map(args) and is_map(branch_context) do
    try do
      case secret_scan_runner.(args, branch_context) do
        :ok ->
          {:ok, %{status: "passed", scan_status: @secret_scan_clean_state}}

        {:ok, result} when is_map(result) ->
          {:ok, result}

        {:ok, result} ->
          {:ok, %{status: "passed", scan_status: @secret_scan_clean_state, detail: inspect(result)}}

        {:error, reason} ->
          {:error, reason}

        other ->
          {:error,
           %{
             reason_type: "secret_scan_invalid_result",
             detail: "Secret scan runner returned an invalid result (#{inspect(other)}).",
             reason: other
           }}
      end
    rescue
      exception ->
        {:error,
         %{
           reason_type: "secret_scan_runner_crashed",
           detail: "Secret scan runner crashed (#{Exception.message(exception)}).",
           reason: exception
         }}
    catch
      kind, reason ->
        {:error,
         %{
           reason_type: "secret_scan_runner_threw",
           detail: "Secret scan runner threw #{inspect({kind, reason})}.",
           reason: {kind, reason}
         }}
    end
  end

  defp build_secret_scan_policy_check(args, branch_context, secret_scan_result)
       when is_map(args) and is_map(branch_context) and is_map(secret_scan_result) do
    environment_mode = environment_mode_from_args(args)

    branch_derivation =
      branch_context |> map_get(:branch_derivation, "branch_derivation") |> normalize_map()

    status =
      secret_scan_result
      |> map_get(:status, "status")
      |> normalize_secret_scan_check_status()
      |> case do
        "passed" -> "passed"
        "failed" -> "failed"
        _other -> "failed"
      end

    scan_status = normalize_secret_scan_outcome(secret_scan_result, status)

    findings =
      secret_scan_result |> map_get(:findings, "findings") |> normalize_secret_scan_findings()

    violation_count =
      secret_scan_result
      |> map_get(:violation_count, "violation_count")
      |> normalize_secret_scan_violation_count(length(findings))
      |> normalize_violation_count(status, findings)

    blocked_actions = secret_scan_blocked_actions(status)

    %{
      id: @secret_scan_check_id,
      name: @secret_scan_check_name,
      status: status,
      scan_status: scan_status,
      violation_count: violation_count,
      findings: findings,
      blocked_actions: blocked_actions,
      blocked_action_details: secret_scan_blocked_action_details(scan_status, blocked_actions),
      detail:
        secret_scan_result
        |> map_get(
          :detail,
          "detail",
          secret_scan_policy_detail(status, scan_status, violation_count)
        )
        |> normalize_optional_string() ||
          secret_scan_policy_detail(status, scan_status, violation_count),
      remediation:
        secret_scan_result
        |> map_get(
          :remediation,
          "remediation",
          secret_scan_policy_remediation(status, scan_status)
        )
        |> normalize_optional_string() || secret_scan_policy_remediation(status, scan_status),
      run_metadata: %{
        workflow_name:
          branch_derivation
          |> map_get(:workflow_name, "workflow_name")
          |> normalize_optional_string(),
        run_id: branch_derivation |> map_get(:run_id, "run_id") |> normalize_optional_string(),
        branch_name: branch_context |> map_get(:branch_name, "branch_name") |> normalize_optional_string(),
        environment_mode: environment_mode
      },
      step_metadata: secret_scan_step_metadata(),
      checked_at: timestamp_now()
    }
  end

  defp build_secret_scan_policy_check(_args, branch_context, _secret_scan_result) do
    build_secret_scan_tooling_failure_policy_check(
      %{},
      branch_context,
      :invalid_secret_scan_result
    )
  end

  defp build_secret_scan_tooling_failure_policy_check(args, branch_context, reason)
       when is_map(args) and is_map(branch_context) do
    environment_mode = environment_mode_from_args(args)

    branch_derivation =
      branch_context |> map_get(:branch_derivation, "branch_derivation") |> normalize_map()

    detail =
      map_get(
        reason,
        :detail,
        "detail",
        "Secret scan tooling failed and shipping is blocked by fail-closed policy."
      )

    %{
      id: @secret_scan_check_id,
      name: @secret_scan_check_name,
      status: "failed",
      scan_status: @secret_scan_tooling_error_state,
      violation_count: 0,
      findings: [],
      blocked_actions: @blocked_shipping_actions,
      blocked_action_details:
        secret_scan_blocked_action_details(
          @secret_scan_tooling_error_state,
          @blocked_shipping_actions
        ),
      detail: detail,
      remediation: @secret_scan_policy_remediation,
      run_metadata: %{
        workflow_name:
          branch_derivation
          |> map_get(:workflow_name, "workflow_name")
          |> normalize_optional_string(),
        run_id: branch_derivation |> map_get(:run_id, "run_id") |> normalize_optional_string(),
        branch_name: branch_context |> map_get(:branch_name, "branch_name") |> normalize_optional_string(),
        environment_mode: environment_mode
      },
      step_metadata: secret_scan_step_metadata(),
      checked_at: timestamp_now()
    }
  end

  defp build_secret_scan_tooling_failure_policy_check(_args, branch_context, _reason) do
    branch_derivation =
      branch_context |> map_get(:branch_derivation, "branch_derivation") |> normalize_map()

    %{
      id: @secret_scan_check_id,
      name: @secret_scan_check_name,
      status: "failed",
      scan_status: @secret_scan_tooling_error_state,
      violation_count: 0,
      findings: [],
      blocked_actions: @blocked_shipping_actions,
      blocked_action_details:
        secret_scan_blocked_action_details(
          @secret_scan_tooling_error_state,
          @blocked_shipping_actions
        ),
      detail: "Secret scan tooling failed and shipping is blocked by fail-closed policy.",
      remediation: @secret_scan_policy_remediation,
      run_metadata: %{
        workflow_name:
          branch_derivation
          |> map_get(:workflow_name, "workflow_name")
          |> normalize_optional_string(),
        run_id: branch_derivation |> map_get(:run_id, "run_id") |> normalize_optional_string(),
        branch_name: branch_context |> map_get(:branch_name, "branch_name") |> normalize_optional_string(),
        environment_mode: "cloud"
      },
      step_metadata: secret_scan_step_metadata(),
      checked_at: timestamp_now()
    }
  end

  @doc false
  @spec default_diff_size_runner(map(), map()) :: {:ok, map()} | {:error, map()}
  def default_diff_size_runner(args, _branch_context) when is_map(args) do
    {:ok, diff_metrics_from_sources(args, %{})}
  end

  def default_diff_size_runner(_args, _branch_context) do
    {:error,
     %{
       reason_type: "diff_size_input_invalid",
       detail: "Diff size input payload is invalid and shipping is blocked by fail-closed policy.",
       reason: :invalid_diff_size_args
     }}
  end

  defp validate_diff_size_threshold(args, branch_context, opts)
       when is_map(args) and is_map(branch_context) and is_list(opts) do
    diff_size_runner =
      Keyword.get(opts, :diff_size_runner, &__MODULE__.default_diff_size_runner/2)

    case invoke_diff_size_runner(diff_size_runner, args, branch_context) do
      {:ok, diff_size_result} ->
        diff_size_policy_check =
          build_diff_size_policy_check(args, branch_context, diff_size_result)

        if diff_size_policy_check.status == "passed" do
          {:ok, diff_size_policy_check}
        else
          {:error,
           diff_size_policy_error(
             diff_size_reason_type(diff_size_policy_check),
             Map.get(
               diff_size_policy_check,
               :detail,
               "Diff size threshold policy blocked shipping."
             ),
             branch_context,
             diff_size_policy_check,
             map_get(diff_size_result, :reason, "reason")
           )}
        end

      {:error, diff_size_runner_failure} ->
        diff_size_policy_check =
          build_diff_size_tooling_failure_policy_check(
            args,
            branch_context,
            diff_size_runner_failure
          )

        {:error,
         diff_size_policy_error(
           "policy_violation",
           Map.get(
             diff_size_policy_check,
             :detail,
             "Diff size metrics are unavailable and shipping is blocked by fail-closed policy."
           ),
           branch_context,
           diff_size_policy_check,
           diff_size_runner_failure
         )}
    end
  end

  defp validate_diff_size_threshold(_args, branch_context, _opts) do
    diff_size_policy_check =
      build_diff_size_tooling_failure_policy_check(
        %{},
        branch_context,
        :invalid_diff_size_args
      )

    {:error,
     diff_size_policy_error(
       "policy_violation",
       Map.get(
         diff_size_policy_check,
         :detail,
         "Diff size metrics are unavailable and shipping is blocked by fail-closed policy."
       ),
       branch_context,
       diff_size_policy_check,
       :invalid_diff_size_args
     )}
  end

  defp invoke_diff_size_runner(diff_size_runner, args, branch_context)
       when is_function(diff_size_runner, 2) and is_map(args) and is_map(branch_context) do
    safe_invoke_diff_size_runner(diff_size_runner, args, branch_context)
  end

  defp invoke_diff_size_runner(diff_size_runner, args, branch_context)
       when is_function(diff_size_runner, 1) and is_map(args) and is_map(branch_context) do
    safe_invoke_diff_size_runner(
      fn _args, context -> diff_size_runner.(context) end,
      args,
      branch_context
    )
  end

  defp invoke_diff_size_runner(_diff_size_runner, _args, _branch_context) do
    {:error,
     %{
       reason_type: "diff_size_runner_invalid",
       detail: "Diff size runner configuration is invalid."
     }}
  end

  defp safe_invoke_diff_size_runner(diff_size_runner, args, branch_context)
       when is_function(diff_size_runner, 2) and is_map(args) and is_map(branch_context) do
    try do
      case diff_size_runner.(args, branch_context) do
        :ok ->
          {:ok, diff_metrics_from_sources(args, %{})}

        {:ok, result} when is_map(result) ->
          {:ok, result}

        {:ok, result} when is_integer(result) and result >= 0 ->
          {:ok, %{total_lines_changed: result}}

        {:ok, result} ->
          {:error,
           %{
             reason_type: "diff_size_invalid_result",
             detail: "Diff size runner returned an invalid result (#{inspect(result)}).",
             reason: result
           }}

        {:error, reason} ->
          {:error, reason}

        other ->
          {:error,
           %{
             reason_type: "diff_size_invalid_result",
             detail: "Diff size runner returned an invalid result (#{inspect(other)}).",
             reason: other
           }}
      end
    rescue
      exception ->
        {:error,
         %{
           reason_type: "diff_size_runner_crashed",
           detail: "Diff size runner crashed (#{Exception.message(exception)}).",
           reason: exception
         }}
    catch
      kind, reason ->
        {:error,
         %{
           reason_type: "diff_size_runner_threw",
           detail: "Diff size runner threw #{inspect({kind, reason})}.",
           reason: {kind, reason}
         }}
    end
  end

  defp build_diff_size_policy_check(args, branch_context, diff_size_result)
       when is_map(args) and is_map(branch_context) and is_map(diff_size_result) do
    environment_mode = environment_mode_from_args(args)
    diff_metrics = diff_metrics_from_sources(args, diff_size_result)
    threshold_policy = diff_threshold_policy(args, diff_size_result)

    total_lines_changed = Map.get(diff_metrics, :total_lines_changed, 0)

    max_changed_lines =
      Map.get(threshold_policy, :max_changed_lines, @default_diff_max_changed_lines)

    threshold_exceeded = total_lines_changed > max_changed_lines

    decision = diff_size_decision(threshold_exceeded, Map.get(threshold_policy, :on_exceed))
    status = if threshold_exceeded, do: "failed", else: "passed"
    blocked_actions = diff_size_blocked_actions(status)

    branch_derivation =
      branch_context |> map_get(:branch_derivation, "branch_derivation") |> normalize_map()

    %{
      id: @diff_size_check_id,
      name: @diff_size_check_name,
      status: status,
      decision: decision,
      threshold_exceeded: threshold_exceeded,
      manual_override_required: decision == "approval_override_required",
      metrics: diff_metrics,
      threshold_policy: threshold_policy,
      blocked_actions: blocked_actions,
      blocked_action_details: diff_size_blocked_action_details(decision, blocked_actions),
      detail:
        diff_size_result
        |> map_get(
          :detail,
          "detail",
          diff_size_policy_detail(
            status,
            decision,
            total_lines_changed,
            max_changed_lines,
            Map.get(threshold_policy, :source)
          )
        )
        |> normalize_optional_string() ||
          diff_size_policy_detail(
            status,
            decision,
            total_lines_changed,
            max_changed_lines,
            Map.get(threshold_policy, :source)
          ),
      remediation:
        diff_size_result
        |> map_get(
          :remediation,
          "remediation",
          diff_size_policy_remediation(status, decision)
        )
        |> normalize_optional_string() || diff_size_policy_remediation(status, decision),
      run_metadata: %{
        workflow_name:
          branch_derivation
          |> map_get(:workflow_name, "workflow_name")
          |> normalize_optional_string(),
        run_id: branch_derivation |> map_get(:run_id, "run_id") |> normalize_optional_string(),
        branch_name: branch_context |> map_get(:branch_name, "branch_name") |> normalize_optional_string(),
        environment_mode: environment_mode
      },
      step_metadata: diff_size_step_metadata(),
      checked_at: timestamp_now()
    }
  end

  defp build_diff_size_policy_check(_args, branch_context, _diff_size_result) do
    build_diff_size_tooling_failure_policy_check(
      %{},
      branch_context,
      :invalid_diff_size_result
    )
  end

  defp build_diff_size_tooling_failure_policy_check(args, branch_context, reason)
       when is_map(args) and is_map(branch_context) do
    environment_mode = environment_mode_from_args(args)
    threshold_policy = diff_threshold_policy(args, %{})
    diff_metrics = diff_metrics_from_sources(args, %{})

    branch_derivation =
      branch_context |> map_get(:branch_derivation, "branch_derivation") |> normalize_map()

    detail =
      map_get(
        reason,
        :detail,
        "detail",
        "Diff size metrics are unavailable and shipping is blocked by fail-closed policy."
      )

    %{
      id: @diff_size_check_id,
      name: @diff_size_check_name,
      status: "failed",
      decision: "blocked",
      threshold_exceeded: false,
      manual_override_required: false,
      metrics: diff_metrics,
      threshold_policy: threshold_policy,
      blocked_actions: @blocked_shipping_actions,
      blocked_action_details: diff_size_blocked_action_details("tooling_error", @blocked_shipping_actions),
      detail: detail,
      remediation: @diff_size_policy_remediation,
      run_metadata: %{
        workflow_name:
          branch_derivation
          |> map_get(:workflow_name, "workflow_name")
          |> normalize_optional_string(),
        run_id: branch_derivation |> map_get(:run_id, "run_id") |> normalize_optional_string(),
        branch_name: branch_context |> map_get(:branch_name, "branch_name") |> normalize_optional_string(),
        environment_mode: environment_mode
      },
      step_metadata: diff_size_step_metadata(),
      checked_at: timestamp_now()
    }
  end

  defp build_diff_size_tooling_failure_policy_check(_args, branch_context, _reason) do
    branch_derivation =
      branch_context |> map_get(:branch_derivation, "branch_derivation") |> normalize_map()

    %{
      id: @diff_size_check_id,
      name: @diff_size_check_name,
      status: "failed",
      decision: "blocked",
      threshold_exceeded: false,
      manual_override_required: false,
      metrics: %{files_changed: 0, lines_added: 0, lines_deleted: 0, total_lines_changed: 0},
      threshold_policy: default_diff_threshold_policy(),
      blocked_actions: @blocked_shipping_actions,
      blocked_action_details: diff_size_blocked_action_details("tooling_error", @blocked_shipping_actions),
      detail: "Diff size metrics are unavailable and shipping is blocked by fail-closed policy.",
      remediation: @diff_size_policy_remediation,
      run_metadata: %{
        workflow_name:
          branch_derivation
          |> map_get(:workflow_name, "workflow_name")
          |> normalize_optional_string(),
        run_id: branch_derivation |> map_get(:run_id, "run_id") |> normalize_optional_string(),
        branch_name: branch_context |> map_get(:branch_name, "branch_name") |> normalize_optional_string(),
        environment_mode: "cloud"
      },
      step_metadata: diff_size_step_metadata(),
      checked_at: timestamp_now()
    }
  end

  defp maybe_probe_commit(branch_context, opts) when is_map(branch_context) and is_list(opts) do
    case Keyword.get(opts, :commit_probe) do
      commit_probe when is_function(commit_probe, 1) ->
        commit_probe.(branch_context)
        :ok

      _other ->
        :ok
    end
  rescue
    _exception -> :ok
  end

  defp maybe_probe_commit(_branch_context, _opts), do: :ok

  defp normalize_branch_segment(value, fallback, max_length)
       when is_integer(max_length) and max_length > 0 do
    normalized_segment = normalize_branch_slug(value, fallback)

    if String.length(normalized_segment) <= max_length do
      {normalized_segment, "slug"}
    else
      {truncate_with_hash_suffix(normalized_segment, max_length), "slug_with_hash_suffix"}
    end
  end

  defp normalize_branch_slug(value, fallback) do
    value
    |> normalize_optional_string()
    |> case do
      nil ->
        fallback

      normalized_value ->
        normalized_value
        |> String.downcase()
        |> String.replace(~r/[^a-z0-9]+/, "-")
        |> String.replace(~r/-+/, "-")
        |> String.trim("-")
        |> case do
          "" -> fallback
          segment -> segment
        end
    end
  end

  defp truncate_with_hash_suffix(segment, max_length)
       when is_binary(segment) and is_integer(max_length) and max_length > @hash_suffix_length + 1 do
    hash_suffix = segment_fingerprint(segment)
    prefix_length = max_length - @hash_suffix_length - 1
    prefix = segment |> String.slice(0, prefix_length) |> String.trim_trailing("-")

    case prefix do
      "" -> String.slice(hash_suffix, 0, max_length)
      normalized_prefix -> "#{normalized_prefix}-#{hash_suffix}"
    end
  end

  defp truncate_with_hash_suffix(segment, max_length)
       when is_binary(segment) and is_integer(max_length) and max_length > 0 do
    segment
    |> segment_fingerprint()
    |> String.slice(0, max_length)
  end

  defp segment_fingerprint(segment) when is_binary(segment) do
    segment
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> String.slice(0, @hash_suffix_length)
  end

  defp build_workspace_policy_check(args, branch_context)
       when is_map(args) and is_map(branch_context) do
    environment_mode = environment_mode_from_args(args)
    observed_state = workspace_state_from_args(args)
    status = workspace_policy_status(observed_state)

    branch_derivation =
      branch_context |> map_get(:branch_derivation, "branch_derivation") |> normalize_map()

    %{
      id: @workspace_policy_check_id,
      name: @workspace_policy_check_name,
      status: status,
      policy_mode: @workspace_policy_mode,
      required_state: @required_workspace_state,
      observed_state: observed_state,
      environment_mode: environment_mode,
      detail: workspace_policy_detail(status, environment_mode, observed_state),
      remediation: workspace_policy_remediation(status),
      run_metadata: %{
        workflow_name:
          branch_derivation
          |> map_get(:workflow_name, "workflow_name")
          |> normalize_optional_string(),
        run_id: branch_derivation |> map_get(:run_id, "run_id") |> normalize_optional_string(),
        branch_name: branch_context |> map_get(:branch_name, "branch_name") |> normalize_optional_string(),
        environment_mode: environment_mode
      },
      step_metadata: default_step_metadata(),
      checked_at: timestamp_now()
    }
  end

  defp workspace_policy_status("clean"), do: "passed"
  defp workspace_policy_status(_observed_state), do: "failed"

  defp workspace_policy_detail("passed", environment_mode, "clean") do
    "Workspace is clean and satisfies #{environment_mode} clean-room shipping policy."
  end

  defp workspace_policy_detail("failed", environment_mode, "dirty") do
    "#{String.capitalize(environment_mode)} mode requires a clean workspace before commit, push, and PR."
  end

  defp workspace_policy_detail("failed", environment_mode, _observed_state) do
    "#{String.capitalize(environment_mode)} mode requires a clean workspace, but workspace cleanliness was unknown."
  end

  defp workspace_policy_remediation("passed"),
    do: "Workspace meets clean-room shipping requirements."

  defp workspace_policy_remediation(_status), do: @workspace_policy_remediation

  defp workspace_policy_reason_type(%{observed_state: "dirty"}), do: "workspace_dirty"
  defp workspace_policy_reason_type(%{observed_state: "unknown"}), do: "workspace_state_unknown"
  defp workspace_policy_reason_type(_workspace_policy_check), do: "workspace_policy_failed"

  defp secret_scan_signal_from_args(args) when is_map(args) do
    status_hint =
      args
      |> map_get(
        :secret_scan_status,
        "secret_scan_status",
        map_get(args, :secret_scan_result, "secret_scan_result")
      )
      |> normalize_secret_scan_status_hint()

    findings =
      args
      |> map_get(
        :secret_scan_findings,
        "secret_scan_findings",
        map_get(args, :secret_scan_matches, "secret_scan_matches")
      )
      |> normalize_secret_scan_findings()

    violation_count =
      args
      |> map_get(
        :secret_scan_violation_count,
        "secret_scan_violation_count",
        map_get(args, :secret_scan_violations, "secret_scan_violations")
      )
      |> normalize_secret_scan_violation_count(length(findings))

    secret_scan_passed =
      args
      |> map_get(:secret_scan_passed, "secret_scan_passed")
      |> normalize_optional_boolean()

    tooling_error_reason =
      map_get(
        args,
        :secret_scan_error,
        "secret_scan_error",
        map_get(args, :secret_scan_tooling_error, "secret_scan_tooling_error")
      )

    cond do
      status_hint == :tooling_error ->
        {:tooling_error, tooling_error_reason || :secret_scan_tooling_error}

      not is_nil(tooling_error_reason) ->
        {:tooling_error, tooling_error_reason}

      status_hint == :violation ->
        {:violation, ensure_violation_count(violation_count), findings}

      secret_scan_passed == false ->
        {:violation, ensure_violation_count(violation_count), findings}

      violation_count > 0 ->
        {:violation, violation_count, findings}

      findings != [] ->
        {:violation, ensure_violation_count(violation_count, length(findings)), findings}

      status_hint == :passed ->
        {:passed, 0, []}

      secret_scan_passed == true ->
        {:passed, 0, []}

      true ->
        {:passed, 0, []}
    end
  end

  defp secret_scan_signal_from_args(_args), do: {:tooling_error, :invalid_secret_scan_args}

  defp normalize_secret_scan_status_hint(value) when is_boolean(value) do
    if value, do: :passed, else: :violation
  end

  defp normalize_secret_scan_status_hint(value) do
    value
    |> normalize_optional_string()
    |> case do
      nil ->
        nil

      normalized_status ->
        case String.downcase(normalized_status) do
          "passed" -> :passed
          "pass" -> :passed
          "clean" -> :passed
          "ok" -> :passed
          "success" -> :passed
          "failed" -> :violation
          "fail" -> :violation
          "violation" -> :violation
          "violations" -> :violation
          "violations_detected" -> :violation
          "blocked" -> :violation
          "error" -> :tooling_error
          "tooling_error" -> :tooling_error
          "runner_error" -> :tooling_error
          "scanner_error" -> :tooling_error
          "unavailable" -> :tooling_error
          _other -> nil
        end
    end
  end

  defp normalize_secret_scan_check_status(value) do
    value
    |> normalize_optional_string()
    |> case do
      nil ->
        nil

      normalized_status ->
        case String.downcase(normalized_status) do
          "passed" -> "passed"
          "clean" -> "passed"
          "ok" -> "passed"
          "failed" -> "failed"
          "error" -> "failed"
          "blocked" -> "failed"
          "violations_detected" -> "failed"
          _other -> nil
        end
    end
  end

  defp normalize_secret_scan_outcome(secret_scan_result, status)
       when is_map(secret_scan_result) and is_binary(status) do
    outcome =
      secret_scan_result
      |> map_get(:scan_status, "scan_status")
      |> normalize_optional_string()
      |> case do
        nil ->
          nil

        normalized_scan_status ->
          case String.downcase(normalized_scan_status) do
            "clean" -> @secret_scan_clean_state
            "passed" -> @secret_scan_clean_state
            "ok" -> @secret_scan_clean_state
            "violation" -> @secret_scan_violation_state
            "violations" -> @secret_scan_violation_state
            "violations_detected" -> @secret_scan_violation_state
            "failed" -> @secret_scan_violation_state
            "blocked" -> @secret_scan_violation_state
            "tooling_error" -> @secret_scan_tooling_error_state
            "error" -> @secret_scan_tooling_error_state
            "runner_error" -> @secret_scan_tooling_error_state
            "scanner_error" -> @secret_scan_tooling_error_state
            "unavailable" -> @secret_scan_tooling_error_state
            _other -> nil
          end
      end

    case {status, outcome} do
      {"passed", _any_outcome} ->
        @secret_scan_clean_state

      {"failed", nil} ->
        @secret_scan_violation_state

      {"failed", @secret_scan_clean_state} ->
        @secret_scan_violation_state

      {"failed", normalized_outcome} ->
        normalized_outcome

      _other ->
        @secret_scan_tooling_error_state
    end
  end

  defp normalize_secret_scan_outcome(_secret_scan_result, _status),
    do: @secret_scan_tooling_error_state

  defp normalize_secret_scan_findings(findings) when is_list(findings) do
    findings
    |> Enum.map(&normalize_secret_scan_finding/1)
    |> Enum.reject(fn finding -> finding == %{} end)
  end

  defp normalize_secret_scan_findings(%{} = finding) do
    finding = normalize_secret_scan_finding(finding)

    if finding == %{} do
      []
    else
      [finding]
    end
  end

  defp normalize_secret_scan_findings(findings) when is_binary(findings) do
    case String.trim(findings) do
      "" -> []
      summary -> [%{summary: summary}]
    end
  end

  defp normalize_secret_scan_findings(_findings), do: []

  defp normalize_secret_scan_finding(%{} = finding), do: finding

  defp normalize_secret_scan_finding(finding) when is_binary(finding) do
    case String.trim(finding) do
      "" -> %{}
      summary -> %{summary: summary}
    end
  end

  defp normalize_secret_scan_finding(finding), do: %{summary: inspect(finding)}

  defp normalize_secret_scan_violation_count(value, fallback)

  defp normalize_secret_scan_violation_count(value, _fallback)
       when is_integer(value) and value >= 0,
       do: value

  defp normalize_secret_scan_violation_count(value, _fallback) when is_list(value),
    do: length(value)

  defp normalize_secret_scan_violation_count(true, _fallback), do: 1
  defp normalize_secret_scan_violation_count(false, _fallback), do: 0

  defp normalize_secret_scan_violation_count(value, fallback) do
    value
    |> normalize_optional_string()
    |> case do
      nil ->
        fallback

      normalized_value ->
        case Integer.parse(normalized_value) do
          {parsed_count, ""} when parsed_count >= 0 -> parsed_count
          _other -> fallback
        end
    end
  end

  defp normalize_violation_count(_violation_count, "passed", _findings), do: 0

  defp normalize_violation_count(violation_count, "failed", findings)
       when is_list(findings) and is_integer(violation_count) do
    ensure_violation_count(violation_count, length(findings))
  end

  defp normalize_violation_count(violation_count, _status, _findings), do: violation_count

  defp ensure_violation_count(violation_count, findings_count \\ 0)

  defp ensure_violation_count(violation_count, _findings_count)
       when is_integer(violation_count) and violation_count > 0,
       do: violation_count

  defp ensure_violation_count(_violation_count, findings_count)
       when is_integer(findings_count) and findings_count > 0,
       do: findings_count

  defp ensure_violation_count(_violation_count, _findings_count), do: 1

  defp secret_scan_blocked_actions("failed"), do: @blocked_shipping_actions
  defp secret_scan_blocked_actions(_status), do: []

  defp secret_scan_blocked_action_details(_scan_status, blocked_actions)
       when is_list(blocked_actions) and blocked_actions == [] do
    []
  end

  defp secret_scan_blocked_action_details(scan_status, blocked_actions)
       when is_list(blocked_actions) do
    Enum.map(blocked_actions, fn blocked_action ->
      %{
        action: blocked_action,
        blocked: true,
        reason: secret_scan_block_reason(scan_status),
        detail: "Secret scan policy blocked #{blocked_action}."
      }
    end)
  end

  defp secret_scan_blocked_action_details(_scan_status, _blocked_actions), do: []

  defp secret_scan_block_reason(@secret_scan_tooling_error_state), do: "secret_scan_tooling_error"
  defp secret_scan_block_reason(@secret_scan_violation_state), do: "secret_scan_violation"
  defp secret_scan_block_reason(_scan_status), do: "policy_violation"

  defp secret_scan_policy_detail("passed", @secret_scan_clean_state, _violation_count) do
    "Secret scan passed with no detected plaintext secrets."
  end

  defp secret_scan_policy_detail("failed", @secret_scan_violation_state, violation_count) do
    "Secret scan detected #{violation_count} potential secret finding(s); commit, push, and PR creation are blocked."
  end

  defp secret_scan_policy_detail("failed", @secret_scan_tooling_error_state, _violation_count) do
    "Secret scan tooling failed and shipping is blocked by fail-closed policy."
  end

  defp secret_scan_policy_detail(_status, _scan_status, _violation_count) do
    "Secret scan policy blocked shipping."
  end

  defp secret_scan_policy_remediation("passed", @secret_scan_clean_state),
    do: "Secret scan policy satisfied."

  defp secret_scan_policy_remediation("failed", @secret_scan_violation_state) do
    "Remove detected secrets from the workspace and retry CommitAndPR shipping."
  end

  defp secret_scan_policy_remediation("failed", @secret_scan_tooling_error_state) do
    "Restore secret-scan tooling availability and retry CommitAndPR shipping."
  end

  defp secret_scan_policy_remediation(_status, _scan_status), do: @secret_scan_policy_remediation

  defp secret_scan_step_metadata do
    step_metadata(@secret_scan_policy_stage, @secret_scan_policy_operation)
  end

  defp diff_size_reason_type(%{decision: "approval_override_required"}),
    do: "approval_override_required"

  defp diff_size_reason_type(%{decision: "blocked"}), do: "diff_size_threshold_exceeded"
  defp diff_size_reason_type(_diff_size_policy_check), do: "policy_violation"

  defp diff_size_decision(false, _on_exceed), do: "within_threshold"
  defp diff_size_decision(true, "require_approval_override"), do: "approval_override_required"
  defp diff_size_decision(true, _on_exceed), do: "blocked"

  defp diff_size_blocked_actions("failed"), do: @blocked_shipping_actions
  defp diff_size_blocked_actions(_status), do: []

  defp diff_size_blocked_action_details(_decision, blocked_actions)
       when is_list(blocked_actions) and blocked_actions == [] do
    []
  end

  defp diff_size_blocked_action_details(decision, blocked_actions)
       when is_list(blocked_actions) do
    Enum.map(blocked_actions, fn blocked_action ->
      %{
        action: blocked_action,
        blocked: true,
        reason: diff_size_block_reason(decision),
        detail: "Diff size threshold policy blocked #{blocked_action}."
      }
    end)
  end

  defp diff_size_blocked_action_details(_decision, _blocked_actions), do: []

  defp diff_size_block_reason("approval_override_required"), do: "approval_override_required"
  defp diff_size_block_reason("blocked"), do: "diff_size_threshold_exceeded"
  defp diff_size_block_reason("tooling_error"), do: "diff_size_tooling_error"
  defp diff_size_block_reason(_decision), do: "policy_violation"

  defp diff_size_policy_detail(
         "passed",
         "within_threshold",
         total_lines_changed,
         max_changed_lines,
         _source
       ) do
    "Diff size #{total_lines_changed} changed line(s) is within configured threshold #{max_changed_lines}."
  end

  defp diff_size_policy_detail(
         "failed",
         "approval_override_required",
         total_lines_changed,
         max_changed_lines,
         source
       ) do
    "Diff size #{total_lines_changed} changed line(s) exceeded #{diff_threshold_source_label(source)} threshold #{max_changed_lines}; explicit approval override is required before shipping."
  end

  defp diff_size_policy_detail(
         "failed",
         "blocked",
         total_lines_changed,
         max_changed_lines,
         source
       ) do
    "Diff size #{total_lines_changed} changed line(s) exceeded #{diff_threshold_source_label(source)} threshold #{max_changed_lines}; shipping is blocked by policy."
  end

  defp diff_size_policy_detail(
         _status,
         _decision,
         total_lines_changed,
         max_changed_lines,
         source
       ) do
    "Diff size #{total_lines_changed} changed line(s) exceeded #{diff_threshold_source_label(source)} threshold #{max_changed_lines}; shipping is blocked by policy."
  end

  defp diff_size_policy_remediation("passed", "within_threshold"),
    do: "Diff size policy satisfied."

  defp diff_size_policy_remediation("failed", "approval_override_required") do
    "Request explicit approval override for the oversized diff before retrying CommitAndPR shipping."
  end

  defp diff_size_policy_remediation(_status, _decision), do: @diff_size_policy_remediation

  defp diff_threshold_source_label("workflow_policy"), do: "workflow"
  defp diff_threshold_source_label("project_policy"), do: "project"
  defp diff_threshold_source_label("shipping_policy"), do: "shipping"
  defp diff_threshold_source_label("runner_policy"), do: "runner"
  defp diff_threshold_source_label("args"), do: "input"
  defp diff_threshold_source_label(_source), do: "configured"

  defp diff_size_step_metadata do
    step_metadata(@diff_size_policy_stage, @diff_size_policy_operation)
  end

  defp diff_threshold_policy(args, diff_size_result)
       when is_map(args) and is_map(diff_size_result) do
    [
      runner_threshold_candidate(diff_size_result),
      {"workflow_policy", policy_diff_threshold_candidate(map_get(args, :workflow_policy, "workflow_policy"))},
      {"project_policy", policy_diff_threshold_candidate(map_get(args, :project_policy, "project_policy"))},
      {"shipping_policy", policy_diff_threshold_candidate(map_get(args, :shipping_policy, "shipping_policy"))},
      {"args",
       map_get(
         args,
         :diff_size_threshold,
         "diff_size_threshold",
         map_get(args, :max_diff_lines, "max_diff_lines")
       )}
    ]
    |> Enum.find_value(&normalize_diff_threshold_candidate/1)
    |> case do
      nil -> default_diff_threshold_policy()
      threshold_policy -> threshold_policy
    end
  end

  defp diff_threshold_policy(_args, _diff_size_result), do: default_diff_threshold_policy()

  defp runner_threshold_candidate(diff_size_result) when is_map(diff_size_result) do
    {"runner_policy",
     map_get(
       diff_size_result,
       :threshold_policy,
       "threshold_policy",
       map_get(diff_size_result, :diff_size_threshold, "diff_size_threshold")
     )}
  end

  defp runner_threshold_candidate(_diff_size_result), do: {"runner_policy", nil}

  defp policy_diff_threshold_candidate(policy_map) when is_map(policy_map) do
    map_get(
      policy_map,
      :diff_size_threshold,
      "diff_size_threshold",
      map_get(
        policy_map,
        :diff_size,
        "diff_size",
        map_get(policy_map, :max_diff_lines, "max_diff_lines")
      )
    )
  end

  defp policy_diff_threshold_candidate(_policy_map), do: nil

  defp normalize_diff_threshold_candidate({source, candidate}) do
    max_changed_lines = diff_threshold_max_lines(candidate)

    if is_integer(max_changed_lines) and max_changed_lines > 0 do
      %{
        source: source,
        max_changed_lines: max_changed_lines,
        on_exceed: diff_threshold_exceed_policy(candidate)
      }
    else
      nil
    end
  end

  defp normalize_diff_threshold_candidate(_candidate), do: nil

  defp diff_threshold_max_lines(candidate) when is_integer(candidate), do: candidate

  defp diff_threshold_max_lines(candidate) when is_map(candidate) do
    candidate
    |> map_get(
      :max_changed_lines,
      "max_changed_lines",
      map_get(
        candidate,
        :max_lines,
        "max_lines",
        map_get(
          candidate,
          :threshold,
          "threshold",
          map_get(
            candidate,
            :line_limit,
            "line_limit",
            map_get(candidate, :limit, "limit")
          )
        )
      )
    )
    |> normalize_optional_non_negative_integer()
  end

  defp diff_threshold_max_lines(candidate) do
    candidate
    |> normalize_optional_non_negative_integer()
  end

  defp diff_threshold_exceed_policy(%{} = candidate) do
    candidate
    |> map_get(
      :on_exceed,
      "on_exceed",
      map_get(
        candidate,
        :exceed_action,
        "exceed_action",
        map_get(
          candidate,
          :decision,
          "decision",
          map_get(candidate, :outcome, "outcome", "block")
        )
      )
    )
    |> normalize_diff_threshold_exceed_policy()
  end

  defp diff_threshold_exceed_policy(_candidate), do: "block"

  defp normalize_diff_threshold_exceed_policy(value) do
    value
    |> normalize_optional_string()
    |> case do
      nil ->
        "block"

      normalized_value ->
        case String.downcase(normalized_value) do
          "block" -> "block"
          "blocked" -> "block"
          "deny" -> "block"
          "escalate" -> "require_approval_override"
          "approval_override" -> "require_approval_override"
          "require_approval_override" -> "require_approval_override"
          "manual_override" -> "require_approval_override"
          _other -> "block"
        end
    end
  end

  defp default_diff_threshold_policy do
    %{
      source: "default",
      max_changed_lines: @default_diff_max_changed_lines,
      on_exceed: "block"
    }
  end

  defp diff_metrics_from_sources(args, diff_size_result)
       when is_map(args) and is_map(diff_size_result) do
    result_metrics =
      diff_size_result
      |> map_get(:metrics, "metrics")
      |> normalize_map()

    args_metrics =
      args
      |> map_get(:diff_metrics, "diff_metrics")
      |> normalize_map()

    files_changed =
      first_non_negative_integer(
        [
          map_get(result_metrics, :files_changed, "files_changed"),
          map_get(result_metrics, :changed_files_count, "changed_files_count"),
          map_get(diff_size_result, :files_changed, "files_changed"),
          map_get(diff_size_result, :changed_files_count, "changed_files_count"),
          map_get(args_metrics, :files_changed, "files_changed"),
          map_get(args_metrics, :changed_files_count, "changed_files_count"),
          map_get(args, :files_changed, "files_changed"),
          map_get(args, :changed_files_count, "changed_files_count"),
          diff_files_count(diff_size_result, args)
        ],
        0
      )

    lines_added =
      first_non_negative_integer(
        [
          map_get(result_metrics, :lines_added, "lines_added"),
          map_get(result_metrics, :additions, "additions"),
          map_get(diff_size_result, :lines_added, "lines_added"),
          map_get(diff_size_result, :additions, "additions"),
          map_get(args_metrics, :lines_added, "lines_added"),
          map_get(args_metrics, :additions, "additions"),
          map_get(args, :lines_added, "lines_added"),
          map_get(args, :additions, "additions"),
          map_get(args, :diff_lines_added, "diff_lines_added")
        ],
        0
      )

    lines_deleted =
      first_non_negative_integer(
        [
          map_get(result_metrics, :lines_deleted, "lines_deleted"),
          map_get(result_metrics, :deletions, "deletions"),
          map_get(diff_size_result, :lines_deleted, "lines_deleted"),
          map_get(diff_size_result, :deletions, "deletions"),
          map_get(args_metrics, :lines_deleted, "lines_deleted"),
          map_get(args_metrics, :deletions, "deletions"),
          map_get(args, :lines_deleted, "lines_deleted"),
          map_get(args, :deletions, "deletions"),
          map_get(args, :diff_lines_deleted, "diff_lines_deleted")
        ],
        0
      )

    explicit_total_lines_changed =
      first_optional_non_negative_integer([
        map_get(result_metrics, :total_lines_changed, "total_lines_changed"),
        map_get(result_metrics, :diff_size, "diff_size"),
        map_get(result_metrics, :diff_line_count, "diff_line_count"),
        map_get(diff_size_result, :total_lines_changed, "total_lines_changed"),
        map_get(diff_size_result, :diff_size, "diff_size"),
        map_get(diff_size_result, :diff_line_count, "diff_line_count"),
        map_get(args_metrics, :total_lines_changed, "total_lines_changed"),
        map_get(args_metrics, :diff_size, "diff_size"),
        map_get(args_metrics, :diff_line_count, "diff_line_count"),
        map_get(args, :total_lines_changed, "total_lines_changed"),
        map_get(args, :diff_size, "diff_size"),
        map_get(args, :diff_line_count, "diff_line_count")
      ])

    derived_total_lines_changed = lines_added + lines_deleted

    total_lines_changed =
      case explicit_total_lines_changed do
        nil -> derived_total_lines_changed
        parsed_total_lines_changed -> max(parsed_total_lines_changed, derived_total_lines_changed)
      end

    %{
      files_changed: files_changed,
      lines_added: lines_added,
      lines_deleted: lines_deleted,
      total_lines_changed: total_lines_changed
    }
  end

  defp diff_metrics_from_sources(_args, _diff_size_result) do
    %{files_changed: 0, lines_added: 0, lines_deleted: 0, total_lines_changed: 0}
  end

  defp diff_files_count(diff_size_result, args) do
    diff_size_result
    |> map_get(
      :diff_files,
      "diff_files",
      map_get(
        diff_size_result,
        :changed_files,
        "changed_files",
        map_get(
          args,
          :diff_files,
          "diff_files",
          map_get(args, :changed_files, "changed_files")
        )
      )
    )
    |> normalize_optional_non_negative_integer()
  end

  defp first_non_negative_integer(candidates, fallback) when is_list(candidates) do
    case first_optional_non_negative_integer(candidates) do
      nil -> fallback
      value -> value
    end
  end

  defp first_non_negative_integer(_candidates, fallback), do: fallback

  defp first_optional_non_negative_integer(candidates) when is_list(candidates) do
    Enum.find_value(candidates, &normalize_optional_non_negative_integer/1)
  end

  defp first_optional_non_negative_integer(_candidates), do: nil

  defp normalize_optional_non_negative_integer(value)
       when is_integer(value) and value >= 0,
       do: value

  defp normalize_optional_non_negative_integer(value) when is_integer(value), do: nil

  defp normalize_optional_non_negative_integer(value) when is_float(value) and value >= 0,
    do: trunc(value)

  defp normalize_optional_non_negative_integer(value) when is_float(value), do: nil
  defp normalize_optional_non_negative_integer(true), do: 1
  defp normalize_optional_non_negative_integer(false), do: 0

  defp normalize_optional_non_negative_integer(value) when is_list(value),
    do: length(value)

  defp normalize_optional_non_negative_integer(value) do
    value
    |> normalize_optional_string()
    |> case do
      nil ->
        nil

      normalized_value ->
        case Integer.parse(normalized_value) do
          {parsed_value, ""} when parsed_value >= 0 -> parsed_value
          _other -> nil
        end
    end
  end

  defp environment_mode_from_args(args) when is_map(args) do
    args
    |> map_get(
      :environment_mode,
      "environment_mode",
      map_get(args, :workspace_mode, "workspace_mode", map_get(args, :mode, "mode", "cloud"))
    )
    |> normalize_environment_mode()
  end

  defp environment_mode_from_args(_args), do: "cloud"

  defp workspace_state_from_args(args) when is_map(args) do
    explicit_state =
      args
      |> map_get(:workspace_state, "workspace_state")
      |> normalize_workspace_state()

    status_state =
      args
      |> map_get(:workspace_status, "workspace_status")
      |> normalize_workspace_state()

    clean_flag_state =
      args
      |> map_get(
        :workspace_clean,
        "workspace_clean",
        map_get(args, :workspace_is_clean, "workspace_is_clean")
      )
      |> normalize_workspace_clean_flag()

    explicit_state || status_state || clean_flag_state || "unknown"
  end

  defp workspace_state_from_args(_args), do: "unknown"

  defp normalize_environment_mode(value) do
    value
    |> normalize_optional_string()
    |> case do
      nil ->
        "cloud"

      normalized_mode ->
        case String.downcase(normalized_mode) do
          "local" -> "local"
          "cloud" -> "cloud"
          "sprite" -> "cloud"
          _other -> "cloud"
        end
    end
  end

  defp normalize_workspace_state(value) when is_boolean(value),
    do: normalize_workspace_clean_flag(value)

  defp normalize_workspace_state(value) do
    value
    |> normalize_optional_string()
    |> case do
      nil ->
        nil

      normalized_state ->
        case String.downcase(normalized_state) do
          "clean" -> "clean"
          "ready" -> "clean"
          "pristine" -> "clean"
          "dirty" -> "dirty"
          "modified" -> "dirty"
          "changes" -> "dirty"
          "changes_present" -> "dirty"
          _other -> nil
        end
    end
  end

  defp normalize_workspace_clean_flag(true), do: "clean"
  defp normalize_workspace_clean_flag(false), do: "dirty"

  defp normalize_workspace_clean_flag(value) do
    value
    |> normalize_optional_string()
    |> case do
      nil ->
        nil

      normalized_value ->
        case String.downcase(normalized_value) do
          "true" -> "clean"
          "false" -> "dirty"
          "1" -> "clean"
          "0" -> "dirty"
          _other -> nil
        end
    end
  end

  defp normalize_optional_boolean(value) when is_boolean(value), do: value

  defp normalize_optional_boolean(value) do
    value
    |> normalize_optional_string()
    |> case do
      nil ->
        nil

      normalized_value ->
        case String.downcase(normalized_value) do
          "true" -> true
          "false" -> false
          "1" -> true
          "0" -> false
          _other -> nil
        end
    end
  end

  defp default_step_metadata do
    step_metadata(@workspace_policy_stage, @workspace_policy_operation)
  end

  defp step_metadata(stage, operation) do
    %{
      step: "CommitAndPR",
      stage: stage,
      operation: operation
    }
  end

  defp branch_setup_error(reason_type, detail, branch_context, reason \\ nil) do
    %{
      error_type: @branch_setup_error_type,
      operation: @branch_setup_operation,
      reason_type: normalize_reason_type(reason_type),
      detail: format_failure_detail(detail, reason),
      remediation: @branch_setup_remediation,
      blocked_stage: "commit_changes",
      halted_before_commit: true,
      branch_name: branch_context |> map_get(:branch_name, "branch_name") |> normalize_optional_string(),
      branch_derivation: branch_context |> map_get(:branch_derivation, "branch_derivation") |> normalize_map(),
      timestamp: timestamp_now()
    }
  end

  defp workspace_policy_error(
         reason_type,
         detail,
         branch_context,
         workspace_policy_check,
         reason \\ nil
       ) do
    %{
      error_type: @workspace_policy_error_type,
      operation: @workspace_policy_operation,
      reason_type: normalize_reason_type(reason_type),
      detail: format_failure_detail(detail, reason),
      remediation:
        workspace_policy_check
        |> map_get(:remediation, "remediation", @workspace_policy_remediation)
        |> normalize_optional_string() || @workspace_policy_remediation,
      blocked_stage: "commit_changes",
      blocked_actions: @blocked_shipping_actions,
      halted_before_commit: true,
      halted_before_push: true,
      halted_before_pr: true,
      branch_name: branch_context |> map_get(:branch_name, "branch_name") |> normalize_optional_string(),
      branch_derivation: branch_context |> map_get(:branch_derivation, "branch_derivation") |> normalize_map(),
      policy_check: normalize_map(workspace_policy_check),
      timestamp: timestamp_now()
    }
  end

  defp secret_scan_policy_error(
         reason_type,
         detail,
         branch_context,
         secret_scan_policy_check,
         reason
       ) do
    %{
      error_type: @secret_scan_policy_error_type,
      operation: @secret_scan_policy_operation,
      reason_type: normalize_reason_type(reason_type),
      detail: format_failure_detail(detail, reason),
      remediation:
        secret_scan_policy_check
        |> map_get(:remediation, "remediation", @secret_scan_policy_remediation)
        |> normalize_optional_string() || @secret_scan_policy_remediation,
      blocked_stage: "commit_changes",
      blocked_actions: @blocked_shipping_actions,
      halted_before_commit: true,
      halted_before_push: true,
      halted_before_pr: true,
      branch_name: branch_context |> map_get(:branch_name, "branch_name") |> normalize_optional_string(),
      branch_derivation: branch_context |> map_get(:branch_derivation, "branch_derivation") |> normalize_map(),
      policy_check: normalize_map(secret_scan_policy_check),
      timestamp: timestamp_now()
    }
  end

  defp diff_size_policy_error(
         reason_type,
         detail,
         branch_context,
         diff_size_policy_check,
         reason
       ) do
    blocked_actions =
      diff_size_policy_check
      |> map_get(:blocked_actions, "blocked_actions", @blocked_shipping_actions)
      |> case do
        actions when is_list(actions) -> actions
        _other -> @blocked_shipping_actions
      end

    %{
      error_type: @diff_size_policy_error_type,
      operation: @diff_size_policy_operation,
      reason_type: normalize_reason_type(reason_type),
      detail: format_failure_detail(detail, reason),
      remediation:
        diff_size_policy_check
        |> map_get(:remediation, "remediation", @diff_size_policy_remediation)
        |> normalize_optional_string() || @diff_size_policy_remediation,
      blocked_stage: "commit_changes",
      blocked_actions: blocked_actions,
      halted_before_commit: true,
      halted_before_push: true,
      halted_before_pr: true,
      branch_name: branch_context |> map_get(:branch_name, "branch_name") |> normalize_optional_string(),
      branch_derivation: branch_context |> map_get(:branch_derivation, "branch_derivation") |> normalize_map(),
      policy_check: normalize_map(diff_size_policy_check),
      timestamp: timestamp_now()
    }
  end

  defp timestamp_now do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end

  defp format_failure_detail(detail, nil), do: detail
  defp format_failure_detail(detail, ""), do: detail

  defp format_failure_detail(detail, reason) do
    "#{detail} (#{format_failure_reason(reason)})"
  end

  defp format_failure_reason(reason) when is_binary(reason), do: reason

  defp format_failure_reason(reason) do
    reason
    |> Exception.message()
    |> normalize_optional_string()
    |> case do
      nil -> inspect(reason)
      message -> message
    end
  rescue
    _exception -> inspect(reason)
  end

  defp normalize_reason_type(reason_type) do
    reason_type
    |> normalize_optional_string()
    |> case do
      nil -> "unknown"
      value -> String.replace(value, ~r/[^a-zA-Z0-9._-]/, "_")
    end
  end

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value) when is_boolean(value), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized_value -> normalized_value
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(value) when is_float(value), do: :erlang.float_to_binary(value)
  defp normalize_optional_string(_value), do: nil

  defp normalize_map(%{} = map), do: map
  defp normalize_map(_value), do: %{}

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(map, atom_key, string_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default
end
