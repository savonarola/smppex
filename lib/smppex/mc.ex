defmodule SMPPEX.MC do
  @moduledoc """
  This is a module for launching a TCP listener (or any other listener supported by `ranch`, for example, `ssl`) which handles incoming connections with the passed `SMPPEX.Session` implementations.

  To start an MC one generally should do the following.

  1. Implement an `SMPPEX.Session` behaviour.

  ```elixir

  defmodule MyMCSession do
    use SMPPEX.Session

    # ...Callback implementation

  end

  ```

  2. Pass the child specification to a supervisor, using implemented behaviour as a session module:

  ```elixir
  Supervisor.start_link(
    [
      {
        SMPPEX.MC,
        session: {MyESMESession, session_arg},
        transport_opts: [port: 2775]
      },
      ...
    ],
    ...
  )
  ```

  Note that each received connection is served with its own process which uses passed callback module (`MyESMESession`) for handling connection events. Each process has his own state initialized by `init` callback receiving `socket`, `transport` and a copy of arguments (`session_arg`).
  """

  alias SMPPEX.Session.Defaults

  @default_transport :ranch_tcp
  @default_acceptor_count 50

  @spec start({module, args :: term}, opts :: Keyword.t()) ::
          {:ok, listener_ref :: :ranch.ref()}
          | {:error, reason :: term}

  @doc """
  Starts listener for MC entity.

  The listener is started in the supervision tree of the `:ranch` application.
  Therefore, prefer `child_spec/1`, which allows you to start the MC in your own supervision tree.

  The first argument must be a `{module, arg}` tuple, where `module` is the callback module which should implement `SMPPEX.Session` behaviour, while `arg` is the argument passed to the `init` callback each time a new connection is received.
  For the list of other options see `child_spec/1`.
  """
  def start(mod_with_args, opts \\ []) do
    {ref, transport, transport_opts, protocol, protocol_opts} =
      ranch_start_args(mod_with_args, opts)

    start_result = :ranch.start_listener(ref, transport, transport_opts, protocol, protocol_opts)

    case start_result do
      {:error, _} = error -> error
      {:ok, _, _} -> {:ok, ref}
      {:ok, _} -> {:ok, ref}
    end
  end

  @doc """
  Returns a supervisor child specification for starting listener for MC entity.

  Starting under a supervisor:

  ```elixir
  Supervisor.start_link(
    [
      {SMPPEX.MC, session: {MyESMESession, session_arg}, ...},
      ...
    ],
    ...
  )
  ```

  Options:

  * `:session` (required) a `{module, arg}` tuple, where `module` is the callback module
  which should implement `SMPPEX.Session` behaviour, while `arg` is the argument passed
  to the `init` callback each time a new connection is received.
  * `:transport` is :ranch transport used for TCP connections: either `ranch_tcp` (the default)
  or `ranch_ssl`;
  * `:transport_opts` is a map of :ranch transport options.
  The major key is `socket_opts` which contains a list of important options such as `{:port, port}`.
  The port is set to `0` by default, which means that the listener will accept
  connections on a random free port. For backward compatibility one can pass a list of socket options
  instead of `transport_opts` map (as in :ranch 1.x).
  * `:session_module` is a module to use as an alternative to `SMPPEX.Session`
  for handling sessions (if needed). For example, `SMPPEX.TelemetrySession`.
  * `:acceptor_count` is the number of :ranch listener acceptors, #{@default_acceptor_count} by default.
  * `:mc_opts` is a keyword list of MC options:
      - `:session_init_limit` is the maximum time for which a session waits an incoming bind request.
      If no bind request is received within this interval of time, the session stops.
      The default value is #{inspect(Defaults.session_init_limit())} ms;
      - `:enquire_link_limit` is value for enquire_link SMPP timer, i.e. the interval of SMPP session
      inactivity after which enquire_link PDU is send to "ping" the connetion.
      The default value is #{inspect(Defaults.enquire_link_limit())} ms;
      - `:enquire_link_resp_limit` is the maximum time for which a session waits for enquire_link PDU response.
      If the response is not received within this interval of time and no activity from the peer occurs,
      the session is then considered dead and the session stops.
      The default value is #{inspect(Defaults.enquire_link_resp_limit())} ms;
      - `:inactivity_limit` is the maximum time for which a peer is allowed not to send PDUs
      (which are not response PDUs). If no such PDUs are received within this interval of time,
      the session stops. The default is #{inspect(Defaults.inactivity_limit())} ms;
      - `:response_limit` is the maximum time to wait for a response for a previously sent PDU.
      If the response is not received within this interval, `handle_resp_timeout` callback is triggered
      for the original pdu. If the response is received later, it is discarded.
      The default value is #{inspect(Defaults.response_limit())} ms.
      - `:response_limit_resolution` is the maximum time after reaching `response_limit` for which a PDU without
      a response is not collected. Setting to `0` will make PDUs without responses to be collected
      immediately after `response_limit` ms. Setting to greater values improve performance since
      such PDUs are collected in batches. The default value is #{inspect(Defaults.response_limit_resolution())} ms.
      - `:default_call_timeout` is an integer greater than zero which specifies how many milliseconds to wait
      for a reply, or the atom :infinity to wait indefinitely.If no reply is received within the specified time,
      the function call fails and the caller exits. The default value
      is #{inspect(Defaults.default_call_timeout())} ms.
  If `:mc_opts` list of options is ommited, all options take their default values.
  The returned value is either `{:ok, ref}` or `{:error, reason}`. The `ref` can be later used
  to stop the whole MC listener and all sessions received by it.
  """
  @spec child_spec(Keyword.t()) :: Supervisor.child_spec()
  def child_spec(opts) do
    # TODO: using fetch! + delete since pop! is supported on 1.10+. Replace this with pop! once we require at least Elixir 1.10.
    mod_with_args = Keyword.fetch!(opts, :session)
    opts = Keyword.delete(opts, :session)

    {ref, transport, transport_opts, protocol, protocol_opts} =
      ranch_start_args(mod_with_args, opts)

    :ranch.child_spec(ref, transport, transport_opts, protocol, protocol_opts)
  end

  defp ranch_start_args({_module, _args} = mod_with_args, opts) do
    acceptor_count = Keyword.get(opts, :acceptor_count, @default_acceptor_count)
    transport = Keyword.get(opts, :transport, @default_transport)

    transport_opts =
      opts
      |> Keyword.get(:transport_opts, [{:port, 0}])
      |> normalize_transport_opts(acceptor_count)

    mc_opts = Keyword.get(opts, :mc_opts, [])
    ref = make_ref()

    session_module = Keyword.get(opts, :session_module, SMPPEX.Session)

    {
      ref,
      transport,
      transport_opts,
      SMPPEX.TransportSession,
      {session_module, [mod_with_args, mc_opts]}
    }
  end

  defp normalize_transport_opts(opts, acceptor_count) when is_list(opts) do
    %{num_acceptors: acceptor_count, socket_opts: opts}
  end

  defp normalize_transport_opts(opts, acceptor_count) when is_map(opts) do
    Map.put_new(opts, :num_acceptors, acceptor_count)
  end

  @spec stop(:ranch.ref()) :: :ok

  @doc """
  Stops MC listener and all its sessions.
  """

  def stop(listener) do
    :ranch.stop_listener(listener)
  end
end
