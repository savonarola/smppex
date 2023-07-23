defmodule Support.TCP.Helpers do
  @moduledoc false

  alias :gen_tcp, as: GenTCP
  alias :inet, as: INET

  def find_free_port do
    {:ok, socket} = GenTCP.listen(0, [])
    {:ok, port} = INET.port(socket)
    :ok = GenTCP.close(socket)
    # assume no one will immediately take this port
    port
  end

  def wait_match(fun, n \\ 10, interval \\ 10)

  def wait_match(fun, n, interval) when n <= 0 do
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
