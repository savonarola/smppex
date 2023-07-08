defmodule SMPPEX.Time do
  if Mix.env() == :test do
    @moduledoc """
    This module is used to mock the time in tests.
    """
    @backend SMPPEX.Time.Mock
  else
    @moduledoc false
    @backend SMPPEX.Time.Real
  end

  def monotonic_time(unit) do
    @backend.monotonic_time(unit)
  end

  def monotonic_time() do
    @backend.monotonic_time()
  end

  def send_after(pid, time, message) do
    @backend.send_after(pid, time, message)
  end

  def cancel_timer(ref) do
    @backend.cancel_timer(ref)
  end
end
