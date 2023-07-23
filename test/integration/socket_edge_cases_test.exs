defmodule SMPPEX.Integration.SocketEdgeCasesTest do
  use ExUnit.Case

  require Logger

  @moduletag :ssl

  alias Support.SSL.MC
  alias Support.SSL.ESME
  alias Support.TCP.Helpers

  test "denying mc" do
    Process.flag(:trap_exit, true)

    port = Helpers.find_free_port()
    start_supervised!({MC, {port, "good.rubybox.dev", false}})

    {:ok, pid} = ESME.start_link(port, "good.rubybox.dev")

    receive do
      {:EXIT, ^pid, :socket_closed} -> :ok
      {:EXIT, ^pid, {:socket_error, :closed}} -> :ok
    after
      1000 ->
        flunk("ESME should have been terminated")
    end
  end

  test "socket closed before esme finishes initialization" do
    Process.flag(:trap_exit, true)

    port = Helpers.find_free_port()

    pid = self()

    ## Quite a complex setup we need here:
    ## * MC should start accepting connections
    ## * ESME should start connecting to MC
    ## * ESME should connect to MC and start `init` callback
    ## * MC should accept TCP connection and refuse it in MC Session's `init` callback
    ## * MC Session should close connection
    ## * ESME should still be in `init` callback and continue with :ok (having TCP connection closed)
    ## * ESME should be correctly terminated

    ## To achieve this we inject `delay` inside ESME Session's `init` callback
    ## and `accept` inside MC Session's `init` callback

    accept = fn ->
      send(pid, {:accept, self()})

      receive do
        {:accept, res} -> res
      after
        1000 ->
          flunk("MC should have received :accept")
      end
    end

    delay = fn ->
      send(pid, {:esme_pid, self()})

      receive do
        :continue -> :ok
      after
        1000 ->
          flunk("ESME should have received :continue")
      end
    end

    start_supervised!({MC, {port, "good.rubybox.dev", accept}})
    spawn_link(fn -> ESME.start_link(port, "good.rubybox.dev", delay) end)

    receive do
      {:accept, mc_pid} ->
        mref = :erlang.monitor(:process, mc_pid)
        send(mc_pid, {:accept, {:stop, :ooops}})

        receive do
          {:DOWN, ^mref, :process, ^mc_pid, :ooops} -> :ok
        after
          1000 ->
            flunk("MC should have been terminated")
        end
    after
      1000 ->
        flunk("MC accept should have been called")
    end

    receive do
      {:esme_pid, esme_pid} ->
        mref = :erlang.monitor(:process, esme_pid)
        send(esme_pid, :continue)

        receive do
          {:DOWN, ^mref, :process, ^esme_pid, :socket_closed} -> :ok
          {:DOWN, ^mref, :process, ^esme_pid, {:socket_error, :closed}} -> :ok
        after
          1000 ->
            flunk("ESME should have been terminated")
        end
    after
      1000 ->
        flunk("ESME should have received :continue")
    end
  end
end
