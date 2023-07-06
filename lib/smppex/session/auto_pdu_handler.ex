defmodule SMPPEX.Session.AutoPduHandler do
  @moduledoc false

  defstruct [
    :pdu_storage,
    :my_pdu_refs
  ]

  alias __MODULE__, as: AutoPduHandler

  alias SMPPEX.Pdu.Factory, as: PduFactory
  alias SMPPEX.PduStorage
  alias SMPPEX.Pdu

  @type t :: %AutoPduHandler{}

  @spec new(PduStorage.t) :: t

  def new(pdu_storage) do
    %AutoPduHandler{
      # In PDU storage, we store request PDUs that we generated (enquire_link's)
      pdu_storage: pdu_storage,
      # In my_pdu_refs, we store refs of all PDUs that we generated (enquire_link's and enquire_link_resp's)
      # We need this to track which PDUs we generated and tell the session to skip them
      my_pdu_refs: MapSet.new()
    }
  end

  @spec enquire_link(t, non_neg_integer) :: {t, Pdu.t()}

  def enquire_link(handler, sequence_number) do
    pdu = %Pdu{PduFactory.enquire_link() | sequence_number: sequence_number}
    new_pdu_storage = PduStorage.store(handler.pdu_storage, pdu)
    new_my_pdu_refs = MapSet.put(handler.my_pdu_refs, Pdu.ref(pdu))
    {%AutoPduHandler{handler | pdu_storage: new_pdu_storage, my_pdu_refs: new_my_pdu_refs}, pdu}
  end

  @spec handle_send_pdu_result(t, Pdu.t()) :: {t, :proceed | :skip}

  def handle_send_pdu_result(handler, pdu) do
    ref = Pdu.ref(pdu)
    case MapSet.member?(handler.my_pdu_refs, ref) do
      true ->
        new_my_pdu_refs = MapSet.delete(handler.my_pdu_refs, ref)
        {%AutoPduHandler{handler | my_pdu_refs: new_my_pdu_refs}, :skip}
      false ->
        {handler, :proceed}
    end
  end

  @spec handle_pdu(t, Pdu.t()) :: {t, :proceed} | {t, :skip, [Pdu.t()]}

  def handle_pdu(handler, pdu) do
    cond do
      Pdu.resp?(pdu) ->
        handle_resp(handler, pdu)

      Pdu.command_name(pdu) == :enquire_link ->
        handle_enquire_link(handler, pdu)

      true ->
        {handler, :proceed}
    end
  end

  @spec drop_expired(t) :: :ok

  def drop_expired(handler) do
    PduStorage.fetch_expired(handler.pdu_storage)
    :ok
  end

  defp handle_resp(handler, pdu) do
    case PduStorage.fetch(handler.pdu_storage, Pdu.sequence_number(pdu)) do
      {new_pdu_storage, [_pdu]} ->
        new_handler = %AutoPduHandler{handler | pdu_storage: new_pdu_storage}
        {new_handler, :skip}
      {new_pdu_storage, []} ->
        new_handler = %AutoPduHandler{handler | pdu_storage: new_pdu_storage}
        {new_handler, :proceed}
    end
  end

  defp handle_enquire_link(handler, pdu) do
    resp = PduFactory.enquire_link_resp() |> Pdu.as_reply_to(pdu)
    new_my_pdu_refs = MapSet.put(handler.my_pdu_refs, Pdu.ref(resp))
    {%AutoPduHandler{handler | my_pdu_refs: new_my_pdu_refs}, :skip, [resp]}
  end
end
