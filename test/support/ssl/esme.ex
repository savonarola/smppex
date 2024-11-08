defmodule Support.SSL.ESME do
  @moduledoc false

  use SMPPEX.Session

  @host "localhost"

  @system_id "system_id"
  @password "password"

  def start_link(port, hostname, delay \\ nil) do
    SMPPEX.ESME.start_link(
      @host,
      port,
      {__MODULE__, %{pid: self(), delay: delay}},
      transport: :ranch_ssl,
      socket_opts: [
        cacertfile: String.to_charlist("test/support/ssl/ca.crt"),
        server_name_indication: String.to_charlist(hostname),
        verify: :verify_peer
      ]
    )
  end

  @impl SMPPEX.Session
  def init(_socket, _transport, st) do
    if st.delay do
      st.delay.()
    end

    send(self(), :bind)
    {:ok, st}
  end

  @impl SMPPEX.Session
  def handle_info(:bind, st) do
    pdu = SMPPEX.Pdu.Factory.bind_transceiver(@system_id, @password)
    {:noreply, [pdu], st}
  end

  @impl SMPPEX.Session
  def handle_resp(resp, original_pdu, st) do
    send(st.pid, {resp, original_pdu})
    {:stop, :normal, st}
  end
end
