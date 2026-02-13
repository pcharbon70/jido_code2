defmodule JidoCode.GithubIssueBot.Triage.Actions.TriageAction do
  @moduledoc """
  Performs triage on an issue.

  Uses simple heuristics to classify issues:
  - Has "bug" in title/labels -> :bug
  - Has "feature" or "enhancement" -> :feature
  - Has reproduction steps -> actionable
  - Missing info -> needs_info: true
  """
  use Jido.Action,
    name: "triage",
    schema: [
      run_id: [type: :string, required: true],
      issue: [type: :map, required: true]
    ]

  alias Jido.Agent.Directive
  alias Jido.Signal

  require Logger

  def run(%{run_id: run_id, issue: issue}, context) do
    Logger.debug("Triaging issue for run: #{run_id}")

    title = Map.get(issue, :title, "") |> String.downcase()
    body = Map.get(issue, :body, "") |> String.downcase()
    labels = Map.get(issue, :labels, []) |> Enum.map(&String.downcase/1)

    classification = classify(title, body, labels)
    needs_info = needs_more_info?(body)
    summary = generate_summary(classification, needs_info)

    result_signal =
      Signal.new!(
        "triage.result",
        %{
          run_id: run_id,
          classification: classification,
          needs_info: needs_info,
          summary: summary
        },
        source: "/triage"
      )

    emit_directive = Directive.emit_to_parent(%{state: context.state}, result_signal)

    {:ok,
     %{
       status: :completed,
       run_id: run_id,
       issue_number: Map.get(issue, :number)
     }, List.wrap(emit_directive)}
  end

  defp classify(title, _body, labels) do
    cond do
      bug_issue?(title, labels) ->
        :bug

      feature_issue?(title, labels) ->
        :feature

      question_issue?(title, labels) ->
        :question

      documentation_issue?(title, labels) ->
        :documentation

      true ->
        :unknown
    end
  end

  defp bug_issue?(title, labels) do
    "bug" in labels or contains_any?(title, ["bug", "error"])
  end

  defp feature_issue?(title, labels) do
    "feature" in labels or "enhancement" in labels or contains_any?(title, ["feature", "add"])
  end

  defp question_issue?(title, labels) do
    "question" in labels or String.contains?(title, "?")
  end

  defp documentation_issue?(title, labels) do
    "documentation" in labels or String.contains?(title, "docs")
  end

  defp contains_any?(text, terms) do
    Enum.any?(terms, &String.contains?(text, &1))
  end

  defp needs_more_info?(body) do
    has_reproduction =
      String.contains?(body, "steps to reproduce") or
        String.contains?(body, "reproduction") or
        String.contains?(body, "to reproduce")

    has_version =
      String.contains?(body, "version") or
        String.contains?(body, "elixir") or
        String.contains?(body, "otp")

    body_length = String.length(body)

    body_length < 50 or (not has_reproduction and not has_version)
  end

  defp generate_summary(classification, needs_info) do
    base = "Classified as #{classification}"

    if needs_info do
      base <> "; needs more information from reporter"
    else
      base <> "; ready for processing"
    end
  end
end
