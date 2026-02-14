defmodule JidoCodeWeb.GitHubWebhookControllerTest do
  use JidoCodeWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias JidoCode.GitHub.Repo, as: GitHubRepo
  alias JidoCode.GitHub.WebhookDelivery
  alias JidoCode.Orchestration.WorkflowRun
  alias JidoCode.Projects.Project

  require Logger

  @webhook_path "/api/github/webhooks"

  setup do
    original_log_level = Logger.level()
    Logger.configure(level: :info)

    original_secret = Application.get_env(:jido_code, :github_webhook_secret, :__missing__)

    original_dispatcher =
      Application.get_env(:jido_code, :github_webhook_verified_dispatcher, :__missing__)

    original_system_config = Application.get_env(:jido_code, :system_config, :__missing__)

    on_exit(fn ->
      Logger.configure(level: original_log_level)
      restore_env(:github_webhook_secret, original_secret)
      restore_env(:github_webhook_verified_dispatcher, original_dispatcher)
      restore_env(:system_config, original_system_config)
    end)

    :ok
  end

  test "accepts verified deliveries, persists delivery ID before dispatch, and forwards handoff",
       %{
         conn: conn
       } do
    secret = "webhook-secret-#{System.unique_integer([:positive])}"
    Application.put_env(:jido_code, :github_webhook_secret, secret)
    repo = create_repo!()

    test_pid = self()

    Application.put_env(:jido_code, :github_webhook_verified_dispatcher, fn delivery ->
      persisted_delivery =
        WebhookDelivery.get_by_github_delivery_id(delivery.delivery_id, authorize?: false)

      send(test_pid, {:verified_delivery_handoff, delivery, persisted_delivery})
      :ok
    end)

    payload =
      Jason.encode!(%{
        "action" => "opened",
        "issue" => %{"number" => 42},
        "repository" => %{"full_name" => repo.full_name}
      })

    delivery_id = "delivery-#{System.unique_integer([:positive])}"
    event = "issues"

    log_output =
      capture_log([level: :info], fn ->
        response =
          conn
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-hub-signature-256", sign(payload, secret))
          |> put_req_header("x-github-delivery", delivery_id)
          |> put_req_header("x-github-event", event)
          |> post(@webhook_path, payload)
          |> json_response(202)

        assert response["status"] == "accepted"
      end)

    assert_receive {:verified_delivery_handoff, handoff, {:ok, %WebhookDelivery{} = persisted_delivery}}

    assert handoff.delivery_id == delivery_id
    assert handoff.event == event
    assert handoff.payload["action"] == "opened"
    assert handoff.payload["repository"]["full_name"] == repo.full_name
    assert handoff.raw_payload == payload
    assert persisted_delivery.github_delivery_id == delivery_id
    assert persisted_delivery.event_type == event
    assert persisted_delivery.repo_id == repo.id

    assert log_output =~ "security_audit=github_webhook_signature_verified"
    assert log_output =~ "delivery_id=#{delivery_id}"
    assert log_output =~ "event=#{event}"
  end

  test "acknowledges duplicate deliveries safely without duplicate dispatch", %{conn: conn} do
    secret = "webhook-secret-#{System.unique_integer([:positive])}"
    Application.put_env(:jido_code, :github_webhook_secret, secret)
    repo = create_repo!()

    test_pid = self()

    Application.put_env(:jido_code, :github_webhook_verified_dispatcher, fn delivery ->
      send(test_pid, {:verified_delivery_handoff, delivery.delivery_id})
      :ok
    end)

    payload =
      Jason.encode!(%{
        "action" => "opened",
        "issue" => %{"number" => 44},
        "repository" => %{"full_name" => repo.full_name}
      })

    delivery_id = "delivery-#{System.unique_integer([:positive])}"
    event = "issues"

    first_response =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-hub-signature-256", sign(payload, secret))
      |> put_req_header("x-github-delivery", delivery_id)
      |> put_req_header("x-github-event", event)
      |> post(@webhook_path, payload)
      |> json_response(202)

    assert first_response["status"] == "accepted"
    assert_receive {:verified_delivery_handoff, ^delivery_id}

    duplicate_log =
      capture_log([level: :info], fn ->
        second_response =
          conn
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-hub-signature-256", sign(payload, secret))
          |> put_req_header("x-github-delivery", delivery_id)
          |> put_req_header("x-github-event", event)
          |> post(@webhook_path, payload)
          |> json_response(202)

        assert second_response["status"] == "accepted"
      end)

    refute_receive {:verified_delivery_handoff, ^delivery_id}
    assert duplicate_log =~ "outcome=duplicate_acknowledged"

    assert {:ok, %WebhookDelivery{} = persisted_delivery} =
             WebhookDelivery.get_by_github_delivery_id(delivery_id, authorize?: false)

    assert persisted_delivery.repo_id == repo.id
    assert persisted_delivery.event_type == event
  end

  test "uses stored project Issue Bot webhook event list when evaluating deliveries", %{
    conn: conn
  } do
    secret = "webhook-secret-#{System.unique_integer([:positive])}"
    Application.put_env(:jido_code, :github_webhook_secret, secret)

    unique_suffix = System.unique_integer([:positive])
    owner = "event-owner-#{unique_suffix}"
    name = "event-repo-#{unique_suffix}"
    repo_full_name = "#{owner}/#{name}"

    _repo = create_repo!(%{owner: owner, name: name})

    {:ok, _project} =
      Project.create(%{
        name: name,
        github_full_name: repo_full_name,
        default_branch: "main",
        settings: %{
          "support_agent_config" => %{
            "github_issue_bot" => %{
              "enabled" => true,
              "webhook_events" => ["issues.edited"]
            }
          }
        }
      })

    test_pid = self()

    Application.put_env(:jido_code, :github_webhook_verified_dispatcher, fn delivery ->
      send(
        test_pid,
        {:verified_delivery_handoff, delivery.delivery_id, delivery.event, delivery.payload["action"]}
      )

      :ok
    end)

    blocked_payload =
      Jason.encode!(%{
        "action" => "opened",
        "issue" => %{"number" => 55},
        "repository" => %{"full_name" => repo_full_name}
      })

    blocked_delivery_id = "delivery-blocked-#{System.unique_integer([:positive])}"

    blocked_log =
      capture_log([level: :info], fn ->
        response =
          conn
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-hub-signature-256", sign(blocked_payload, secret))
          |> put_req_header("x-github-delivery", blocked_delivery_id)
          |> put_req_header("x-github-event", "issues")
          |> post(@webhook_path, blocked_payload)
          |> json_response(202)

        assert response["status"] == "accepted"
      end)

    refute_receive {:verified_delivery_handoff, ^blocked_delivery_id, _, _}
    assert blocked_log =~ "github_webhook_trigger_filtered"

    assert {:ok, %WebhookDelivery{} = blocked_delivery} =
             WebhookDelivery.get_by_github_delivery_id(blocked_delivery_id, authorize?: false)

    assert blocked_delivery.event_type == "issues"
    assert blocked_delivery.action == "opened"

    allowed_payload =
      Jason.encode!(%{
        "action" => "edited",
        "issue" => %{"number" => 56},
        "repository" => %{"full_name" => repo_full_name}
      })

    allowed_delivery_id = "delivery-allowed-#{System.unique_integer([:positive])}"

    response =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-hub-signature-256", sign(allowed_payload, secret))
      |> put_req_header("x-github-delivery", allowed_delivery_id)
      |> put_req_header("x-github-event", "issues")
      |> post(@webhook_path, allowed_payload)
      |> json_response(202)

    assert response["status"] == "accepted"

    assert_receive {:verified_delivery_handoff, ^allowed_delivery_id, "issues", "edited"}
  end

  test "creates tracked issue_triage runs with webhook context and issue identifiers for issues.opened",
       %{
         conn: conn
       } do
    secret = "webhook-secret-#{System.unique_integer([:positive])}"
    Application.put_env(:jido_code, :github_webhook_secret, secret)

    unique_suffix = System.unique_integer([:positive])
    owner = "triage-owner-#{unique_suffix}"
    name = "triage-repo-#{unique_suffix}"
    repo_full_name = "#{owner}/#{name}"

    _repo = create_repo!(%{owner: owner, name: name})

    {:ok, %Project{} = project} =
      Project.create(%{
        name: name,
        github_full_name: repo_full_name,
        default_branch: "main",
        settings: %{
          "support_agent_config" => %{
            "github_issue_bot" => %{
              "enabled" => true,
              "webhook_events" => ["issues.opened"]
            }
          }
        }
      })

    test_pid = self()

    Application.put_env(:jido_code, :github_webhook_verified_dispatcher, fn delivery ->
      send(
        test_pid,
        {:verified_delivery_handoff, delivery.delivery_id, delivery.event, delivery.payload["action"]}
      )

      :ok
    end)

    payload =
      Jason.encode!(%{
        "action" => "opened",
        "issue" => %{
          "id" => 90_001,
          "number" => 77,
          "node_id" => "I_kwDOABC1234",
          "url" => "https://api.github.com/repos/#{repo_full_name}/issues/77",
          "html_url" => "https://github.com/#{repo_full_name}/issues/77"
        },
        "repository" => %{"full_name" => repo_full_name}
      })

    delivery_id = "delivery-triage-#{System.unique_integer([:positive])}"

    response =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-hub-signature-256", sign(payload, secret))
      |> put_req_header("x-github-delivery", delivery_id)
      |> put_req_header("x-github-event", "issues")
      |> post(@webhook_path, payload)
      |> json_response(202)

    assert response["status"] == "accepted"
    assert_receive {:verified_delivery_handoff, ^delivery_id, "issues", "opened"}

    assert {:ok, [%WorkflowRun{} = run]} = workflow_runs_for_project(project.id)
    assert run.workflow_name == "issue_triage"

    source_row = map_get(run.trigger, :source_row, "source_row", %{})
    webhook_context = map_get(run.trigger, :webhook, "webhook", %{})
    source_issue = map_get(run.trigger, :source_issue, "source_issue", %{})

    assert map_get(run.trigger, :source, "source") == "github_webhook"
    assert map_get(run.trigger, :mode, "mode") == "webhook"
    assert map_get(source_row, :route, "route") == "/api/github/webhooks"
    assert map_get(source_row, :delivery_id, "delivery_id") == delivery_id
    assert map_get(webhook_context, :event, "event") == "issues"
    assert map_get(webhook_context, :action, "action") == "opened"
    assert map_get(source_issue, :number, "number") == 77
    assert map_get(source_issue, :id, "id") == 90_001
    assert map_get(run.inputs, :issue_reference, "issue_reference") == "#{repo_full_name}#77"
  end

  test "records issues.opened deliveries as no-op when project Issue Bot is disabled", %{
    conn: conn
  } do
    secret = "webhook-secret-#{System.unique_integer([:positive])}"
    Application.put_env(:jido_code, :github_webhook_secret, secret)

    unique_suffix = System.unique_integer([:positive])
    owner = "disabled-owner-#{unique_suffix}"
    name = "disabled-repo-#{unique_suffix}"
    repo_full_name = "#{owner}/#{name}"

    _repo = create_repo!(%{owner: owner, name: name})

    {:ok, %Project{} = project} =
      Project.create(%{
        name: name,
        github_full_name: repo_full_name,
        default_branch: "main",
        settings: %{
          "support_agent_config" => %{
            "github_issue_bot" => %{
              "enabled" => false,
              "webhook_events" => ["issues.opened"]
            }
          }
        }
      })

    test_pid = self()

    Application.put_env(:jido_code, :github_webhook_verified_dispatcher, fn delivery ->
      send(
        test_pid,
        {:verified_delivery_handoff, delivery.delivery_id, delivery.event, delivery.payload["action"]}
      )

      :ok
    end)

    payload =
      Jason.encode!(%{
        "action" => "opened",
        "issue" => %{
          "id" => 90_002,
          "number" => 78,
          "url" => "https://api.github.com/repos/#{repo_full_name}/issues/78",
          "html_url" => "https://github.com/#{repo_full_name}/issues/78"
        },
        "repository" => %{"full_name" => repo_full_name}
      })

    delivery_id = "delivery-disabled-#{System.unique_integer([:positive])}"

    log_output =
      capture_log([level: :info], fn ->
        response =
          conn
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-hub-signature-256", sign(payload, secret))
          |> put_req_header("x-github-delivery", delivery_id)
          |> put_req_header("x-github-event", "issues")
          |> post(@webhook_path, payload)
          |> json_response(202)

        assert response["status"] == "accepted"
      end)

    refute_receive {:verified_delivery_handoff, ^delivery_id, _, _}
    assert log_output =~ "github_webhook_trigger_filtered outcome=noop"
    assert log_output =~ "policy=support_agent_config.github_issue_bot.enabled"

    assert {:ok, []} = workflow_runs_for_project(project.id)

    assert {:ok, %WebhookDelivery{} = persisted_delivery} =
             WebhookDelivery.get_by_github_delivery_id(delivery_id, authorize?: false)

    assert persisted_delivery.event_type == "issues"
    assert persisted_delivery.action == "opened"
  end

  test "rejects delivery when signature verification fails and does not route side effects", %{
    conn: conn
  } do
    secret = "webhook-secret-#{System.unique_integer([:positive])}"
    Application.put_env(:jido_code, :github_webhook_secret, secret)

    test_pid = self()

    Application.put_env(:jido_code, :github_webhook_verified_dispatcher, fn delivery ->
      send(test_pid, {:verified_delivery_handoff, delivery})
      :ok
    end)

    payload = Jason.encode!(%{"action" => "opened", "issue" => %{"number" => 43}})
    delivery_id = "delivery-#{System.unique_integer([:positive])}"
    event = "issues"

    log_output =
      capture_log(fn ->
        response =
          conn
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-hub-signature-256", "sha256=deadbeef")
          |> put_req_header("x-github-delivery", delivery_id)
          |> put_req_header("x-github-event", event)
          |> post(@webhook_path, payload)
          |> json_response(401)

        assert response["error"] == "invalid_signature"
      end)

    refute_receive {:verified_delivery_handoff, _delivery}
    assert log_output =~ "security_audit=github_webhook_signature_rejected"
    assert log_output =~ "delivery_id=#{delivery_id}"
    assert log_output =~ "event=#{event}"
  end

  test "fails closed when delivery ID cannot be persisted and does not dispatch triggers", %{
    conn: conn
  } do
    secret = "webhook-secret-#{System.unique_integer([:positive])}"
    Application.put_env(:jido_code, :github_webhook_secret, secret)
    repo = create_repo!()

    test_pid = self()

    Application.put_env(:jido_code, :github_webhook_verified_dispatcher, fn delivery ->
      send(test_pid, {:verified_delivery_handoff, delivery})
      :ok
    end)

    payload =
      Jason.encode!(%{
        "action" => "opened",
        "issue" => %{"number" => 45},
        "repository" => %{"full_name" => repo.full_name}
      })

    event = "issues"

    log_output =
      capture_log(fn ->
        response =
          conn
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-hub-signature-256", sign(payload, secret))
          |> put_req_header("x-github-event", event)
          |> post(@webhook_path, payload)
          |> json_response(500)

        assert response["error"] == "delivery_processing_failed"
      end)

    refute_receive {:verified_delivery_handoff, _delivery}
    assert log_output =~ "github_webhook_delivery_persist_failed"
    assert log_output =~ "missing_delivery_id"
    assert {:ok, []} = WebhookDelivery.list_for_repo(%{repo_id: repo.id}, authorize?: false)
  end

  test "processes installation repository events and syncs repository availability metadata", %{
    conn: conn
  } do
    secret = "webhook-secret-#{System.unique_integer([:positive])}"
    Application.put_env(:jido_code, :github_webhook_secret, secret)

    _existing_repo =
      create_repo!(%{
        owner: "owner",
        name: "repo-one",
        github_app_installation_id: 123
      })

    _added_repo =
      create_repo!(%{
        owner: "owner",
        name: "repo-two"
      })

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 7,
      onboarding_state: %{
        "4" => %{
          "github_credentials" => %{
            "paths" => [
              %{
                "path" => "github_app",
                "status" => "ready",
                "repository_access" => "confirmed",
                "repositories" => ["owner/repo-one"]
              }
            ]
          }
        }
      }
    })

    payload =
      Jason.encode!(%{
        "action" => "added",
        "installation" => %{
          "id" => 123,
          "repository_selection" => "selected"
        },
        "repositories_added" => [
          %{"id" => 200, "full_name" => "owner/repo-two"}
        ],
        "repositories_removed" => []
      })

    delivery_id = "delivery-#{System.unique_integer([:positive])}"
    event = "installation_repositories"

    log_output =
      capture_log([level: :info], fn ->
        response =
          conn
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-hub-signature-256", sign(payload, secret))
          |> put_req_header("x-github-delivery", delivery_id)
          |> put_req_header("x-github-event", event)
          |> post(@webhook_path, payload)
          |> json_response(202)

        assert response["status"] == "accepted"
      end)

    persisted_config = Application.get_env(:jido_code, :system_config)
    onboarding_state = Map.fetch!(persisted_config, :onboarding_state)

    installation_sync =
      onboarding_state
      |> Map.fetch!("7")
      |> Map.fetch!("installation_sync")

    assert installation_sync["status"] == "ready"
    assert installation_sync["event"] == "installation_repositories"
    assert installation_sync["action"] == "added"
    assert installation_sync["installation_id"] == 123

    assert Enum.map(installation_sync["accessible_repositories"], & &1["full_name"]) == [
             "owner/repo-one",
             "owner/repo-two"
           ]

    github_app_path =
      onboarding_state
      |> Map.fetch!("4")
      |> Map.fetch!("github_credentials")
      |> Map.fetch!("paths")
      |> Enum.find(fn path -> path["path"] == "github_app" end)

    assert github_app_path["status"] == "ready"
    assert github_app_path["repository_access"] == "confirmed"

    assert Enum.map(github_app_path["repositories"], & &1["full_name"]) == [
             "owner/repo-one",
             "owner/repo-two"
           ]

    assert log_output =~ "github_installation_sync outcome=updated"
    assert log_output =~ "affected_repositories=owner/repo-one,owner/repo-two"
  end

  test "marks installation sync metadata as stale with retry guidance when installation payload is invalid",
       %{conn: conn} do
    secret = "webhook-secret-#{System.unique_integer([:positive])}"
    Application.put_env(:jido_code, :github_webhook_secret, secret)

    _repo =
      create_repo!(%{
        owner: "owner",
        name: "repo-one"
      })

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 7,
      onboarding_state: %{
        "4" => %{
          "github_credentials" => %{
            "paths" => [
              %{
                "path" => "github_app",
                "status" => "ready",
                "repository_access" => "confirmed",
                "repositories" => ["owner/repo-one"]
              }
            ]
          }
        }
      }
    })

    payload =
      Jason.encode!(%{
        "action" => "created",
        "repositories" => [%{"full_name" => "owner/repo-one"}]
      })

    delivery_id = "delivery-#{System.unique_integer([:positive])}"
    event = "installation"

    log_output =
      capture_log([level: :info], fn ->
        response =
          conn
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-hub-signature-256", sign(payload, secret))
          |> put_req_header("x-github-delivery", delivery_id)
          |> put_req_header("x-github-event", event)
          |> post(@webhook_path, payload)
          |> json_response(202)

        assert response["status"] == "accepted"
      end)

    persisted_config = Application.get_env(:jido_code, :system_config)
    onboarding_state = Map.fetch!(persisted_config, :onboarding_state)

    installation_sync =
      onboarding_state
      |> Map.fetch!("7")
      |> Map.fetch!("installation_sync")

    assert installation_sync["status"] == "stale"
    assert installation_sync["error_type"] == "github_installation_sync_stale"
    assert installation_sync["detail"] =~ "Repository availability may be stale"
    assert installation_sync["remediation"] =~ "Retry repository refresh in step 7"

    repository_listing =
      onboarding_state
      |> Map.fetch!("7")
      |> Map.fetch!("repository_listing")

    assert repository_listing["status"] == "blocked"
    assert repository_listing["error_type"] == "github_installation_sync_stale"
    assert repository_listing["detail"] =~ "Repository availability may be stale"
    assert repository_listing["remediation"] =~ "Retry repository refresh in step 7"

    assert log_output =~ "github_installation_sync outcome=stale"
    assert log_output =~ "affected_repositories=owner/repo-one"
  end

  defp create_repo! do
    unique_suffix = System.unique_integer([:positive])

    {:ok, %GitHubRepo{} = repo} =
      GitHubRepo.create(
        %{
          owner: "webhook-owner-#{unique_suffix}",
          name: "webhook-repo-#{unique_suffix}"
        },
        authorize?: false
      )

    repo
  end

  defp create_repo!(attributes) when is_map(attributes) do
    owner = Map.fetch!(attributes, :owner)
    name = Map.fetch!(attributes, :name)

    {:ok, %GitHubRepo{} = repo} =
      GitHubRepo.create(
        %{
          owner: owner,
          name: name,
          github_app_installation_id: Map.get(attributes, :github_app_installation_id)
        },
        authorize?: false
      )

    repo
  end

  defp sign(payload, secret) do
    digest =
      :crypto.mac(:hmac, :sha256, secret, payload)
      |> Base.encode16(case: :lower)

    "sha256=#{digest}"
  end

  defp workflow_runs_for_project(project_id) do
    WorkflowRun.read(
      query: [filter: [project_id: project_id], sort: [inserted_at: :asc]],
      authorize?: false
    )
  end

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(map, atom_key, string_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)

  defp restore_env(key, value) do
    Application.put_env(:jido_code, key, value)
  end
end
