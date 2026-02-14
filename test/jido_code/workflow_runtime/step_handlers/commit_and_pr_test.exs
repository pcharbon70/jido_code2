defmodule JidoCode.WorkflowRuntime.StepHandlers.CommitAndPRTest do
  use ExUnit.Case, async: true

  alias JidoCode.WorkflowRuntime.StepHandlers.CommitAndPR

  test "execute derives deterministic branch names, validates commit message contract, and persists pre-ship policy checks" do
    branch_setup_calls = start_supervised!({Agent, fn -> [] end})

    branch_setup_runner = fn branch_context ->
      Agent.update(branch_setup_calls, fn calls -> [branch_context | calls] end)
      {:ok, %{status: "created", branch_name: branch_context.branch_name}}
    end

    args = %{
      workflow_name: "Implement Task",
      run_id: "RUN-12345",
      environment_mode: "cloud",
      workspace_status: "clean",
      diff_metrics: %{files_changed: 2, lines_added: 18, lines_deleted: 7},
      workflow_policy: %{
        diff_size_threshold: %{max_changed_lines: 60, on_exceed: "block"}
      }
    }

    {:ok, first_result} =
      CommitAndPR.execute(nil, args, branch_setup_runner: branch_setup_runner)

    {:ok, second_result} =
      CommitAndPR.execute(nil, args, branch_setup_runner: branch_setup_runner)

    assert first_result.run_artifacts.branch_name == "jidocode/implement-task/run-12345"
    assert second_result.run_artifacts.branch_name == first_result.run_artifacts.branch_name

    assert %{
             pattern: "jidocode/<workflow>/<short-run-id>",
             workflow_name: "Implement Task",
             workflow_segment: "implement-task",
             run_id: "RUN-12345",
             short_run_id: "run-12345",
             short_run_id_strategy: "slug"
           } = first_result.run_artifacts.branch_derivation

    assert %{
             id: "workspace_cleanliness",
             name: "Workspace cleanliness policy check",
             status: "passed",
             policy_mode: "clean_room",
             required_state: "clean",
             observed_state: "clean",
             environment_mode: "cloud"
           } = first_result.run_artifacts.policy_checks.workspace_cleanliness

    assert %{
             workflow_name: "Implement Task",
             run_id: "RUN-12345",
             branch_name: "jidocode/implement-task/run-12345",
             environment_mode: "cloud"
           } = first_result.run_artifacts.policy_checks.workspace_cleanliness.run_metadata

    assert %{
             step: "CommitAndPR",
             stage: "pre_ship_workspace_policy",
             operation: "validate_workspace_cleanliness"
           } = first_result.run_artifacts.policy_checks.workspace_cleanliness.step_metadata

    assert %{
             id: "secret_scan",
             name: "Secret scan policy check",
             status: "passed",
             scan_status: "clean",
             violation_count: 0,
             blocked_actions: [],
             blocked_action_details: []
           } = first_result.run_artifacts.policy_checks.secret_scan

    assert %{
             workflow_name: "Implement Task",
             run_id: "RUN-12345",
             branch_name: "jidocode/implement-task/run-12345",
             environment_mode: "cloud"
           } = first_result.run_artifacts.policy_checks.secret_scan.run_metadata

    assert %{
             step: "CommitAndPR",
             stage: "pre_ship_secret_scan_policy",
             operation: "validate_secret_scan"
           } = first_result.run_artifacts.policy_checks.secret_scan.step_metadata

    assert %{
             id: "diff_size_threshold",
             name: "Diff size threshold policy check",
             status: "passed",
             decision: "within_threshold",
             threshold_exceeded: false,
             manual_override_required: false,
             blocked_actions: []
           } = first_result.run_artifacts.policy_checks.diff_size_threshold

    assert %{
             files_changed: 2,
             lines_added: 18,
             lines_deleted: 7,
             total_lines_changed: 25
           } = first_result.run_artifacts.policy_checks.diff_size_threshold.metrics

    assert %{
             source: "workflow_policy",
             max_changed_lines: 60,
             on_exceed: "block"
           } = first_result.run_artifacts.policy_checks.diff_size_threshold.threshold_policy

    assert %{
             workflow_name: "Implement Task",
             run_id: "RUN-12345",
             branch_name: "jidocode/implement-task/run-12345",
             environment_mode: "cloud"
           } = first_result.run_artifacts.policy_checks.diff_size_threshold.run_metadata

    assert %{
             step: "CommitAndPR",
             stage: "pre_ship_diff_size_policy",
             operation: "validate_diff_size_threshold"
           } = first_result.run_artifacts.policy_checks.diff_size_threshold.step_metadata

    assert %{
             id: "binary_file_policy",
             name: "Binary file policy check",
             status: "passed",
             decision: "no_binary_changes",
             binary_detected: false,
             binary_file_count: 0,
             blocked_actions: []
           } = first_result.run_artifacts.policy_checks.binary_file_policy

    assert %{
             staged_file_count: 0,
             binary_file_count: 0,
             binary_detected: false,
             detection_source: "none"
           } = first_result.run_artifacts.policy_checks.binary_file_policy.detection

    assert %{
             source: "default",
             on_detect: "block"
           } = first_result.run_artifacts.policy_checks.binary_file_policy.binary_policy

    assert %{
             step: "CommitAndPR",
             stage: "pre_ship_binary_file_policy",
             operation: "validate_binary_file_policy"
           } = first_result.run_artifacts.policy_checks.binary_file_policy.step_metadata

    assert %{
             id: "commit_message_contract",
             name: "Commit message contract check",
             status: "passed",
             commit_type: "chore",
             summary: "apply workflow updates for Implement Task",
             body: "Apply workflow-generated updates. Generated by Implement Task.",
             validation_errors: [],
             blocked_actions: []
           } = first_result.run_artifacts.commit_message_contract

    assert %{
             workflow_name: "Implement Task",
             run_id: "RUN-12345"
           } = first_result.run_artifacts.commit_message_contract.trailers

    assert %{
             step: "CommitAndPR",
             stage: "pre_ship_commit_message_contract",
             operation: "validate_commit_message_contract"
           } = first_result.run_artifacts.commit_message_contract.step_metadata

    assert first_result.run_artifacts.commit_message.message =~
             "chore: apply workflow updates for Implement Task"

    assert first_result.run_artifacts.commit_message.message =~
             "Generated by JidoCode workflow: Implement Task\nRun ID: RUN-12345"

    assert first_result.shipping_flow.completed_stage == "commit_message_contract_check"
    assert first_result.shipping_flow.next_stage == "commit_changes"

    recorded_calls = branch_setup_calls |> Agent.get(&Enum.reverse(&1))

    assert 2 == length(recorded_calls)

    assert Enum.all?(recorded_calls, fn call ->
             call.branch_name == "jidocode/implement-task/run-12345"
           end)
  end

  test "commit message contract mismatch blocks shipping and surfaces validation details" do
    commit_probe_calls = start_supervised!({Agent, fn -> 0 end})

    commit_probe = fn _branch_context ->
      Agent.update(commit_probe_calls, &(&1 + 1))
    end

    assert {:error, typed_error} =
             CommitAndPR.execute(
               nil,
               %{
                 workflow_name: "implement_task",
                 run_id: "run-commit-msg-mismatch-01",
                 workspace_clean: true
               },
               branch_setup_runner: fn _branch_context -> :ok end,
               commit_message_runner: fn _args, _branch_context ->
                 {:ok,
                  """
                  feat: tighten commit metadata validation

                  Ensure metadata trailer checks are strict.

                  Generated by JidoCode workflow: wrong_workflow
                  Run ID: run-commit-msg-mismatch-01
                  """}
               end,
               commit_probe: commit_probe
             )

    assert typed_error.error_type == "workflow_commit_and_pr_commit_message_contract_failed"
    assert typed_error.operation == "validate_commit_message_contract"
    assert typed_error.reason_type == "commit_metadata_mismatch"
    assert typed_error.blocked_stage == "commit_changes"
    assert typed_error.blocked_actions == ["commit", "push", "create_pr"]
    assert typed_error.halted_before_commit == true
    assert typed_error.halted_before_push == true
    assert typed_error.halted_before_pr == true

    assert %{
             id: "commit_message_contract",
             status: "failed"
           } = typed_error.contract_check

    assert Enum.any?(typed_error.contract_check.validation_errors, fn validation_error ->
             validation_error.reason == "workflow_metadata_mismatch" and
               validation_error.expected == "implement_task"
           end)

    assert typed_error.detail =~ "workflow metadata must match active workflow identifier exactly"

    assert Agent.get(commit_probe_calls, & &1) == 0
  end

  test "long run ids with matching prefixes derive disambiguated short run ids" do
    branch_setup_runner = fn _branch_context -> :ok end

    run_id_alpha = "run-with-a-very-very-very-long-identifier-alpha"
    run_id_beta = "run-with-a-very-very-very-long-identifier-beta"

    {:ok, alpha_result} =
      CommitAndPR.execute(
        nil,
        %{
          workflow_name: "fix_failing_tests",
          run_id: run_id_alpha,
          environment_mode: :local,
          workspace_clean: true
        },
        branch_setup_runner: branch_setup_runner
      )

    {:ok, beta_result} =
      CommitAndPR.execute(
        nil,
        %{
          workflow_name: "fix_failing_tests",
          run_id: run_id_beta,
          environment_mode: :local,
          workspace_clean: true
        },
        branch_setup_runner: branch_setup_runner
      )

    {:ok, alpha_repeat_result} =
      CommitAndPR.execute(
        nil,
        %{
          workflow_name: "fix_failing_tests",
          run_id: run_id_alpha,
          environment_mode: :local,
          workspace_clean: true
        },
        branch_setup_runner: branch_setup_runner
      )

    alpha_short_id = alpha_result.run_artifacts.branch_derivation.short_run_id
    beta_short_id = beta_result.run_artifacts.branch_derivation.short_run_id

    assert alpha_short_id != beta_short_id
    assert alpha_short_id == alpha_repeat_result.run_artifacts.branch_derivation.short_run_id

    assert String.length(alpha_short_id) <= 24
    assert String.length(beta_short_id) <= 24
    assert Regex.match?(~r/-[0-9a-f]{8}$/, alpha_short_id)
    assert Regex.match?(~r/-[0-9a-f]{8}$/, beta_short_id)

    assert alpha_result.run_artifacts.branch_name ==
             "jidocode/fix-failing-tests/#{alpha_short_id}"

    assert beta_result.run_artifacts.branch_name == "jidocode/fix-failing-tests/#{beta_short_id}"

    assert alpha_result.run_artifacts.policy_checks.workspace_cleanliness.environment_mode ==
             "local"

    assert alpha_result.run_artifacts.policy_checks.workspace_cleanliness.status == "passed"
    assert alpha_result.run_artifacts.policy_checks.secret_scan.status == "passed"
    assert alpha_result.run_artifacts.policy_checks.secret_scan.scan_status == "clean"
    assert alpha_result.run_artifacts.policy_checks.diff_size_threshold.status == "passed"
    assert alpha_result.run_artifacts.policy_checks.binary_file_policy.status == "passed"

    assert alpha_result.run_artifacts.policy_checks.diff_size_threshold.decision ==
             "within_threshold"

    assert alpha_result.run_artifacts.policy_checks.binary_file_policy.decision ==
             "no_binary_changes"
  end

  test "branch collision retries once with deterministic suffix and non-destructive behavior" do
    branch_setup_calls = start_supervised!({Agent, fn -> [] end})

    branch_setup_runner = fn branch_context ->
      Agent.update(branch_setup_calls, fn calls -> [branch_context | calls] end)

      if branch_context.branch_name == "jidocode/implement-task/run-collision-42" do
        {:error, %{reason_type: "branch_exists", detail: "Remote branch already exists."}}
      else
        {:ok,
         %{
           status: "created",
           branch_name: branch_context.branch_name,
           command_intent: "git checkout -b #{branch_context.branch_name}"
         }}
      end
    end

    args = %{
      workflow_name: "Implement Task",
      run_id: "run-collision-42",
      environment_mode: :local,
      workspace_clean: true
    }

    {:ok, first_result} =
      CommitAndPR.execute(nil, args, branch_setup_runner: branch_setup_runner)

    {:ok, second_result} =
      CommitAndPR.execute(nil, args, branch_setup_runner: branch_setup_runner)

    retry_branch_name = first_result.run_artifacts.branch_name

    assert retry_branch_name =~
             ~r/^jidocode\/implement-task\/run-collision-42-retry-[0-9a-f]{8}$/

    assert first_result.run_artifacts.branch_name == second_result.run_artifacts.branch_name
    assert first_result.branch_setup.status == "created_after_collision_retry"
    assert first_result.branch_setup.command_intent =~ "git checkout -b "
    refute first_result.branch_setup.command_intent =~ "--force"
    refute first_result.branch_setup.command_intent =~ "-B "

    assert %{
             collision_detected: true,
             strategy: "deterministic_hash_suffix",
             retry_limit: 1,
             retry_attempted: true,
             source_branch_name: "jidocode/implement-task/run-collision-42",
             retry_branch_name: ^retry_branch_name,
             overwrite_existing_remote: false,
             force_push: false
           } = first_result.run_artifacts.collision_handling

    assert first_result.branch_setup.collision_handling ==
             first_result.run_artifacts.collision_handling

    recorded_calls = branch_setup_calls |> Agent.get(&Enum.reverse(&1))

    assert length(recorded_calls) == 4

    assert Enum.count(recorded_calls, fn call ->
             call.branch_name == "jidocode/implement-task/run-collision-42"
           end) == 2

    assert Enum.count(recorded_calls, fn call ->
             call.branch_name == retry_branch_name
           end) == 2

    retry_call =
      Enum.find(recorded_calls, fn call ->
        call.branch_name == retry_branch_name
      end)

    assert retry_call.collision_handling.overwrite_existing_remote == false
    assert retry_call.collision_handling.force_push == false
  end

  test "branch collision retry failure returns typed collision context and halts shipping" do
    branch_setup_calls = start_supervised!({Agent, fn -> [] end})

    branch_setup_runner = fn branch_context ->
      Agent.update(branch_setup_calls, fn calls -> [branch_context | calls] end)
      {:error, %{reason_type: "branch_exists", detail: "Remote branch already exists."}}
    end

    assert {:error, typed_error} =
             CommitAndPR.execute(
               nil,
               %{
                 workflow_name: "implement_task",
                 run_id: "run-collision-fail",
                 workspace_clean: true
               },
               branch_setup_runner: branch_setup_runner
             )

    assert typed_error.error_type == "workflow_commit_and_pr_branch_setup_failed"
    assert typed_error.reason_type == "branch_collision_retry_failed"
    assert typed_error.halted_before_commit == true
    assert typed_error.source_branch_name == "jidocode/implement-task/run-collision-fail"

    assert typed_error.retry_branch_name =~
             ~r/^jidocode\/implement-task\/run-collision-fail-retry-[0-9a-f]{8}$/

    assert typed_error.branch_name == typed_error.retry_branch_name

    assert %{
             collision_detected: true,
             strategy: "deterministic_hash_suffix",
             retry_limit: 1,
             retry_attempted: true,
             source_branch_name: "jidocode/implement-task/run-collision-fail",
             retry_branch_name: retry_branch_name,
             overwrite_existing_remote: false,
             force_push: false,
             retry_failure_reason_type: "branch_setup_failed"
           } = typed_error.collision_handling

    assert retry_branch_name == typed_error.retry_branch_name

    recorded_calls = branch_setup_calls |> Agent.get(&Enum.reverse(&1))

    assert length(recorded_calls) == 2
    assert Enum.at(recorded_calls, 0).branch_name == "jidocode/implement-task/run-collision-fail"
    assert Enum.at(recorded_calls, 1).branch_name == typed_error.retry_branch_name
  end

  test "branch setup failure halts shipping before commit probe with typed branch setup error" do
    commit_probe_calls = start_supervised!({Agent, fn -> 0 end})

    commit_probe = fn _branch_context ->
      Agent.update(commit_probe_calls, &(&1 + 1))
    end

    assert {:error, typed_error} =
             CommitAndPR.execute(
               nil,
               %{workflow_name: "implement_task", run_id: "run-failure-42"},
               branch_setup_runner: fn _branch_context ->
                 {:error, :branch_permissions_missing}
               end,
               commit_probe: commit_probe
             )

    assert typed_error.error_type == "workflow_commit_and_pr_branch_setup_failed"
    assert typed_error.operation == "setup_run_branch"
    assert typed_error.reason_type == "branch_setup_failed"
    assert typed_error.blocked_stage == "commit_changes"
    assert typed_error.halted_before_commit == true
    assert typed_error.branch_name == "jidocode/implement-task/run-failure-42"

    assert %{
             pattern: "jidocode/<workflow>/<short-run-id>",
             workflow_name: "implement_task",
             workflow_segment: "implement-task",
             run_id: "run-failure-42",
             short_run_id: "run-failure-42"
           } = typed_error.branch_derivation

    assert Agent.get(commit_probe_calls, & &1) == 0
  end

  test "dirty workspace blocks shipping actions with remediation guidance" do
    commit_probe_calls = start_supervised!({Agent, fn -> 0 end})

    commit_probe = fn _branch_context ->
      Agent.update(commit_probe_calls, &(&1 + 1))
    end

    assert {:error, typed_error} =
             CommitAndPR.execute(
               nil,
               %{
                 workflow_name: "implement_task",
                 run_id: "run-dirty-88",
                 environment_mode: :local,
                 workspace_status: "dirty"
               },
               branch_setup_runner: fn _branch_context -> :ok end,
               commit_probe: commit_probe
             )

    assert typed_error.error_type == "workflow_commit_and_pr_workspace_policy_failed"
    assert typed_error.operation == "validate_workspace_cleanliness"
    assert typed_error.reason_type == "workspace_dirty"
    assert typed_error.blocked_stage == "commit_changes"
    assert typed_error.blocked_actions == ["commit", "push", "create_pr"]
    assert typed_error.halted_before_commit == true
    assert typed_error.halted_before_push == true
    assert typed_error.halted_before_pr == true
    assert typed_error.remediation =~ "Clean or discard unintended workspace changes"

    assert %{
             id: "workspace_cleanliness",
             status: "failed",
             policy_mode: "clean_room",
             required_state: "clean",
             observed_state: "dirty",
             environment_mode: "local"
           } = typed_error.policy_check

    assert %{
             workflow_name: "implement_task",
             run_id: "run-dirty-88",
             branch_name: "jidocode/implement-task/run-dirty-88",
             environment_mode: "local"
           } = typed_error.policy_check.run_metadata

    assert %{
             step: "CommitAndPR",
             stage: "pre_ship_workspace_policy",
             operation: "validate_workspace_cleanliness"
           } = typed_error.policy_check.step_metadata

    assert Agent.get(commit_probe_calls, & &1) == 0
  end

  test "secret scan, diff size, and binary file checks execute before commit probe in shipping path" do
    ordered_calls = start_supervised!({Agent, fn -> [] end})

    secret_scan_runner = fn _args, _branch_context ->
      Agent.update(ordered_calls, fn calls -> [:secret_scan | calls] end)
      {:ok, %{status: "passed", scan_status: "clean", violation_count: 0}}
    end

    commit_probe = fn _branch_context ->
      Agent.update(ordered_calls, fn calls -> [:commit_probe | calls] end)
    end

    diff_size_runner = fn _args, _branch_context ->
      Agent.update(ordered_calls, fn calls -> [:diff_size | calls] end)
      {:ok, %{metrics: %{files_changed: 1, lines_added: 9, lines_deleted: 4}}}
    end

    binary_file_runner = fn _args, _branch_context ->
      Agent.update(ordered_calls, fn calls -> [:binary_policy | calls] end)

      {:ok, %{staged_files: [%{path: "lib/commit_and_pr.ex", change_type: "modified", binary: false}]}}
    end

    {:ok, result} =
      CommitAndPR.execute(
        nil,
        %{workflow_name: "implement_task", run_id: "run-secret-order-01", workspace_clean: true},
        branch_setup_runner: fn _branch_context -> :ok end,
        secret_scan_runner: secret_scan_runner,
        diff_size_runner: diff_size_runner,
        binary_file_runner: binary_file_runner,
        commit_probe: commit_probe
      )

    assert result.policy_checks.secret_scan.status == "passed"
    assert result.policy_checks.secret_scan.scan_status == "clean"
    assert result.policy_checks.diff_size_threshold.status == "passed"
    assert result.policy_checks.diff_size_threshold.decision == "within_threshold"
    assert result.policy_checks.binary_file_policy.status == "passed"
    assert result.policy_checks.binary_file_policy.decision == "no_binary_changes"

    assert ordered_calls
           |> Agent.get(&Enum.reverse(&1))
           |> Enum.take(4) == [:secret_scan, :diff_size, :binary_policy, :commit_probe]
  end

  test "diff size threshold exceed blocks shipping with explicit threshold details" do
    commit_probe_calls = start_supervised!({Agent, fn -> 0 end})

    commit_probe = fn _branch_context ->
      Agent.update(commit_probe_calls, &(&1 + 1))
    end

    assert {:error, typed_error} =
             CommitAndPR.execute(
               nil,
               %{
                 workflow_name: "implement_task",
                 run_id: "run-diff-block-01",
                 workspace_clean: true,
                 diff_metrics: %{files_changed: 8, lines_added: 180, lines_deleted: 40},
                 workflow_policy: %{
                   diff_size_threshold: %{max_changed_lines: 100, on_exceed: "block"}
                 }
               },
               branch_setup_runner: fn _branch_context -> :ok end,
               commit_probe: commit_probe
             )

    assert typed_error.error_type == "workflow_commit_and_pr_diff_size_policy_failed"
    assert typed_error.operation == "validate_diff_size_threshold"
    assert typed_error.reason_type == "diff_size_threshold_exceeded"
    assert typed_error.blocked_stage == "commit_changes"
    assert typed_error.blocked_actions == ["commit", "push", "create_pr"]
    assert typed_error.halted_before_commit == true
    assert typed_error.halted_before_push == true
    assert typed_error.halted_before_pr == true
    assert typed_error.detail =~ "exceeded workflow threshold 100"

    assert %{
             id: "diff_size_threshold",
             status: "failed",
             decision: "blocked",
             threshold_exceeded: true,
             manual_override_required: false
           } = typed_error.policy_check

    assert %{
             source: "workflow_policy",
             max_changed_lines: 100,
             on_exceed: "block"
           } = typed_error.policy_check.threshold_policy

    assert typed_error.policy_check.metrics.total_lines_changed == 220

    assert Enum.map(typed_error.policy_check.blocked_action_details, & &1.reason) ==
             [
               "diff_size_threshold_exceeded",
               "diff_size_threshold_exceeded",
               "diff_size_threshold_exceeded"
             ]

    assert Agent.get(commit_probe_calls, & &1) == 0
  end

  test "diff size threshold exceed can escalate to explicit approval override requirement" do
    commit_probe_calls = start_supervised!({Agent, fn -> 0 end})

    commit_probe = fn _branch_context ->
      Agent.update(commit_probe_calls, &(&1 + 1))
    end

    assert {:error, typed_error} =
             CommitAndPR.execute(
               nil,
               %{
                 workflow_name: "implement_task",
                 run_id: "run-diff-escalate-01",
                 workspace_clean: true,
                 diff_metrics: %{files_changed: 5, lines_added: 110, lines_deleted: 20},
                 project_policy: %{
                   diff_size_threshold: %{max_changed_lines: 120, on_exceed: "escalate"}
                 }
               },
               branch_setup_runner: fn _branch_context -> :ok end,
               commit_probe: commit_probe
             )

    assert typed_error.error_type == "workflow_commit_and_pr_diff_size_policy_failed"
    assert typed_error.operation == "validate_diff_size_threshold"
    assert typed_error.reason_type == "approval_override_required"
    assert typed_error.detail =~ "approval override is required"

    assert %{
             status: "failed",
             decision: "approval_override_required",
             threshold_exceeded: true,
             manual_override_required: true
           } = typed_error.policy_check

    assert %{
             source: "project_policy",
             max_changed_lines: 120,
             on_exceed: "require_approval_override"
           } = typed_error.policy_check.threshold_policy

    assert Agent.get(commit_probe_calls, & &1) == 0
  end

  test "binary file policy blocks shipping when staged binary additions are detected" do
    commit_probe_calls = start_supervised!({Agent, fn -> 0 end})

    commit_probe = fn _branch_context ->
      Agent.update(commit_probe_calls, &(&1 + 1))
    end

    assert {:error, typed_error} =
             CommitAndPR.execute(
               nil,
               %{
                 workflow_name: "implement_task",
                 run_id: "run-binary-block-01",
                 workspace_clean: true,
                 staged_changes: [
                   %{
                     path: "lib/jido_code/workflow_runtime/step_handlers/commit_and_pr.ex",
                     status: "M"
                   },
                   %{path: "priv/static/logo.png", status: "A"}
                 ],
                 workflow_policy: %{
                   binary_file_policy: %{on_detect: "block"}
                 }
               },
               branch_setup_runner: fn _branch_context -> :ok end,
               commit_probe: commit_probe
             )

    assert typed_error.error_type == "workflow_commit_and_pr_binary_file_policy_failed"
    assert typed_error.operation == "validate_binary_file_policy"
    assert typed_error.reason_type == "binary_file_policy_blocked"
    assert typed_error.blocked_stage == "commit_changes"
    assert typed_error.blocked_actions == ["commit", "push", "create_pr"]
    assert typed_error.halted_before_commit == true
    assert typed_error.halted_before_push == true
    assert typed_error.halted_before_pr == true
    assert typed_error.detail =~ "detected 1 binary file change"

    assert %{
             id: "binary_file_policy",
             status: "failed",
             decision: "blocked",
             binary_detected: true,
             binary_file_count: 1
           } = typed_error.policy_check

    assert [%{path: "priv/static/logo.png", change_type: "added", binary: true}] =
             typed_error.policy_check.binary_files

    assert %{
             staged_file_count: 2,
             binary_file_count: 1,
             binary_detected: true
           } = typed_error.policy_check.detection

    assert Enum.any?(typed_error.policy_check.detection.staged_files, fn staged_file ->
             staged_file.path == "priv/static/logo.png" and staged_file.binary == true
           end)

    assert %{
             source: "workflow_policy",
             on_detect: "block"
           } = typed_error.policy_check.binary_policy

    assert Enum.map(typed_error.policy_check.blocked_action_details, & &1.reason) ==
             [
               "binary_file_policy_blocked",
               "binary_file_policy_blocked",
               "binary_file_policy_blocked"
             ]

    assert Agent.get(commit_probe_calls, & &1) == 0
  end

  test "binary file policy can require explicit approval override escalation" do
    commit_probe_calls = start_supervised!({Agent, fn -> 0 end})

    commit_probe = fn _branch_context ->
      Agent.update(commit_probe_calls, &(&1 + 1))
    end

    assert {:error, typed_error} =
             CommitAndPR.execute(
               nil,
               %{
                 workflow_name: "implement_task",
                 run_id: "run-binary-escalate-01",
                 workspace_clean: true,
                 staged_changes: [
                   %{path: "docs/architecture.md", status: "M"},
                   %{path: "assets/images/wireframe.webp", status: "M"}
                 ],
                 project_policy: %{
                   binary_file_policy: %{on_detect: "escalate"}
                 }
               },
               branch_setup_runner: fn _branch_context -> :ok end,
               commit_probe: commit_probe
             )

    assert typed_error.error_type == "workflow_commit_and_pr_binary_file_policy_failed"
    assert typed_error.operation == "validate_binary_file_policy"
    assert typed_error.reason_type == "approval_override_required"
    assert typed_error.detail =~ "explicit approval override is required"

    assert %{
             status: "failed",
             decision: "approval_override_required",
             binary_detected: true,
             binary_file_count: 1
           } = typed_error.policy_check

    assert %{
             source: "project_policy",
             on_detect: "require_approval_override"
           } = typed_error.policy_check.binary_policy

    assert Agent.get(commit_probe_calls, & &1) == 0
  end

  test "binary file policy evaluation failures fail closed with typed policy-check error" do
    commit_probe_calls = start_supervised!({Agent, fn -> 0 end})

    commit_probe = fn _branch_context ->
      Agent.update(commit_probe_calls, &(&1 + 1))
    end

    assert {:error, typed_error} =
             CommitAndPR.execute(
               nil,
               %{
                 workflow_name: "implement_task",
                 run_id: "run-binary-tooling-01",
                 workspace_clean: true
               },
               branch_setup_runner: fn _branch_context -> :ok end,
               binary_file_runner: fn _args, _branch_context ->
                 {:error, %{reason_type: "binary_scan_timeout", detail: "binary scan timed out"}}
               end,
               commit_probe: commit_probe
             )

    assert typed_error.error_type == "workflow_commit_and_pr_binary_file_policy_failed"
    assert typed_error.operation == "validate_binary_file_policy"
    assert typed_error.reason_type == "policy_violation"
    assert typed_error.blocked_actions == ["commit", "push", "create_pr"]
    assert typed_error.halted_before_commit == true
    assert typed_error.halted_before_push == true
    assert typed_error.halted_before_pr == true

    assert %{
             id: "binary_file_policy",
             status: "failed",
             decision: "blocked"
           } = typed_error.policy_check

    assert Enum.map(typed_error.policy_check.blocked_action_details, & &1.reason) ==
             [
               "binary_file_policy_tooling_error",
               "binary_file_policy_tooling_error",
               "binary_file_policy_tooling_error"
             ]

    assert Agent.get(commit_probe_calls, & &1) == 0
  end

  test "secret scan violations block shipping with policy_violation and blocked action details" do
    commit_probe_calls = start_supervised!({Agent, fn -> 0 end})

    commit_probe = fn _branch_context ->
      Agent.update(commit_probe_calls, &(&1 + 1))
    end

    assert {:error, typed_error} =
             CommitAndPR.execute(
               nil,
               %{
                 workflow_name: "implement_task",
                 run_id: "run-secret-block-01",
                 workspace_clean: true
               },
               branch_setup_runner: fn _branch_context -> :ok end,
               secret_scan_runner: fn _args, _branch_context ->
                 {:ok,
                  %{
                    status: "failed",
                    scan_status: "violations_detected",
                    violation_count: 2,
                    findings: [
                      %{path: "lib/example.ex", rule: "github_token"},
                      %{path: "config/runtime.exs", rule: "api_key"}
                    ],
                    detail: "Secret scan detected plaintext credentials."
                  }}
               end,
               commit_probe: commit_probe
             )

    assert typed_error.error_type == "workflow_commit_and_pr_secret_scan_policy_failed"
    assert typed_error.operation == "validate_secret_scan"
    assert typed_error.reason_type == "policy_violation"
    assert typed_error.blocked_stage == "commit_changes"
    assert typed_error.blocked_actions == ["commit", "push", "create_pr"]
    assert typed_error.halted_before_commit == true
    assert typed_error.halted_before_push == true
    assert typed_error.halted_before_pr == true

    assert %{
             id: "secret_scan",
             status: "failed",
             scan_status: "violations_detected",
             violation_count: 2,
             blocked_actions: ["commit", "push", "create_pr"]
           } = typed_error.policy_check

    assert Enum.map(typed_error.policy_check.blocked_action_details, & &1.action) ==
             ["commit", "push", "create_pr"]

    assert Enum.all?(typed_error.policy_check.blocked_action_details, fn action_detail ->
             action_detail.blocked == true and action_detail.reason == "secret_scan_violation"
           end)

    assert Agent.get(commit_probe_calls, & &1) == 0
  end

  test "secret scan tooling errors fail closed and no commit probe is executed" do
    commit_probe_calls = start_supervised!({Agent, fn -> 0 end})

    commit_probe = fn _branch_context ->
      Agent.update(commit_probe_calls, &(&1 + 1))
    end

    assert {:error, typed_error} =
             CommitAndPR.execute(
               nil,
               %{
                 workflow_name: "implement_task",
                 run_id: "run-secret-tooling-01",
                 workspace_clean: true
               },
               branch_setup_runner: fn _branch_context -> :ok end,
               secret_scan_runner: fn _args, _branch_context ->
                 {:error, %{reason_type: "scanner_timeout", detail: "secret scan timed out"}}
               end,
               commit_probe: commit_probe
             )

    assert typed_error.error_type == "workflow_commit_and_pr_secret_scan_policy_failed"
    assert typed_error.operation == "validate_secret_scan"
    assert typed_error.reason_type == "policy_violation"
    assert typed_error.blocked_actions == ["commit", "push", "create_pr"]
    assert typed_error.halted_before_commit == true
    assert typed_error.halted_before_push == true
    assert typed_error.halted_before_pr == true
    assert typed_error.policy_check.status == "failed"
    assert typed_error.policy_check.scan_status == "tooling_error"

    assert Enum.map(typed_error.policy_check.blocked_action_details, & &1.reason) ==
             [
               "secret_scan_tooling_error",
               "secret_scan_tooling_error",
               "secret_scan_tooling_error"
             ]

    assert Agent.get(commit_probe_calls, & &1) == 0
  end
end
