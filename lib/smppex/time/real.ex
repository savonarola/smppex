defmodule SMPPEX.Time.Real do
  def monotonic_time(unit) do
    :erlang.monotonic_time(unit)
  end

  def monotonic_time() do
    :erlang.monotonic_time()
  end

  def send_after(pid, time, message) do
    :erlang.send_after(pid, time, message)
  end

  def cancel_timer(ref) do
    :erlang.cancel_timer(ref)
  end
end
