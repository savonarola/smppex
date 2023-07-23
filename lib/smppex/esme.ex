defmodule SMPPEX.ESME do
  @moduledoc """
  This is a module for launching an `SMPPEX.Session` implementation as an ESME.

  To start an ESME one generally should do the following.

  1. Implement an `SMPPEX.Session` behaviour.

  ```elixir

  defmodule MyESMESession do
    use SMPPEX.Session

    # ...Callback implementation

  end

  ```

  2. Launch it.

  ```elixir

  {:ok, esme_session} = SMPPEX.ESME.start_link("127.0.0.1",
                                               2775,
                                               {MyESMESession, some_args})

  ```

  """

  alias SMPPEX.Session.Defaults
  alias SMPPEX.TransportSession

  @default_transport :ranch_tcp
  @default_timeout 5000

  @spec start_link(
          host :: term,
          port :: non_neg_integer,
          {module, args :: term},
          opts :: Keyword.t()
        ) :: GenServer.on_start()

  @doc """
  Starts an `SMPPEX.Session` implementation as an ESME entitiy,
  i.e. makes a transport connection to `host`:`port` and starts an `SMPPEX.Session`
  to handle the connection with the passed module.

  The function does not return until ESME successfully connects to the specified
  `host` and `port` and initializes or fails.
  `module` is the callback module which should implement `SMPPEX.ESME` behaviour.
  `args` is the argument passed to the `init` callback.
  `opts` is a keyword list of different options:
  * `:transport` is Ranch transport used for TCP connection: either `:ranch_tcp` (the default) or
  `:ranch_ssl`;
  * `:session_module` is a module to use as an alternative to `SMPPEX.Session`
  for handling sessions (if needed). For example, `SMPPEX.TelemetrySession`.
  * `:timeout` is timeout for transport connect. The default is #{@default_timeout} ms;
  * `:esme_opts` is a keyword list of ESME options:
      - `:enquire_link_limit` is value for enquire_link SMPP timer, i.e. the interval of SMPP session inactivity after which
      enquire_link PDU is send to "ping" the connetion. The default value is #{inspect(Defaults.enquire_link_limit())} ms;
      - `:enquire_link_resp_limit` is the maximum time for which ESME waits for enquire_link PDU response. If the
      response is not received within this interval of time and no activity from the peer occurs, the session is then considered
      dead and the ESME stops. The default value is #{inspect(Defaults.enquire_link_resp_limit())} ms;
      - `:inactivity_limit` is the maximum time for which the peer is allowed not to send PDUs (which are not response PDUs).
      If no such PDUs are received within this interval of time, ESME stops.
      The default is #{inspect(Defaults.inactivity_limit())} ms;
      - `:response_limit` is the maximum time to wait for a response for a previously sent PDU. If the response is
      not received within this interval, `handle_resp_timeout` callback is triggered for the original pdu. If the response
      is received later, it is discarded. The default value is #{inspect(Defaults.response_limit())} ms.
      - `:response_limit_resolution` is the maximum time after reaching `response_limit` for which a PDU without
      a response is not collected. Setting to `0` will make PDUs without responses to be collected
      immediately after `response_limit` ms. Setting to greater values improve performance since
      such PDUs are collected in batches. The default value is #{inspect(Defaults.response_limit_resolution())} ms.
      - `:session_init_limit` is the maximum time for the session to be unbound.
      If no bind request succeed within this interval of time, the session stops.
      The default value is #{inspect(Defaults.session_init_limit())} ms;
  * `:socket_opts` is a keyword list of ranch socket options, see ranch's options for more information
  If `:esme_opts` list of options is ommited, all options take their default values.
  The whole `opts` argument may also be ommited in order to start ESME with the defaults.
  The returned value is either `{:ok, pid}` or `{:error, reason}`.
  """
  def start_link(host, port, {_module, _args} = mod_with_args, opts \\ []) do
    transport = Keyword.get(opts, :transport, @default_transport)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    sock_opts = [
      :binary,
      {:packet, 0},
      {:active, :once}
      | Keyword.get(opts, :socket_opts, [])
    ]

    session_module = Keyword.get(opts, :session_module, SMPPEX.Session)

    esme_opts = Keyword.get(opts, :esme_opts, [])

    case transport.connect(convert_host(host), port, sock_opts, timeout) do
      {:ok, socket} ->
        session_opts = {session_module, [mod_with_args, esme_opts]}

        case TransportSession.start_esme(socket, transport, session_opts) do
          {:ok, pid} ->
            {:ok, pid}

          {:error, _} = error ->
            transport.close(socket)
            error
        end

      {:error, _} = error ->
        error
    end
  end

  defp convert_host(host) when is_binary(host), do: to_charlist(host)
  defp convert_host(host), do: host
end
