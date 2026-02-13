# 00 — Story Traceability Matrix

This matrix maps every MVP story to requirement IDs (`R1..R13`), primary route/API, and source specification files.

| Story ID | Domain File | Primary Route/API | R1 | R2 | R3 | R4 | R5 | R6 | R7 | R8 | R9 | R10 | R11 | R12 | R13 | Source Specs |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `ST-ONB-001` | `01_onboarding_bootstrap.md` | `/` |  | x |  |  |  |  |  |  |  |  |  |  |  | specs/11_onboarding_flow.md, specs/ux/03_routes_and_experience_flows.md |
| `ST-ONB-002` | `01_onboarding_bootstrap.md` | `/setup` |  | x |  |  |  |  |  |  |  |  |  |  |  | specs/11_onboarding_flow.md, specs/20_ash_domain_model.md |
| `ST-ONB-003` | `01_onboarding_bootstrap.md` | `/setup` |  | x |  |  |  |  |  |  |  |  | x |  |  | specs/11_onboarding_flow.md, specs/61_configuration_and_deployment.md |
| `ST-ONB-004` | `01_onboarding_bootstrap.md` | `/setup` | x | x |  |  |  |  |  |  |  |  |  |  |  | specs/11_onboarding_flow.md, specs/60_security_and_auth.md |
| `ST-ONB-005` | `01_onboarding_bootstrap.md` | `/setup` | x | x |  |  |  |  |  |  |  |  |  |  |  | specs/11_onboarding_flow.md, specs/03_decisions_and_invariants.md |
| `ST-ONB-006` | `01_onboarding_bootstrap.md` | `/setup` |  | x |  |  |  | x |  |  |  |  |  |  |  | specs/11_onboarding_flow.md, specs/02_requirements_and_scope.md |
| `ST-ONB-007` | `01_onboarding_bootstrap.md` | `/setup` |  | x | x |  |  |  |  |  |  |  |  |  |  | specs/11_onboarding_flow.md, specs/50_github_integration.md |
| `ST-ONB-008` | `01_onboarding_bootstrap.md` | `/setup` |  | x | x |  |  |  |  | x |  |  |  |  |  | specs/11_onboarding_flow.md, specs/50_github_integration.md |
| `ST-ONB-009` | `01_onboarding_bootstrap.md` | `/setup` |  |  |  | x |  |  |  |  |  |  | x |  |  | specs/11_onboarding_flow.md, specs/40_project_environments.md |
| `ST-ONB-010` | `01_onboarding_bootstrap.md` | `/setup` |  | x |  | x |  |  |  |  |  |  |  |  | x | specs/11_onboarding_flow.md, specs/10_web_ui_and_routes.md |
| `ST-AUTH-001` | `02_auth_and_access.md` | `/dashboard` | x |  |  |  |  |  |  |  |  |  |  |  |  | specs/60_security_and_auth.md, specs/02_requirements_and_scope.md |
| `ST-AUTH-002` | `02_auth_and_access.md` | `/dashboard` | x |  |  |  |  |  |  |  |  | x |  |  |  | specs/10_web_ui_and_routes.md, specs/60_security_and_auth.md |
| `ST-AUTH-003` | `02_auth_and_access.md` | `/settings` | x |  |  |  |  |  |  |  |  | x |  |  |  | specs/60_security_and_auth.md, specs/10_web_ui_and_routes.md |
| `ST-AUTH-004` | `02_auth_and_access.md` | `POST /rpc/run` | x |  |  |  |  |  |  |  |  |  |  | x |  | specs/60_security_and_auth.md, specs/10_web_ui_and_routes.md |
| `ST-AUTH-005` | `02_auth_and_access.md` | `POST /rpc/validate` | x |  |  |  |  |  |  |  |  |  |  | x |  | specs/60_security_and_auth.md, specs/20_ash_domain_model.md |
| `ST-AUTH-006` | `02_auth_and_access.md` | `/settings/security` | x |  |  |  |  |  |  |  |  | x |  |  |  | specs/20_ash_domain_model.md, specs/62_security_playbook.md |
| `ST-AUTH-007` | `02_auth_and_access.md` | `/settings` | x |  |  |  |  |  |  |  |  | x |  |  |  | specs/60_security_and_auth.md, specs/02_requirements_and_scope.md |
| `ST-AUTH-008` | `02_auth_and_access.md` | `/setup` | x | x |  |  |  |  |  |  |  | x |  |  |  | specs/60_security_and_auth.md, specs/62_security_playbook.md |
| `ST-SEC-001` | `03_secrets_and_provider_credentials.md` | `/settings/security` |  |  |  |  |  |  |  |  |  | x |  |  |  | specs/20_ash_domain_model.md, specs/60_security_and_auth.md |
| `ST-SEC-002` | `03_secrets_and_provider_credentials.md` | `/settings/security` |  |  |  |  |  |  |  |  |  | x |  |  |  | specs/03_decisions_and_invariants.md, specs/60_security_and_auth.md |
| `ST-SEC-003` | `03_secrets_and_provider_credentials.md` | `/settings/security` |  |  |  |  |  |  |  |  |  | x |  |  |  | specs/20_ash_domain_model.md, specs/62_security_playbook.md |
| `ST-SEC-004` | `03_secrets_and_provider_credentials.md` | `/projects/:id/runs/:run_id` |  |  |  |  |  |  |  |  |  | x |  |  |  | specs/60_security_and_auth.md, specs/62_security_playbook.md |
| `ST-SEC-005` | `03_secrets_and_provider_credentials.md` | `jido_code:run:<id>` |  |  |  |  |  |  |  |  | x | x |  |  |  | specs/30_workflow_system_overview.md, specs/60_security_and_auth.md |
| `ST-SEC-006` | `03_secrets_and_provider_credentials.md` | `/projects/:id/runs/:run_id` |  |  |  |  |  | x |  |  |  | x |  |  |  | specs/60_security_and_auth.md, specs/30_workflow_system_overview.md |
| `ST-SEC-007` | `03_secrets_and_provider_credentials.md` | `/setup` |  | x |  |  |  | x |  |  |  |  |  |  |  | specs/11_onboarding_flow.md, specs/20_ash_domain_model.md |
| `ST-SEC-008` | `03_secrets_and_provider_credentials.md` | `/settings/security` |  |  |  |  |  | x |  |  |  | x |  |  |  | specs/62_security_playbook.md, specs/20_ash_domain_model.md |
| `ST-SEC-009` | `03_secrets_and_provider_credentials.md` | `/setup` |  |  |  |  |  |  |  |  |  | x | x |  |  | specs/61_configuration_and_deployment.md, specs/20_ash_domain_model.md |
| `ST-SEC-010` | `03_secrets_and_provider_credentials.md` | `/settings/security` |  |  |  |  |  |  |  |  |  | x |  |  |  | specs/62_security_playbook.md, specs/60_security_and_auth.md |
| `ST-GH-001` | `04_github_integration_and_repo_import.md` | `/setup` |  |  | x |  |  |  |  |  |  |  |  |  |  | specs/50_github_integration.md, specs/11_onboarding_flow.md |
| `ST-GH-002` | `04_github_integration_and_repo_import.md` | `/setup` |  |  | x |  |  |  |  |  |  |  |  |  |  | specs/50_github_integration.md, specs/11_onboarding_flow.md |
| `ST-GH-003` | `04_github_integration_and_repo_import.md` | `/setup` |  |  | x | x |  |  |  |  |  |  |  |  |  | specs/50_github_integration.md, specs/11_onboarding_flow.md |
| `ST-GH-004` | `04_github_integration_and_repo_import.md` | `/setup` |  |  |  | x |  |  |  |  |  |  |  |  | x | specs/50_github_integration.md, specs/20_ash_domain_model.md |
| `ST-GH-005` | `04_github_integration_and_repo_import.md` | `/setup` |  |  |  | x |  |  |  |  |  |  |  |  |  | specs/50_github_integration.md, specs/40_project_environments.md |
| `ST-GH-006` | `04_github_integration_and_repo_import.md` | `POST /api/github/webhooks` |  |  | x |  |  |  |  | x |  | x |  |  |  | specs/50_github_integration.md, specs/60_security_and_auth.md |
| `ST-GH-007` | `04_github_integration_and_repo_import.md` | `POST /api/github/webhooks` |  |  | x |  |  |  |  | x |  | x |  |  |  | specs/50_github_integration.md, specs/60_security_and_auth.md |
| `ST-GH-008` | `04_github_integration_and_repo_import.md` | `POST /api/github/webhooks` |  |  | x |  |  |  |  | x |  |  |  |  |  | specs/50_github_integration.md, specs/31_builtin_workflows.md |
| `ST-GH-009` | `04_github_integration_and_repo_import.md` | `POST /api/github/webhooks` |  |  | x | x |  |  |  |  |  |  |  |  |  | specs/50_github_integration.md, specs/20_ash_domain_model.md |
| `ST-GH-010` | `04_github_integration_and_repo_import.md` | `GitHub HTTP integration layer` |  |  | x |  |  |  |  | x |  |  |  |  |  | specs/50_github_integration.md, specs/02_requirements_and_scope.md |
| `ST-WB-001` | `05_workbench_and_project_views.md` | `/workbench` |  |  |  |  |  |  |  |  |  |  |  |  | x | specs/10_web_ui_and_routes.md, specs/ux/03_routes_and_experience_flows.md |
| `ST-WB-002` | `05_workbench_and_project_views.md` | `/workbench` |  |  |  |  |  |  |  |  |  |  |  |  | x | specs/10_web_ui_and_routes.md, specs/ux/03_routes_and_experience_flows.md |
| `ST-WB-003` | `05_workbench_and_project_views.md` | `/workbench` |  |  |  |  |  |  |  |  |  |  |  |  | x | specs/ux/02_user_journey.md, specs/10_web_ui_and_routes.md |
| `ST-WB-004` | `05_workbench_and_project_views.md` | `/workbench` |  |  |  |  |  |  |  |  |  |  |  |  | x | specs/ux/03_routes_and_experience_flows.md, specs/10_web_ui_and_routes.md |
| `ST-WB-005` | `05_workbench_and_project_views.md` | `/workbench` |  |  |  |  |  |  |  |  |  |  |  |  | x | specs/ux/02_user_journey.md, specs/ux/03_routes_and_experience_flows.md |
| `ST-WB-006` | `05_workbench_and_project_views.md` | `/workbench` |  |  |  |  | x | x |  |  |  |  |  |  | x | specs/10_web_ui_and_routes.md, specs/31_builtin_workflows.md |
| `ST-WB-007` | `05_workbench_and_project_views.md` | `/workbench` |  |  |  |  |  |  |  | x |  |  |  |  | x | specs/10_web_ui_and_routes.md, specs/31_builtin_workflows.md |
| `ST-WB-008` | `05_workbench_and_project_views.md` | `/projects/:id` |  |  |  |  | x |  |  |  |  |  |  |  | x | specs/10_web_ui_and_routes.md, specs/ux/03_routes_and_experience_flows.md |
| `ST-WB-009` | `05_workbench_and_project_views.md` | `/workbench` |  |  |  |  |  |  |  |  | x |  |  |  | x | specs/10_web_ui_and_routes.md, specs/ux/02_user_journey.md |
| `ST-WB-010` | `05_workbench_and_project_views.md` | `/projects` |  |  |  | x |  |  |  |  |  |  |  |  | x | specs/10_web_ui_and_routes.md, specs/ux/03_routes_and_experience_flows.md |
| `ST-WF-001` | `06_workflow_runtime_and_approvals.md` | `/workflows` |  |  |  |  | x | x |  |  |  |  |  |  | x | specs/30_workflow_system_overview.md, specs/31_builtin_workflows.md |
| `ST-WF-002` | `06_workflow_runtime_and_approvals.md` | `/projects/:id/runs/:run_id` |  |  |  |  | x |  |  |  |  |  |  |  |  | specs/30_workflow_system_overview.md, specs/31_builtin_workflows.md |
| `ST-WF-003` | `06_workflow_runtime_and_approvals.md` | `/projects/:id/runs/:run_id` |  |  |  |  | x |  |  |  | x |  |  |  |  | specs/30_workflow_system_overview.md, specs/20_ash_domain_model.md |
| `ST-WF-004` | `06_workflow_runtime_and_approvals.md` | `jido_code:run:<run_id>` |  |  |  |  | x |  |  |  | x |  |  |  |  | specs/30_workflow_system_overview.md, specs/41_forge_integration.md |
| `ST-WF-005` | `06_workflow_runtime_and_approvals.md` | `/projects/:id/runs/:run_id` |  |  |  |  | x |  | x |  |  |  |  |  |  | specs/30_workflow_system_overview.md, specs/51_git_and_pr_flow.md |
| `ST-WF-006` | `06_workflow_runtime_and_approvals.md` | `/projects/:id/runs/:run_id` |  |  |  |  | x |  | x |  |  |  |  |  |  | specs/30_workflow_system_overview.md, specs/31_builtin_workflows.md |
| `ST-WF-007` | `06_workflow_runtime_and_approvals.md` | `/projects/:id/runs/:run_id` |  |  |  |  | x |  |  |  |  |  |  |  |  | specs/30_workflow_system_overview.md, specs/31_builtin_workflows.md |
| `ST-WF-008` | `06_workflow_runtime_and_approvals.md` | `/projects/:id/runs/:run_id` |  |  |  |  | x |  |  |  | x |  |  |  |  | specs/30_workflow_system_overview.md, specs/02_requirements_and_scope.md |
| `ST-WF-009` | `06_workflow_runtime_and_approvals.md` | `/projects/:id/runs/:run_id` |  |  |  |  | x |  |  |  |  |  |  |  |  | specs/30_workflow_system_overview.md, specs/31_builtin_workflows.md |
| `ST-WF-010` | `06_workflow_runtime_and_approvals.md` | `/projects/:id/runs/:run_id` |  |  |  |  | x |  |  |  | x |  |  |  |  | specs/30_workflow_system_overview.md, specs/02_requirements_and_scope.md |
| `ST-GIT-001` | `07_git_shipping_and_safety.md` | `CommitAndPR shipping step` |  |  |  |  |  |  | x |  |  |  |  |  |  | specs/51_git_and_pr_flow.md, specs/52_git_safety_policy.md |
| `ST-GIT-002` | `07_git_shipping_and_safety.md` | `CommitAndPR shipping step` |  |  |  |  |  |  | x |  |  |  |  |  |  | specs/52_git_safety_policy.md, specs/40_project_environments.md |
| `ST-GIT-003` | `07_git_shipping_and_safety.md` | `CommitAndPR shipping step` |  |  |  |  |  |  | x |  |  |  |  |  |  | specs/52_git_safety_policy.md, specs/51_git_and_pr_flow.md |
| `ST-GIT-004` | `07_git_shipping_and_safety.md` | `CommitAndPR shipping step` |  |  |  |  |  |  | x |  |  | x |  |  |  | specs/52_git_safety_policy.md, specs/60_security_and_auth.md |
| `ST-GIT-005` | `07_git_shipping_and_safety.md` | `CommitAndPR shipping step` |  |  |  |  |  |  | x |  |  |  |  |  |  | specs/52_git_safety_policy.md, specs/51_git_and_pr_flow.md |
| `ST-GIT-006` | `07_git_shipping_and_safety.md` | `CommitAndPR shipping step` |  |  |  |  |  |  | x |  |  |  |  |  |  | specs/52_git_safety_policy.md, specs/51_git_and_pr_flow.md |
| `ST-GIT-007` | `07_git_shipping_and_safety.md` | `CommitAndPR shipping step` |  |  |  |  |  |  | x |  |  |  |  |  |  | specs/51_git_and_pr_flow.md, specs/31_builtin_workflows.md |
| `ST-GIT-008` | `07_git_shipping_and_safety.md` | `CommitAndPR shipping step` |  |  | x |  |  |  | x |  |  |  |  |  |  | specs/52_git_safety_policy.md, specs/50_github_integration.md |
| `ST-GIT-009` | `07_git_shipping_and_safety.md` | `CommitAndPR shipping step` |  |  |  |  |  |  | x |  |  |  |  |  |  | specs/51_git_and_pr_flow.md, specs/02_requirements_and_scope.md |
| `ST-GIT-010` | `07_git_shipping_and_safety.md` | `CommitAndPR shipping step` |  |  |  |  |  |  | x |  | x | x |  |  |  | specs/52_git_safety_policy.md, specs/60_security_and_auth.md |
| `ST-BOT-001` | `08_issue_bot_and_agent_controls.md` | `/agents` |  |  |  |  |  |  |  | x |  |  |  |  | x | specs/10_web_ui_and_routes.md, specs/20_ash_domain_model.md |
| `ST-BOT-002` | `08_issue_bot_and_agent_controls.md` | `/agents` |  |  |  |  |  |  |  | x |  |  |  |  |  | specs/20_ash_domain_model.md, specs/50_github_integration.md |
| `ST-BOT-003` | `08_issue_bot_and_agent_controls.md` | `/agents` |  |  |  |  |  |  | x | x |  |  |  |  |  | specs/10_web_ui_and_routes.md, specs/31_builtin_workflows.md |
| `ST-BOT-004` | `08_issue_bot_and_agent_controls.md` | `POST /api/github/webhooks` |  |  | x |  |  |  |  | x |  |  |  |  |  | specs/50_github_integration.md, specs/31_builtin_workflows.md |
| `ST-BOT-005` | `08_issue_bot_and_agent_controls.md` | `POST /api/github/webhooks` |  |  | x |  |  |  |  | x |  |  |  |  |  | specs/50_github_integration.md, specs/31_builtin_workflows.md |
| `ST-BOT-006` | `08_issue_bot_and_agent_controls.md` | `POST /api/github/webhooks` |  |  | x |  |  |  |  | x |  |  |  |  |  | specs/50_github_integration.md, specs/31_builtin_workflows.md |
| `ST-BOT-007` | `08_issue_bot_and_agent_controls.md` | `/projects/:id/runs/:run_id` |  |  |  |  |  |  |  | x | x |  |  |  |  | specs/31_builtin_workflows.md, specs/20_ash_domain_model.md |
| `ST-BOT-008` | `08_issue_bot_and_agent_controls.md` | `/projects/:id/runs/:run_id` |  |  | x |  |  |  |  | x | x |  |  |  |  | specs/31_builtin_workflows.md, specs/50_github_integration.md |
| `ST-OBS-001` | `09_observability_and_artifacts.md` | `/dashboard` |  |  |  |  |  |  |  |  | x |  |  |  | x | specs/10_web_ui_and_routes.md, specs/30_workflow_system_overview.md |
| `ST-OBS-002` | `09_observability_and_artifacts.md` | `/projects/:id/runs/:run_id` |  |  |  |  |  |  |  |  | x |  |  |  |  | specs/30_workflow_system_overview.md, specs/10_web_ui_and_routes.md |
| `ST-OBS-003` | `09_observability_and_artifacts.md` | `forge:session:<id>` |  |  |  |  |  | x |  |  | x |  |  |  |  | specs/41_forge_integration.md, specs/30_workflow_system_overview.md |
| `ST-OBS-004` | `09_observability_and_artifacts.md` | `/projects/:id/runs/:run_id` |  |  |  |  |  |  |  |  | x |  |  |  |  | specs/30_workflow_system_overview.md, specs/51_git_and_pr_flow.md |
| `ST-OBS-005` | `09_observability_and_artifacts.md` | `/workbench` |  |  |  |  |  |  |  |  | x |  |  |  | x | specs/10_web_ui_and_routes.md, specs/ux/02_user_journey.md |
| `ST-OBS-006` | `09_observability_and_artifacts.md` | `/dashboard` |  |  |  |  |  |  |  |  | x |  |  |  |  | specs/02_requirements_and_scope.md, specs/30_workflow_system_overview.md |
| `ST-RPC-001` | `10_rpc_and_typescript_client.md` | `POST /rpc/validate` |  |  |  |  |  |  |  |  |  |  |  | x |  | specs/10_web_ui_and_routes.md, specs/32_agent_and_action_catalog.md |
| `ST-RPC-002` | `10_rpc_and_typescript_client.md` | `POST /rpc/run` |  |  |  |  |  |  |  |  |  |  |  | x |  | specs/10_web_ui_and_routes.md, specs/32_agent_and_action_catalog.md |
| `ST-RPC-003` | `10_rpc_and_typescript_client.md` | `POST /rpc/run` | x |  |  |  |  |  |  |  |  | x |  | x |  | specs/60_security_and_auth.md, specs/32_agent_and_action_catalog.md |
| `ST-RPC-004` | `10_rpc_and_typescript_client.md` | `POST /rpc/validate` |  |  |  |  |  |  |  |  |  | x |  | x |  | specs/60_security_and_auth.md, specs/32_agent_and_action_catalog.md |
| `ST-RPC-005` | `10_rpc_and_typescript_client.md` | `POST /rpc/run` |  |  |  |  | x |  |  |  |  |  |  | x |  | specs/30_workflow_system_overview.md, specs/32_agent_and_action_catalog.md |
| `ST-RPC-006` | `10_rpc_and_typescript_client.md` | `assets/js/ash_rpc.ts` |  |  |  |  |  |  |  |  |  |  |  | x |  | specs/32_agent_and_action_catalog.md, specs/20_ash_domain_model.md |
| `ST-RPC-007` | `10_rpc_and_typescript_client.md` | `/settings/api` |  |  |  |  |  |  |  |  |  |  |  | x |  | specs/20_ash_domain_model.md, specs/61_configuration_and_deployment.md |
| `ST-RPC-008` | `10_rpc_and_typescript_client.md` | `/settings/api` |  |  |  |  |  |  |  |  | x |  |  | x |  | specs/10_web_ui_and_routes.md, specs/61_configuration_and_deployment.md |
| `ST-DEP-001` | `11_deployment_and_environment_modes.md` | `Cloud VM deployment flow` |  |  |  |  |  |  |  |  |  |  | x |  |  | specs/61_configuration_and_deployment.md, specs/README.md |
| `ST-DEP-002` | `11_deployment_and_environment_modes.md` | `Local dev mode` |  |  |  |  |  |  |  |  |  | x | x |  |  | specs/61_configuration_and_deployment.md, specs/60_security_and_auth.md |
| `ST-DEP-003` | `11_deployment_and_environment_modes.md` | `Application startup` |  |  |  |  |  |  |  |  |  | x | x |  |  | specs/61_configuration_and_deployment.md, specs/11_onboarding_flow.md |
| `ST-DEP-004` | `11_deployment_and_environment_modes.md` | `/setup` |  |  | x |  |  | x |  |  |  |  | x |  |  | specs/61_configuration_and_deployment.md, specs/11_onboarding_flow.md |
| `ST-DEP-005` | `11_deployment_and_environment_modes.md` | `/setup` |  |  |  | x |  |  |  |  |  |  | x |  |  | specs/20_ash_domain_model.md, specs/11_onboarding_flow.md |
| `ST-DEP-006` | `11_deployment_and_environment_modes.md` | `/status` |  |  |  |  | x |  |  |  |  |  | x |  |  | specs/61_configuration_and_deployment.md, specs/30_workflow_system_overview.md |
| `ST-DEP-007` | `11_deployment_and_environment_modes.md` | `POST /api/github/webhooks` |  |  | x |  |  |  |  |  |  |  | x |  |  | specs/61_configuration_and_deployment.md, specs/50_github_integration.md |
| `ST-DEP-008` | `11_deployment_and_environment_modes.md` | `Workflow scheduling and queueing` |  |  |  |  | x |  | x |  |  |  | x |  |  | specs/40_project_environments.md, specs/30_workflow_system_overview.md |
| `ST-SIR-001` | `12_security_runbooks_and_incidents.md` | `/settings/security` |  |  |  |  |  |  |  |  |  | x |  |  |  | specs/10_web_ui_and_routes.md, specs/62_security_playbook.md |
| `ST-SIR-002` | `12_security_runbooks_and_incidents.md` | `/settings/security` |  |  |  |  |  |  |  |  |  | x |  |  |  | specs/62_security_playbook.md, specs/20_ash_domain_model.md |
| `ST-SIR-003` | `12_security_runbooks_and_incidents.md` | `/settings/security` | x |  |  |  |  |  |  |  |  | x |  |  |  | specs/62_security_playbook.md, specs/60_security_and_auth.md |
| `ST-SIR-004` | `12_security_runbooks_and_incidents.md` | `/settings/security` |  |  |  |  |  |  |  |  |  | x |  |  |  | specs/62_security_playbook.md, specs/60_security_and_auth.md |
| `ST-SIR-005` | `12_security_runbooks_and_incidents.md` | `POST /api/github/webhooks` |  |  | x |  |  |  |  | x |  | x |  |  |  | specs/62_security_playbook.md, specs/60_security_and_auth.md |
| `ST-SIR-006` | `12_security_runbooks_and_incidents.md` | `/settings/security` | x |  |  |  |  |  |  |  |  | x |  |  |  | specs/62_security_playbook.md, specs/60_security_and_auth.md |
| `ST-SIR-007` | `12_security_runbooks_and_incidents.md` | `/settings/security` |  |  |  |  |  |  | x | x |  | x |  |  |  | specs/62_security_playbook.md, specs/52_git_safety_policy.md |
| `ST-SIR-008` | `12_security_runbooks_and_incidents.md` | `/settings/security` |  |  |  |  |  |  |  |  | x | x |  |  |  | specs/62_security_playbook.md, specs/61_configuration_and_deployment.md |
