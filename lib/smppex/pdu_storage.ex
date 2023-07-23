defmodule SMPPEX.PduStorage do
  @moduledoc false

  alias SMPPEX.PduStorage
  alias SMPPEX.Pdu

  import Ex2ms

  defstruct id: nil,
            by_sequence_number: nil,
            by_expire: nil,
            ttl: nil,
            ttl_threshold: nil,
            timer: nil

  @type t :: %PduStorage{}

  @spec new(term, non_neg_integer, non_neg_integer) :: t

  def new(id, ttl, ttl_threshold) do
    %PduStorage{
      id: id,
      by_sequence_number: :ets.new(:pdu_storage_by_sequence_number, [:set]),
      by_expire: :ets.new(:pdu_storage_by_expire, [:ordered_set]),
      ttl: ttl,
      ttl_threshold: ttl_threshold
    }
  end

  @spec store(t, Pdu.t()) :: boolean

  def store(storage, %Pdu{} = pdu) do
    sequence_number = Pdu.sequence_number(pdu)
    ref = Pdu.ref(pdu)
    create_time = Klotho.monotonic_time(:millisecond)
    :ets.insert_new(storage.by_sequence_number, {sequence_number, {create_time, pdu}})
    :ets.insert_new(storage.by_expire, {{create_time, ref}, sequence_number})
    schedule_expire(storage, create_time)
  end

  @spec fetch(t, non_neg_integer) :: {t, [Pdu.t()]}

  def fetch(storage, sequence_number) do
    case :ets.take(storage.by_sequence_number, sequence_number) do
      [{^sequence_number, {create_time, pdu}}] ->
        ref = Pdu.ref(pdu)
        :ets.delete(storage.by_expire, {create_time, ref})
        new_storage = reschedule_expire(storage, create_time)
        {new_storage, [pdu]}

      [] ->
        {storage, []}
    end
  end

  @spec fetch_expired(t) :: {t, [Pdu.t()]}

  def fetch_expired(storage) do
    deadline = Klotho.monotonic_time(:millisecond) - storage.ttl

    expired_ms =
      fun do
        {{create_time, ref}, sequence_number} when create_time < ^deadline ->
          {ref, sequence_number}
      end

    expired = :ets.select(storage.by_expire, expired_ms)

    pdus =
      for {ref, sequence_number} <- expired, into: [] do
        [{_sn, {create_time, pdu}}] = :ets.take(storage.by_sequence_number, sequence_number)
        :ets.delete(storage.by_expire, {create_time, ref})
        pdu
      end

    {reschedule_expire(storage, nil), pdus}
  end

  @spec fetch_all(t) :: {t, [Pdu.t()]}

  def fetch_all(storage) do
    pdus = for {_sn, {_ex, pdu}} <- :ets.tab2list(storage.by_sequence_number), do: pdu
    :ets.delete_all_objects(storage.by_sequence_number)
    :ets.delete_all_objects(storage.by_expire)
    {cancel_expire(storage), pdus}
  end

  # On inserting new PDU, we schedule expire timer only if it's not scheduled yet
  # Because if it is already scheduled, it is scheduled on earlier time.
  defp schedule_expire(%PduStorage{id: id, timer: nil} = storage, create_time) do
    timer_interval = timer_interval(storage, create_time)
    timer = Klotho.send_after(timer_interval, self(), {:expire_pdus, id})
    %PduStorage{storage | timer: timer}
  end

  defp schedule_expire(storage, _) do
    storage
  end

  defp cancel_expire(%PduStorage{timer: nil} = storage) do
    storage
  end

  defp cancel_expire(%PduStorage{timer: timer} = storage) do
    Klotho.cancel_timer(timer)
    %PduStorage{storage | timer: nil}
  end

  # This is called when a PDU is fetched from storage.
  defp reschedule_expire(storage, fetched_create_time) do
    case :ets.first(storage.by_expire) do
      {create_time, _ref} ->
        # There is still something left in
        if create_time > fetched_create_time or fetched_create_time == nil do
          # We fetched the first (erliest) PDU, but there is still something left in storage
          # We should postpone the timer to the next PDU's expire time
          storage
          |> cancel_expire()
          |> schedule_expire(create_time)
        else
          storage
        end

      :"$end_of_table" ->
        # Nothing left in storage, cancel timer
        cancel_expire(storage)
    end
  end

  defp timer_interval(%PduStorage{ttl_threshold: ttl_threshold, ttl: ttl}, create_time) do
    interval = create_time + ttl + ttl_threshold - Klotho.monotonic_time(:millisecond)

    if interval < 0 do
      ttl_threshold
    else
      interval
    end
  end
end
