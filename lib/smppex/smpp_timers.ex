defmodule SMPPEX.SMPPTimers do
  @moduledoc false

  alias SMPPEX.SMPPTimers

  # :established -> :bound
  # :active <-> :waiting_resp
  defstruct(
    # session_init_timer
    session_init_state: :established,
    session_init_limit: 0,
    session_init_timer: nil,

    # enquire_link_timer
    enquire_link_state: :active,
    enquire_link_limit: 0,
    enquire_link_timer: nil,

    # enquire_link_resp_timer
    enquire_link_resp_limit: 0,
    enquire_link_resp_timer: nil,

    # inactivity_timer
    inactivity_limit: 0,
    inactivity_timer: nil
  )

  @type t :: %SMPPTimers{}

  @type stop_reason :: :session_init_timer | :inactivity_timer | :enquire_link_timer
  @type timer_name ::
          :session_init_timer | :inactivity_timer | :enquire_link_timer | :enquire_link_resp_timer
  @type timer_event :: {:smpp_timer, timer_name}

  @spec new(timeout, timeout, timeout, timeout) :: t

  def new(session_init_limit, enquire_link_limit, enquire_link_resp_limit, inactivity_limit) do
    %SMPPTimers{
      session_init_limit: session_init_limit,
      enquire_link_limit: enquire_link_limit,
      enquire_link_resp_limit: enquire_link_resp_limit,
      inactivity_limit: inactivity_limit
    }
    |> reschedule_timer(:session_init_timer, :session_init_limit)
  end

  @spec handle_bind(t) :: t

  def handle_bind(timers) do
    %SMPPTimers{timers | session_init_state: :bound}
    |> cancel_timer(:session_init_timer)
    |> reschedule_timer(:inactivity_timer, :inactivity_limit)
    |> reschedule_timer(:enquire_link_timer, :enquire_link_limit)
  end

  @spec handle_peer_transaction(t) :: t

  def handle_peer_transaction(timers) do
    timers
    |> handle_peer_action()
    |> reschedule_timer(:inactivity_timer, :inactivity_limit)
  end

  @spec handle_peer_action(t) :: t

  def handle_peer_action(timers) do
    %SMPPTimers{timers | enquire_link_state: :active}
    |> reschedule_timer(:enquire_link_timer, :enquire_link_limit)
    |> cancel_timer(:enquire_link_resp_timer)
  end

  @type timer_event_result :: {:ok, t} | {:stop, reason :: stop_reason} | {:enquire_link, t}

  @spec handle_timer_event(t, timer_event) :: timer_event_result

  def handle_timer_event(_timers, {:smpp_timer, :inactivity_timer}) do
    {:stop, :inactivity_timer}
  end

  def handle_timer_event(_timers, {:smpp_timer, :session_init_timer}) do
    {:stop, :session_init_timer}
  end

  def handle_timer_event(timers, {:smpp_timer, :enquire_link_timer}) do
    new_timers =
      %SMPPTimers{timers | enquire_link_state: :waiting_resp}
      |> cancel_timer(:enquire_link_timer)
      |> reschedule_timer(:enquire_link_resp_timer, :enquire_link_resp_limit)

    {:enquire_link, new_timers}
  end

  def handle_timer_event(_timers, {:smpp_timer, :enquire_link_resp_timer}) do
    {:stop, :enquire_link_timer}
  end

  defp reschedule_timer(timers, timer_name, interval_name) do
    timers_new = cancel_timer(timers, timer_name)
    interval = Map.fetch!(timers, interval_name)
    schedule_timer(timers_new, timer_name, interval)
  end

  defp cancel_timer(timers, timer_name) do
    case Map.fetch!(timers, timer_name) do
      nil ->
        timers

      timer_ref ->
        Klotho.cancel_timer(timer_ref)
        Map.put(timers, timer_name, nil)
    end
  end

  defp schedule_timer(timers, _timer_name, interval)
       when interval == 0 or interval == :infinity do
    timers
  end

  defp schedule_timer(timers, timer_name, interval) do
    # dbg([:schedule_timer, timer_name, interval])
    timer_ref = Klotho.send_after(interval, self(), {:smpp_timer, timer_name})
    Map.put(timers, timer_name, timer_ref)
  end
end
