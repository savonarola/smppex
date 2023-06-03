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
    start_supervised!({MC, {port, "good.rubybox.dev", false}})
    {:ok, pid} = ESME.start_link(port, "good.rubybox.dev", 100)

    receive do
      {:EXIT, ^pid, :socket_closed} -> :ok
      {:EXIT, ^pid, {:socket_error, :closed}} -> :ok
    after
      1000 ->
        flunk("ESME should have been terminated")
    end
  end
end
