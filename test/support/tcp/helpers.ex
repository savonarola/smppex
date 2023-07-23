defmodule Support.TCP.Helpers do
  @moduledoc false

  def find_free_port do
    {:ok, socket} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    # assume no one will immediately take this port
    port
  end

  def wait_match(fun, n \\ 20, interval \\ 5)

  def wait_match(_fun, n, _interval) when n <= 0 do
    false
  end

  def wait_match(fun, n, interval) do
    try do
      fun.()
    rescue
      MatchError ->
        :timer.sleep(interval)
        wait_match(fun, n - 1, interval)
    end
  end

  def sync(esme) do
    SMPPEX.Session.call(esme, :sync)
  catch
    _, _ -> :ok
  end
end
