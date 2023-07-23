defmodule SMPPEX.PduStorageTest do
  use ExUnit.Case

  alias SMPPEX.PduStorage
  alias SMPPEX.Pdu

  @id :pdu_storage_id
  @ttl 1000
  @ttl_threshold 10

  setup do
    Klotho.Mock.reset()
    {:ok, storage: PduStorage.new(@id, @ttl, @ttl_threshold)}
  end

  test "store", %{storage: storage0} do
    pdu1 = %Pdu{SMPPEX.Pdu.Factory.bind_transmitter("system_id1", "pass1") | sequence_number: 123}
    pdu2 = %Pdu{SMPPEX.Pdu.Factory.bind_transmitter("system_id2", "pass2") | sequence_number: 123}

    storage1 = PduStorage.store(storage0, pdu1)
    storage2 = PduStorage.store(storage1, pdu2)

    {_, pdus} = PduStorage.fetch(storage2, 123)

    assert pdus == [pdu1]
  end

  test "fetch", %{storage: storage0} do
    pdu = %Pdu{SMPPEX.Pdu.Factory.bind_transmitter("system_id", "pass") | sequence_number: 123}

    storage1 = PduStorage.store(storage0, pdu)

    assert {storage2, [_pdu]} = PduStorage.fetch(storage1, 123)
    assert {_, []} = PduStorage.fetch(storage2, 123)
    assert {_, []} = PduStorage.fetch(storage2, 124)
  end

  test "expire", %{storage: storage0} do
    pdu1 = %Pdu{SMPPEX.Pdu.Factory.bind_transmitter("system_id1", "pass") | sequence_number: 123}
    pdu2 = %Pdu{SMPPEX.Pdu.Factory.bind_transmitter("system_id2", "pass") | sequence_number: 124}

    storage1 = PduStorage.store(storage0, pdu1)
    Klotho.Mock.warp_by(500)
    storage2 = PduStorage.store(storage1, pdu2)
    # 1250
    Klotho.Mock.warp_by(750)

    assert_received {:expire_pdus, @id}

    assert {storage3, [^pdu1]} = PduStorage.fetch_expired(storage2)
    assert {storage4, []} = PduStorage.fetch(storage3, 123)
    assert {_storage5, [^pdu2]} = PduStorage.fetch(storage4, 124)
  end

  test "stop && lost_pdus", %{storage: storage0} do
    pdu1 = %Pdu{SMPPEX.Pdu.Factory.bind_transmitter("system_id1", "pass") | sequence_number: 123}
    pdu2 = %Pdu{SMPPEX.Pdu.Factory.bind_transmitter("system_id2", "pass") | sequence_number: 124}

    storage1 = PduStorage.store(storage0, pdu1)
    storage2 = PduStorage.store(storage1, pdu2)

    {_, pdus} = PduStorage.fetch_all(storage2)
    assert Enum.sort([pdu1, pdu2]) == Enum.sort(pdus)
  end
end
