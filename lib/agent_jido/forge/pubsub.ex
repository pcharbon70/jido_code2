defmodule AgentJido.Forge.PubSub do
  @moduledoc """
  PubSub helpers for Forge session events.

  Topics:
  - `"forge:sessions"` - Global session list changes
  - `"forge:session:<id>"` - Per-session state/output events
  """

  @pubsub AgentJido.PubSub

  def sessions_topic, do: "forge:sessions"
  def session_topic(id), do: "forge:session:#{id}"

  def subscribe_sessions do
    Phoenix.PubSub.subscribe(@pubsub, sessions_topic())
  end

  def subscribe_session(id) do
    Phoenix.PubSub.subscribe(@pubsub, session_topic(id))
  end

  def unsubscribe_session(id) do
    Phoenix.PubSub.unsubscribe(@pubsub, session_topic(id))
  end

  def broadcast_sessions(msg) do
    Phoenix.PubSub.broadcast(@pubsub, sessions_topic(), msg)
  end

  def broadcast_session(id, msg) do
    Phoenix.PubSub.broadcast(@pubsub, session_topic(id), msg)
  end
end
