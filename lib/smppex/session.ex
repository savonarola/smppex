defmodule SMPPEX.Session do
  @moduledoc """
  Module for implementing custom SMPP Session entities.

  To implement an Session entitiy, one should implement several callbacks (`SMPPEX.Session` behaviour).
  The most proper way to do it is to `use` `SMPPEX.Session`:

  ```
  defmodule MySession do
    use SMPPEX.Session

    # ...Callback implementation

  end
  ```

  In this case all callbacks have reasonable defaults.
  """

  alias __MODULE__, as: Session
  alias SMPPEX.Pdu
  alias SMPPEX.PduStorage
  alias SMPPEX.RawPdu
  alias SMPPEX.Session.AutoPduHandler
  alias SMPPEX.Session.Defaults
  alias SMPPEX.SMPPTimers
  alias SMPPEX.TransportSession

  require Logger

  @behaviour TransportSession

  defstruct [
    :module,
    :module_state,
    :timers,
    :pdus,
    :auto_pdu_handler,
    :response_limit,
    # increment before use
    :sequence_number
  ]

  @default_call_timeout Defaults.default_call_timeout()

  @type state :: term
  @type request :: term
  @type reason :: term
  @type reply :: term
  @type send_pdu_result :: TransportSession.send_pdu_result()
  @type session :: pid
  @type from :: TransportSession.from()

  @doc """
  Invoked when a session is started after a connection successfully established.

  `args` argument is taken directly from `ESME.start_link` or `MC.start` call.
  The return value should be either `{:ok, state}`, then the session will successfully start and the returned state will be later passed to the other callbacks, or `{:stop, reason}`, then the session will stop with the returned reason.
  """
  @callback init(
              socket :: TransportSession.socket(),
              transport :: TransportSession.transport(),
              args :: term
            ) ::
              {:ok, state}
              | {:stop, reason}

  @doc """
  Invoked when the session receives an incoming PDU (which is not a response PDU).

  The callback return values indicate the following:
  * `{:ok, state}` — use `state` as the new session state;
  * `{:ok, pdus, state}` — use `state` as the new session state and additionally send `pdus` to the connection;
  * `{:stop, reason, state}` — stop with reason `reason` and use `state` as the new session state.
  """
  @callback handle_pdu(pdu :: Pdu.t(), state) ::
              {:ok, state}
              | {:ok, [Pdu.t()], state}
              | {:stop, reason, state}

  @doc """
  Invoked when the session receives an incoming PDU which couldn't be correctly parsed.

  The callback return values indicate the following:
  * `{:ok, state}` — use `state` as the new session state;
  * `{:ok, pdus, state}` — use `state` as the new session state and additionally send `pdus` to the connection;
  * `{:stop, reason, state}` — stop with reason `reason` and use `state` as the new session state.
  """
  @callback handle_unparsed_pdu(pdu :: RawPdu.t(), error :: term, state) ::
              {:ok, state}
              | {:ok, [Pdu.t()], state}
              | {:stop, reason, state}

  @doc """
  Invoked when the session receives a response to a previously sent PDU.

  `pdu` argument contains the received response PDU, `original_pdu` contains
  the previously sent pdu for which the handled response is received.

  The callback return values indicate the following:
  * `{:ok, state}` — use `state` as the new session state;
  * `{:ok, pdus, state}` — use `state` as the new session state and additionally send `pdus` to the connection;
  * `{:stop, reason, state}` — stop with reason `reason` and use `state` as the new session state.
  """
  @callback handle_resp(pdu :: Pdu.t(), original_pdu :: Pdu.t(), state) ::
              {:ok, state}
              | {:ok, [Pdu.t()], state}
              | {:stop, reason, state}

  @doc """
  Invoked when the session does not receive a response to a previously sent PDU
  within the specified timeout.

  `pdu` argument contains the PDU for which no response was received. If the response
  will be received later it will be dropped (with an `info` log message).

  The callback return values indicate the following:
  * `{:ok, state}` — use `state` as the new session state;
  * `{:ok, pdus, state}` — use `state` as the new session state and additionally send `pdus` to the connection;
  * `{:stop, reason, state}` — stop with reason `reason` and use `state` as the new session state.
  """
  @callback handle_resp_timeout(pdus :: [Pdu.t()], state) ::
              {:ok, state}
              | {:ok, [Pdu.t()], state}
              | {:stop, reason, state}

  @doc """
  Invoked when the session is about to be stopped due to a timeout.

  The return value will be used as the exit reason of the session process. The default implementation returns `{:timers, reason}`.
  """
  @callback handle_timeout(SMPPEX.SMPPTimers.stop_reason(), state) :: exit_reason :: term

  @doc """
  Invoked when the SMPP session successfully sent PDU to transport or failed to do this.

  `pdu` argument contains the PDU for which send status is reported. `send_pdu_result` can be
  either `:ok` or `{:error, reason}`.

  The returned value is used as the new state.
  """
  @callback handle_send_pdu_result(pdu :: Pdu.t(), send_pdu_result, state) :: state

  @doc """
  Invoked when the connection's socket reported a error.

  The returned value should be `{reason, state}`. The session stops then with `reason`.
  """
  @callback handle_socket_error(error :: term, state) :: {exit_reason :: term, state}

  @doc """
  Invoked when the connection is closed by the peer.

  The returned value should be `{reason, state}`. The session stops then with `reason`.
  """
  @callback handle_socket_closed(state) :: {exit_reason :: term, state}

  @doc """
  Invoked to handle an arbitrary syncronous `request` sent to the session with `Session.call/3` method.

  `from` argument can be used to send a response asyncronously via `Session.reply/2`.

  The returned values indicate the following:
  * `{:reply, reply, state}` — reply with `reply` and use `state` as the new state;
  * `{:reply, reply, pdus, state}`  — reply with `reply`, use `state` as the new state and additionally send `pdus` to the peer;
  * `{:noreply, state}` — do not reply and use `state` as the new state. The reply can be send later via `Session.reply`;
  * `{:noreply, pdus, state}` — do not reply, use `state` as the new state and additionally send `pdus` to the peer. The reply can be send later via `Session.reply`;
  * `{:stop, reason, reply, state}` — reply with `reply`, use `state` as the new state and exit with `reason`;
  * `{:stop, reason, state}` — do not reply, use `state` as the new state and exit with `reason`.
  """
  @callback handle_call(request, from, state) ::
              {:reply, reply, state}
              | {:reply, reply, [Pdu.t()], state}
              | {:noreply, state}
              | {:noreply, [Pdu.t()], state}
              | {:stop, reason, reply, state}
              | {:stop, reason, state}

  @doc """
  Invoked to handle an arbitrary asyncronous `request` sent to the session with `Session.cast/2` method.

  The returned values indicate the following:
  * `{:noreply, state}` — use `state` as the new state;
  * `{:noreply, pdus, state}` — use `state` as the new state and additionally send `pdus` to the peer.;
  * `{:stop, reason, state}` — use `state` as the new state and exit with `reason`.
  """
  @callback handle_cast(request, state) ::
              {:noreply, state}
              | {:noreply, [Pdu.t()], state}
              | {:stop, reason, state}

  @doc """
  Invoked to handle a generic message `request` sent to the session process.

  The returned values indicate the following:
  * `{:noreply, state}` — use `state` as the new state;
  * `{:noreply, pdus, state}` — use `state` as the new state and additionally send `pdus` to the peer.;
  * `{:stop, reason, state}` — use `state` as the new state and exit with `reason`.
  """
  @callback handle_info(request, state) ::
              {:noreply, state}
              | {:noreply, [Pdu.t()], state}
              | {:stop, reason, state}

  @doc """
  Invoked when the session process is about to exit.

  `lost_pdus` contain a list of nonresp `pdus` sent by the session to the peer and which have not yet received a response.

  The returned value is either `:stop` or `{:stop, last_pdus, state}`, where `last_pdus` is a list of PDUs which will be sent to the peer before socket close, and `state` is the new state. For example, an ESME can send an unbind PDU or an MC can send negative resps for pending `submit_sm`s if needed.

  This callback is called from the underlying `GenServer` `terminate` callbacks, so it has all the corresponding caveats, for example, sometimes it may not be called, see [`GenServer.terminate/2` docs](https://hexdocs.pm/elixir/GenServer.html#c:terminate/2).
  """
  @callback terminate(reason, lost_pdus :: [Pdu.t()], state) ::
              :stop
              | {:stop, [Pdu.t()], state}

  @doc """
  Invoked to change the state of the session when a different version of a module is loaded (hot code swapping) and the state’s term structure should be changed. The method has the same semantics as the original `GenServer.code_change/3` callback.

  """
  @callback code_change(old_vsn :: term | {:down, term}, state, extra :: term) ::
              {:ok, state}
              | {:error, reason}

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour SMPPEX.Session

      require Logger

      @impl SMPPEX.Session
      def init(_socket, _transport, args) do
        {:ok, args}
      end

      @impl SMPPEX.Session
      def handle_pdu(_pdu, state), do: {:ok, state}

      @impl SMPPEX.Session
      def handle_unparsed_pdu(_pdu, _error, state), do: {:ok, state}

      @impl SMPPEX.Session
      def handle_resp(_pdu, _original_pdu, state), do: {:ok, state}

      @impl SMPPEX.Session
      def handle_resp_timeout(_pdus, state), do: {:ok, state}

      @impl SMPPEX.Session
      def handle_timeout(reason, _state) do
        Logger.info("Session #{inspect(self())}, being stopped by timers(#{reason})")
        {:timers, reason}
      end

      @impl SMPPEX.Session
      def handle_send_pdu_result(_pdu, _result, state), do: state

      @impl SMPPEX.Session
      def handle_socket_error(error, state), do: {{:socket_error, error}, state}

      @impl SMPPEX.Session
      def handle_socket_closed(state), do: {:socket_closed, state}

      @impl SMPPEX.Session
      def handle_call(_request, _from, state), do: {:reply, :ok, state}

      @impl SMPPEX.Session
      def handle_cast(_request, state), do: {:noreply, state}

      @impl SMPPEX.Session
      def handle_info(_request, state), do: {:noreply, state}

      @impl SMPPEX.Session
      def terminate(reason, lost_pdus, _state) do
        Logger.info(
          "Session #{inspect(self())} stopped with reason: #{inspect(reason)}, lost_pdus: #{inspect(lost_pdus)}"
        )

        :stop
      end

      @impl SMPPEX.Session
      def code_change(_vsn, state, _extra), do: {:ok, state}

      defoverridable init: 3,
                     handle_pdu: 2,
                     handle_unparsed_pdu: 3,
                     handle_resp: 3,
                     handle_resp_timeout: 2,
                     handle_timeout: 2,
                     handle_send_pdu_result: 3,
                     handle_socket_error: 2,
                     handle_socket_closed: 1,
                     handle_call: 3,
                     handle_cast: 2,
                     handle_info: 2,
                     terminate: 3,
                     code_change: 3
    end
  end

  # Public interface

  @spec send_pdu(session, Pdu.t()) :: :ok

  @doc """
  Sends a PDU from the session to the peer.
  """
  def send_pdu(pid, pdu, timeout \\ @default_call_timeout) do
    TransportSession.call(pid, {:send_pdu, pdu}, timeout)
  end

  @spec stop(session) :: :ok

  @doc """
  Stops the session syncronously.
  """
  def stop(pid, reason \\ :normal) do
    TransportSession.call(pid, {:stop, reason})
  end

  @spec call(session, request :: term, timeout) :: term

  @doc """
  Makes a syncronous call to the session.

  The call is handled by `handle_call/3` `SMPPEX.Session` callback.
  """
  def call(pid, request, timeout \\ @default_call_timeout) do
    TransportSession.call(pid, {:call, request}, timeout)
  end

  @spec cast(session, request :: term) :: :ok

  @doc """
  Makes an asyncronous call to Session.

  The call is handled by `handle_cast/2` `SMPPEX.Session` callback.
  """
  def cast(pid, request) do
    TransportSession.cast(pid, {:cast, request})
  end

  @spec reply(from, response :: term) :: :ok

  @doc """
  Replies to a client calling `Session.call` method.

  This function can be used to explicitly send a reply to a client that called `call/3`.

  `from` must be the `from` argument (the second argument) accepted by `handle_call/3` callbacks.

   The return value is always `:ok`.
  """
  def reply(from, response) do
    TransportSession.reply(from, response)
  end

  # SMPP.TransportSession callbacks

  @impl TransportSession
  def init(socket, transport, [{module, args}, session_opts]) do
    case module.init(socket, transport, args) do
      {:ok, state} ->
        enquire_link_limit =
          Keyword.get(session_opts, :enquire_link_limit, Defaults.enquire_link_limit())

        enquire_link_resp_limit =
          Keyword.get(session_opts, :enquire_link_resp_limit, Defaults.enquire_link_resp_limit())

        inactivity_limit =
          Keyword.get(session_opts, :inactivity_limit, Defaults.inactivity_limit())

        session_init_limit =
          Keyword.get(session_opts, :session_init_limit, Defaults.session_init_limit())

        timers =
          SMPPTimers.new(
            session_init_limit,
            enquire_link_limit,
            enquire_link_resp_limit,
            inactivity_limit
          )

        response_limit = Keyword.get(session_opts, :response_limit, Defaults.response_limit())

        response_limit_resolution =
          Keyword.get(
            session_opts,
            :response_limit_resolution,
            Defaults.response_limit_resolution()
          )

        pdu_storage = PduStorage.new(:custom_pdus, response_limit, response_limit_resolution)
        auto_pdu_storage = PduStorage.new(:auto_pdus, response_limit, response_limit_resolution)

        auto_pdu_handler = AutoPduHandler.new(auto_pdu_storage)

        sequence_number = Keyword.get(session_opts, :sequence_number, 0)

        {:ok,
         %Session{
           module: module,
           module_state: state,
           timers: timers,
           pdus: pdu_storage,
           auto_pdu_handler: auto_pdu_handler,
           response_limit: response_limit,
           sequence_number: sequence_number
         }}

      {:stop, _} = stop ->
        stop
    end
  end

  @impl TransportSession
  def handle_pdu({:unparsed_pdu, raw_pdu, error}, st) do
    {st.module.handle_unparsed_pdu(raw_pdu, error, st.module_state), st}
    |> process_handle_unparsed_pdu_reply()
  end

  def handle_pdu({:pdu, pdu}, st) do
    new_st = update_timers_with_incoming_pdu(pdu, st)

    case AutoPduHandler.handle_pdu(new_st.auto_pdu_handler, pdu) do
      {new_auto_pdu_handler, :proceed} ->
        handle_pdu_by_callback_module(pdu, %Session{
          new_st
          | auto_pdu_handler: new_auto_pdu_handler
        })

      {new_auto_pdu_handler, :skip} ->
        {:ok, [], %Session{new_st | auto_pdu_handler: new_auto_pdu_handler}}

      {new_auto_pdu_handler, :skip, pdus} ->
        {:ok, pdus, %Session{new_st | auto_pdu_handler: new_auto_pdu_handler}}
    end
  end

  @impl TransportSession
  def handle_send_pdu_result(pdu, send_pdu_result, st) do
    new_st = update_timers_with_outgoing_pdu(pdu, send_pdu_result, st)

    with {:error, _} <- send_pdu_result do
      _ = PduStorage.fetch(new_st.pdus, Pdu.sequence_number(pdu))
    end

    case AutoPduHandler.handle_send_pdu_result(new_st.auto_pdu_handler, pdu) do
      {new_auto_pdu_handler, :proceed} ->
        new_module_state =
          st.module.handle_send_pdu_result(pdu, send_pdu_result, new_st.module_state)

        %Session{new_st | auto_pdu_handler: new_auto_pdu_handler, module_state: new_module_state}

      {new_auto_pdu_handler, :skip} ->
        %Session{new_st | auto_pdu_handler: new_auto_pdu_handler}
    end
  end

  @impl TransportSession
  def handle_call({:send_pdu, pdu}, _from, st) do
    {{:reply, :ok, [pdu], st.module_state}, st}
    |> process_handle_call_reply()
  end

  def handle_call({:stop, reason}, _from, st) do
    {{:stop, reason, :ok, st.module_state}, st}
    |> process_handle_call_reply()
  end

  def handle_call({:call, request}, from, st) do
    {st.module.handle_call(request, from, st.module_state), st}
    |> process_handle_call_reply()
  end

  def handle_call(request, from, st) do
    handle_call({:call, request}, from, st)
  end

  @impl TransportSession
  def handle_cast({:cast, request}, st) do
    {st.module.handle_cast(request, st.module_state), st}
    |> process_handle_cast_reply()
  end

  def handle_cast(request, st) do
    handle_cast({:cast, request}, st)
  end

  @impl TransportSession
  def handle_info({:smpp_timer, _} = timer_event, st) do
    check_timers(timer_event, st)
  end

  def handle_info({:expire_pdus, pdu_storage_id}, st) do
    check_expired_pdus(pdu_storage_id, st)
  end

  def handle_info(request, st) do
    {st.module.handle_info(request, st.module_state), st}
    |> process_handle_info_reply()
  end

  @impl TransportSession
  def handle_socket_closed(st) do
    {reason, new_module_state} = st.module.handle_socket_closed(st.module_state)
    {reason, %Session{st | module_state: new_module_state}}
  end

  @impl TransportSession
  def handle_socket_error(error, st) do
    {reason, new_module_state} = st.module.handle_socket_error(error, st.module_state)
    {reason, %Session{st | module_state: new_module_state}}
  end

  @impl TransportSession
  def terminate(reason, st) do
    {new_pdu_storage, lost_pdus} = PduStorage.fetch_all(st.pdus)
    new_st = %Session{st | pdus: new_pdu_storage}

    case new_st.module.terminate(reason, lost_pdus, new_st.module_state) do
      :stop ->
        {[], new_st}

      {:stop, pdus, new_module_state} when is_list(pdus) ->
        {pdus, %Session{new_st | module_state: new_module_state}}

      other ->
        exit({:bad_terminate_reply, other})
    end
  end

  @impl TransportSession
  def code_change(old_vsn, st, extra) do
    case st.module.code_change(old_vsn, st.module_state, extra) do
      {:ok, new_module_state} ->
        {:ok, %Session{st | module_state: new_module_state}}

      {:error, _} = err ->
        err
    end
  end

  # Private

  defp handle_pdu_by_callback_module(pdu, st) do
    if Pdu.resp?(pdu) do
      pdu
      |> handle_resp_pdu(st)
      |> process_handle_resp_reply()
    else
      pdu
      |> handle_non_resp_pdu(st)
      |> process_handle_pdu_reply()
    end
  end

  defp handle_non_resp_pdu(pdu, st) do
    {st.module.handle_pdu(pdu, st.module_state), st}
  end

  defp handle_resp_pdu(pdu, st) do
    sequence_number = Pdu.sequence_number(pdu)

    case PduStorage.fetch(st.pdus, sequence_number) do
      {new_pdu_storage, []} ->
        new_st = %Session{st | pdus: new_pdu_storage}

        Logger.info(
          "Session #{inspect(self())}, resp for unknown pdu(sequence_number: #{sequence_number}), dropping"
        )

        {{:ok, new_st.module_state}, new_st}

      {new_pdu_storage, [original_pdu]} ->
        new_st = %Session{st | pdus: new_pdu_storage}
        {new_st.module.handle_resp(pdu, original_pdu, new_st.module_state), new_st}
    end
  end

  defp update_timers_with_incoming_pdu(pdu, st) do
    new_timers =
      cond do
        Pdu.bind_resp?(pdu) && Pdu.success_resp?(pdu) ->
          st.timers
          |> SMPPTimers.handle_bind()
          |> SMPPTimers.handle_peer_transaction()

        Pdu.resp?(pdu) ->
          st.timers
          |> SMPPTimers.handle_peer_action()

        true ->
          st.timers
          |> SMPPTimers.handle_peer_transaction()
      end

    %Session{st | timers: new_timers}
  end

  defp update_timers_with_outgoing_pdu(pdu, send_pdu_result, st) do
    new_timers =
      if send_pdu_result == :ok and Pdu.bind_resp?(pdu) and Pdu.success_resp?(pdu) do
        st.timers
        |> SMPPTimers.handle_bind()
      else
        st.timers
      end

    %Session{st | timers: new_timers}
  end

  defp check_expired_pdus(:auto_pdus, st) do
    :ok = AutoPduHandler.drop_expired(st.auto_pdu_handler)
    {:noreply, [], st}
  end

  defp check_expired_pdus(:custom_pdus, st) do
    case PduStorage.fetch_expired(st.pdus) do
      {new_pdu_storage, []} ->
        new_st = %Session{st | pdus: new_pdu_storage}
        {:noreply, [], new_st}

      {new_pdu_storage, pdus} ->
        new_st = %Session{st | pdus: new_pdu_storage}
        module_reply = st.module.handle_resp_timeout(pdus, new_st.module_state)
        process_handle_resp_timeout_reply({module_reply, new_st})
    end
  end

  defp check_timers(timer_event, st) do
    case SMPPTimers.handle_timer_event(st.timers, timer_event) do
      {:stop, reason} ->
        exit_reason = st.module.handle_timeout(reason, st.module_state)
        {:stop, exit_reason, [], st}

      {:enquire_link, new_timers} ->
        new_sequence_number = st.sequence_number + 1

        {new_auto_pdu_handler, enquire_link} =
          AutoPduHandler.enquire_link(
            st.auto_pdu_handler,
            new_sequence_number
          )

        {:noreply, [enquire_link],
         %Session{
           st
           | sequence_number: new_sequence_number,
             auto_pdu_handler: new_auto_pdu_handler,
             timers: new_timers
         }}
    end
  end

  defp save_sent_pdus(pdus, st, pdus_to_send \\ [])
  defp save_sent_pdus([], st, pdus_to_send), do: {st, Enum.reverse(pdus_to_send)}

  defp save_sent_pdus([pdu | pdus], st, pdus_to_send) do
    if Pdu.resp?(pdu) do
      save_sent_pdus(pdus, st, [pdu | pdus_to_send])
    else
      sequence_number = st.sequence_number + 1
      new_pdu = %Pdu{pdu | sequence_number: sequence_number}
      new_pdu_storage = PduStorage.store(st.pdus, new_pdu)
      new_st = %Session{st | sequence_number: sequence_number, pdus: new_pdu_storage}
      save_sent_pdus(pdus, new_st, [new_pdu | pdus_to_send])
    end
  end

  defp process_handle_pdu_reply({{:ok, _mst}, _st} = arg), do: process_reply(arg)
  defp process_handle_pdu_reply({{:ok, _pdus, _mst}, _st} = arg), do: process_reply(arg)
  defp process_handle_pdu_reply({{:stop, _reason, _mst}, _st} = arg), do: process_reply(arg)
  defp process_handle_pdu_reply({reply, st}), do: {:stop, {:bad_handle_pdu_reply, reply}, [], st}

  defp process_handle_unparsed_pdu_reply({{:ok, _mst}, _st} = arg), do: process_reply(arg)
  defp process_handle_unparsed_pdu_reply({{:ok, _pdus, _mst}, _st} = arg), do: process_reply(arg)

  defp process_handle_unparsed_pdu_reply({{:stop, _reason, _mst}, _st} = arg),
    do: process_reply(arg)

  defp process_handle_unparsed_pdu_reply({reply, st}),
    do: {:stop, {:bad_handle_unparsed_pdu_reply, reply}, [], st}

  defp process_handle_resp_reply({{:ok, _mst}, _st} = arg), do: process_reply(arg)
  defp process_handle_resp_reply({{:ok, _pdus, _mst}, _st} = arg), do: process_reply(arg)
  defp process_handle_resp_reply({{:stop, _reason, _mst}, _st} = arg), do: process_reply(arg)

  defp process_handle_resp_reply({reply, st}),
    do: {:stop, {:bad_handle_resp_reply, reply}, [], st}

  defp process_handle_resp_timeout_reply({{:ok, mst}, st}),
    do: process_reply({{:noreply, mst}, st})

  defp process_handle_resp_timeout_reply({{:ok, pdus, mst}, st}),
    do: process_reply({{:noreply, pdus, mst}, st})

  defp process_handle_resp_timeout_reply({{:stop, _reason, _mst}, _st} = arg),
    do: process_reply(arg)

  defp process_handle_resp_timeout_reply({reply, st}),
    do: {:stop, {:bad_handle_resp_timeout_reply, reply}, [], st}

  defp process_handle_call_reply({{:reply, _reply, _mst}, _st} = arg), do: process_reply(arg)

  defp process_handle_call_reply({{:reply, _reply, _pdus, _mst}, _st} = arg),
    do: process_reply(arg)

  defp process_handle_call_reply({{:noreply, _pdus, _mst}, _st} = arg), do: process_reply(arg)
  defp process_handle_call_reply({{:noreply, _mst}, _st} = arg), do: process_reply(arg)
  defp process_handle_call_reply({{:stop, _rsn, _reply, _mst}, _st} = arg), do: process_reply(arg)
  defp process_handle_call_reply({{:stop, _rsn, _mst}, _st} = arg), do: process_reply(arg)

  defp process_handle_call_reply({reply, st}),
    do: {:stop, {:bad_handle_call_reply, reply}, [], st}

  defp process_handle_cast_reply({{:noreply, _pdus, _mst}, _st} = arg), do: process_reply(arg)
  defp process_handle_cast_reply({{:noreply, _mst}, _st} = arg), do: process_reply(arg)
  defp process_handle_cast_reply({{:stop, _rsn, _mst}, _st} = arg), do: process_reply(arg)

  defp process_handle_cast_reply({reply, st}),
    do: {:stop, {:bad_handle_cast_reply, reply}, [], st}

  defp process_handle_info_reply({{:noreply, _pdus, _mst}, _st} = arg), do: process_reply(arg)
  defp process_handle_info_reply({{:noreply, _mst}, _st} = arg), do: process_reply(arg)
  defp process_handle_info_reply({{:stop, _rsn, _mst}, _st} = arg), do: process_reply(arg)

  defp process_handle_info_reply({reply, st}),
    do: {:stop, {:bad_handle_info_reply, reply}, [], st}

  defp process_reply({{:ok, module_state}, st}) do
    {:ok, [], %Session{st | module_state: module_state}}
  end

  defp process_reply({{:ok, pdus, module_state}, st}) do
    {new_st, pdus_to_send} = save_sent_pdus(pdus, st)
    {:ok, pdus_to_send, %Session{new_st | module_state: module_state}}
  end

  defp process_reply({{:reply, reply, module_state}, st}) do
    {:reply, reply, [], %Session{st | module_state: module_state}}
  end

  defp process_reply({{:reply, reply, pdus, module_state}, st}) do
    {new_st, pdus_to_send} = save_sent_pdus(pdus, st)
    {:reply, reply, pdus_to_send, %Session{new_st | module_state: module_state}}
  end

  defp process_reply({{:noreply, module_state}, st}) do
    {:noreply, [], %Session{st | module_state: module_state}}
  end

  defp process_reply({{:noreply, pdus, module_state}, st}) do
    {new_st, pdus_to_send} = save_sent_pdus(pdus, st)
    {:noreply, pdus_to_send, %Session{new_st | module_state: module_state}}
  end

  defp process_reply({{:stop, reason, reply, module_state}, st}) do
    {:stop, reason, reply, [], %Session{st | module_state: module_state}}
  end

  defp process_reply({{:stop, reason, module_state}, st}) do
    {:stop, reason, [], %Session{st | module_state: module_state}}
  end
end
