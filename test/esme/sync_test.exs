defmodule SMPPEX.ESME.SyncTest do
  use ExUnit.Case

  alias SMPPEX.Session
  alias SMPPEX.MC
  alias SMPPEX.Pdu
  alias SMPPEX.ESME.Sync, as: ESMESync

  import Support.TCP.Helpers

  setup do
    {:ok, callback_agent} = Agent.start_link(fn -> [] end)

    callbacks = fn ->
      Agent.get(
        callback_agent,
        &Enum.reverse(&1)
      )
    end

    mc_opts = [
      enquire_link_limit: 1000,
      session_init_limit: :infinity,
      enquire_link_resp_limit: 1000,
      inactivity_limit: 10_000,
      response_limit: 2000,
      response_limit_resolution: 100_000
    ]

    port = Support.TCP.Helpers.find_free_port()

    mc_with_opts = fn handler, opts ->
      test_pid = self()

      start_supervised!({
        MC,
        session: {Support.Session, {callback_agent, handler, test_pid}},
        transport_opts: [port: port],
        mc_opts: opts
      })
    end

    mc = &mc_with_opts.(&1, mc_opts)

    esme_with_opts = fn opts ->
      {:ok, pid} = SMPPEX.ESME.Sync.start_link("127.0.0.1", port, opts)
      pid
    end

    esme = fn -> esme_with_opts.([]) end

    {
      :ok,
      mc: mc,
      mc_with_opts: mc_with_opts,
      callbacks: callbacks,
      port: port,
      esme: esme,
      esme_with_opts: esme_with_opts
    }
  end

  test "request and response", ctx do
    ctx[:mc].(fn
      {:init, _, _}, st ->
        {:ok, st}

      {:handle_pdu, pdu}, st ->
        {:ok, [SMPPEX.Pdu.Factory.bind_transmitter_resp(0, "sid") |> Pdu.as_reply_to(pdu)], st}

      {:handle_send_pdu_result, _, _}, st ->
        st
    end)

    esme = ctx[:esme].()

    1..100
    |> Enum.map(fn _ ->
      Task.async(fn ->
        pdu = SMPPEX.Pdu.Factory.bind_transmitter("system_id", "password")
        assert {:ok, resp} = ESMESync.request(esme, pdu)
        assert :bind_transmitter_resp == Pdu.command_name(resp)
      end)
    end)
    |> Enum.each(fn task ->
      Task.await(task)
    end)
  end

  test "request and stop", ctx do
    Process.flag(:trap_exit, true)

    ctx[:mc].(fn
      {:init, _, _}, st ->
        {:ok, st}

      {:handle_pdu, _pdu}, st ->
        {:stop, :oops, st}

      {:handle_send_pdu_result, _, _}, st ->
        st
    end)

    esme = ctx[:esme].()
    pdu = SMPPEX.Pdu.Factory.bind_transmitter("system_id", "password")
    assert :stop = ESMESync.request(esme, pdu)
  end

  test "request and timeout", ctx do
    Process.flag(:trap_exit, true)

    ctx[:mc].(fn
      {:init, _, _}, st ->
        {:ok, st}

      {:handle_pdu, _pdu}, st ->
        {:ok, st}
    end)

    esme = ctx[:esme].()
    pdu = SMPPEX.Pdu.Factory.bind_transmitter("system_id", "password")
    assert :timeout = ESMESync.request(esme, pdu, 50)
  end

  test "request and session timeout", ctx do
    esme_opts = [
      response_limit: 50,
      response_limit_resolution: 5
    ]

    ctx[:mc].(fn
      {:init, _, _}, st ->
        {:ok, st}

      {:handle_pdu, _pdu}, st ->
        {:ok, st}
    end)

    esme = ctx[:esme_with_opts].(esme_opts: esme_opts)
    pdu = SMPPEX.Pdu.Factory.bind_transmitter("system_id", "password")
    assert :timeout = ESMESync.request(esme, pdu, 100)
  end

  test "request and error", ctx do
    Process.flag(:trap_exit, true)

    ctx[:mc].(fn
      {:init, _, _}, st ->
        {:ok, st}

      {:handle_pdu, _pdu}, st ->
        {:ok, st}
    end)

    esme = ctx[:esme].()
    pdu = SMPPEX.Pdu.Factory.bind_transmitter("system_id", "too_long_password")
    assert {:error, _} = ESMESync.request(esme, pdu)
  end

  test "wait_for_pdus, blocking", ctx do
    pid = self()

    ctx[:mc].(fn
      {:init, _, _}, st ->
        send(pid, self())
        {:ok, st}

      {:handle_send_pdu_result, _, _}, st ->
        st
    end)

    esme = ctx[:esme].()

    mc_session =
      receive do
        pid when is_pid(pid) -> pid
      end

    spawn_link(fn ->
      Session.send_pdu(mc_session, SMPPEX.Pdu.Factory.bind_transmitter("system_id", "password"))
    end)

    assert [pdu: _] = ESMESync.wait_for_pdus(esme, 10)
  end

  test "wait_for_pdus, send_pdu result", ctx do
    ctx[:mc].(fn
      {:init, _, _}, st ->
        {:ok, st}

      {:handle_pdu, _pdu}, st ->
        {:ok, st}

      {:handle_send_pdu_result, _, _}, st ->
        st
    end)

    esme = ctx[:esme].()

    spawn_link(fn ->
      Session.send_pdu(esme, SMPPEX.Pdu.Factory.enquire_link())
    end)

    assert [ok: _] = ESMESync.wait_for_pdus(esme)
  end

  test "wait_for_pdus, send_pdu error", ctx do
    ctx[:mc].(fn
      {:init, _, _}, st ->
        {:ok, st}

      {:handle_pdu, pdu}, st ->
        {:ok, [SMPPEX.Pdu.Factory.enquire_link_resp() |> Pdu.as_reply_to(pdu)], st}

      {:handle_send_pdu_result, _, _}, st ->
        st
    end)

    esme = ctx[:esme].()

    pid = self()

    spawn_link(fn ->
      Session.send_pdu(
        esme,
        SMPPEX.Pdu.Factory.bind_transmitter("system_id", "too_long_password")
      )

      send(pid, :done)
    end)

    receive do
      :done -> :ok
    end

    assert [{:error, _pdu, _error}] = ESMESync.wait_for_pdus(esme)
  end

  test "wait_for_pdus, resp", ctx do
    test_pid = self()

    ctx[:mc].(fn
      {:init, _, _}, st ->
        {:ok, st}

      {:handle_pdu, pdu}, st ->
        pid = self()
        resp = SMPPEX.Pdu.Factory.bind_transmitter_resp(0) |> Pdu.as_reply_to(pdu)
        send(test_pid, {pid, resp})
        {:ok, [], st}

      {:handle_send_pdu_result, _, _}, st ->
        st
    end)

    esme = ctx[:esme].()

    Session.send_pdu(esme, SMPPEX.Pdu.Factory.bind_transmitter("system_id", "password"))
    assert [ok: _] = ESMESync.wait_for_pdus(esme)

    receive do
      {mc_sess_pid, resp} when is_pid(mc_sess_pid) ->
        Session.send_pdu(mc_sess_pid, resp)
    end

    assert [{:resp, _, _}] = ESMESync.wait_for_pdus(esme, 60)
  end

  test "wait_for_pdus, resp timeout", ctx do
    esme_opts = [
      response_limit: 50,
      response_limit_resolution: 5
    ]

    ctx[:mc].(fn
      {:init, _, _}, st ->
        {:ok, st}

      {:handle_pdu, _pdu}, st ->
        {:ok, st}

      {:handle_send_pdu_result, _, _}, st ->
        st
    end)

    esme = ctx[:esme_with_opts].(esme_opts: esme_opts)

    Session.send_pdu(esme, SMPPEX.Pdu.Factory.bind_transmitter("system_id", "password"))
    assert [ok: _] = ESMESync.wait_for_pdus(esme)
    assert [{:timeout, _}] = ESMESync.wait_for_pdus(esme, 100)
  end

  test "wait_for_pdus, timeout", ctx do
    ctx[:mc].(fn {:init, _, _}, st ->
      {:ok, st}
    end)

    esme = ctx[:esme].()

    assert :timeout = ESMESync.wait_for_pdus(esme, 5)
  end

  test "stop", ctx do
    ctx[:mc].(fn {:init, _, _}, st ->
      {:ok, st}
    end)

    esme = ctx[:esme].()

    :erlang.monitor(:process, esme)

    assert :ok = ESMESync.stop(esme)

    assert_receive {:DOWN, _, :process, ^esme, :normal}
  end

  test "pdus", ctx do
    pid = self()

    ctx[:mc].(fn
      {:init, _, _}, st ->
        send(pid, self())
        {:ok, st}

      {:handle_send_pdu_result, _, _}, st ->
        st
    end)

    esme = ctx[:esme].()

    mc_session =
      receive do
        pid when is_pid(pid) -> pid
      end

    Session.send_pdu(mc_session, SMPPEX.Pdu.Factory.bind_transmitter("system_id", "password"))

    assert wait_match(fn -> [pdu: _] = ESMESync.pdus(esme) end)
  end
end
