defmodule SMPPEX.SMPPTimersTest do
  use ExUnit.Case

  alias SMPPEX.SMPPTimers

  @session_init_limit 300
  @enquire_link_limit 600
  @enquire_link_resp_limit 300
  @inactivity_limit 6000

  setup do
    Klotho.Mock.reset()

    timers =
      SMPPTimers.new(
        @session_init_limit,
        @enquire_link_limit,
        @enquire_link_resp_limit,
        @inactivity_limit
      )

    {:ok, timers: timers}
  end

  # new(session_init_limit, enquire_link_limit, enquire_link_resp_limit, inactivity_limit)

  test "session_init_timer", %{timers: timers} do
    Klotho.Mock.warp_by(400)
    assert_received {:smpp_timer, :session_init_timer} = event
    assert {:stop, :session_init_timer} == SMPPTimers.handle_timer_event(timers, event)
  end

  test "enquire_link (stop)", %{timers: timers0} do
    timers = SMPPTimers.handle_bind(timers0)

    Klotho.Mock.warp_by(590)
    refute_received {:smpp_timer, :enquire_link_timer}
    # 610
    Klotho.Mock.warp_by(20)
    assert_received {:smpp_timer, :enquire_link_timer} = event0
    assert {:enquire_link, timers1} = SMPPTimers.handle_timer_event(timers, event0)
    # 910
    Klotho.Mock.warp_by(300)
    assert_received {:smpp_timer, :enquire_link_resp_timer} = event1
    assert {:stop, :enquire_link_timer} == SMPPTimers.handle_timer_event(timers1, event1)
  end

  test "enquire_link (recover by peer action)", %{timers: timers0} do
    timers = SMPPTimers.handle_bind(timers0)

    Klotho.Mock.warp_by(610)
    assert_received {:smpp_timer, :enquire_link_timer} = event0
    assert {:enquire_link, timers1} = SMPPTimers.handle_timer_event(timers, event0)
    # 890
    Klotho.Mock.warp_by(280)
    _timers2 = SMPPTimers.handle_peer_action(timers1)
    # 990
    Klotho.Mock.warp_by(100)
    refute_received {:smpp_timer, :enquire_link_resp_timer}
  end

  test "enquire_link (recover by peer transaction)", %{timers: timers0} do
    timers = SMPPTimers.handle_bind(timers0)

    Klotho.Mock.warp_by(610)
    assert_received {:smpp_timer, :enquire_link_timer} = event0
    assert {:enquire_link, timers1} = SMPPTimers.handle_timer_event(timers, event0)
    # 890
    Klotho.Mock.warp_by(280)
    _timers2 = SMPPTimers.handle_peer_transaction(timers1)
    # 990
    Klotho.Mock.warp_by(100)
    refute_received {:smpp_timer, :enquire_link_resp_timer}
  end

  test "inactivity_timer", %{timers: timers0} do
    timers1 = SMPPTimers.handle_bind(timers0)
    # 5950
    Klotho.Mock.warp_by(5950)
    timers2 = SMPPTimers.handle_peer_action(timers1)
    # 6050
    Klotho.Mock.warp_by(100)

    assert_received {:smpp_timer, :inactivity_timer} = event
    assert {:stop, :inactivity_timer} == SMPPTimers.handle_timer_event(timers2, event)
  end

  test "inactivity_timer (recover by peer transaction)", %{timers: timers0} do
    timers1 = SMPPTimers.handle_bind(timers0)
    # 5950
    Klotho.Mock.warp_by(5950)
    _timers2 = SMPPTimers.handle_peer_transaction(timers1)
    # 6050
    Klotho.Mock.warp_by(100)

    refute_received {:smpp_timer, :inactivity_timer}
  end
end
