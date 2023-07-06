defmodule SMPPEX.Session.Defaults do
  @moduledoc false

  defaults = [
    enquire_link_limit: 30_000,
    enquire_link_resp_limit: 30_000,
    session_init_limit: 10_000,
    inactivity_limit: :infinity,
    response_limit: 60_000,
    response_limit_resolution: 100,
    default_call_timeout: 5_000
  ]

  for {name, value} <- defaults do
    def unquote(name)() do
      unquote(value)
    end
  end
end
