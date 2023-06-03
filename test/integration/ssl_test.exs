defmodule SMPPEX.Integration.SSLTest do
  use ExUnit.Case

  @moduletag :ssl

  alias Support.SSL.MC
  alias Support.SSL.ESME
  alias Support.TCP.Helpers
  alias SMPPEX.Pdu

  test "pdu exchange" do
    port = Helpers.find_free_port()
    start_supervised!({MC, {port, "good.rubybox.dev"}})

    {:ok, _pid} = ESME.start_link(port, "good.rubybox.dev")

    receive do
      {bind_resp, bind} ->
        assert :bind_transceiver_resp == Pdu.command_name(bind_resp)
        assert :bind_transceiver == Pdu.command_name(bind)
    after
      1000 ->
        assert false
    end
  end

  test "ssl handshake fail" do
    otp_release = :erlang.system_info(:otp_release)

    case :string.to_integer(otp_release) do
      {n, ''} when n >= 20 ->
        port = Helpers.find_free_port()
        start_supervised!({MC, {port, "bad.rubybox.dev"}})
        {:error, {:tls_alert, _}} = ESME.start_link(port, "good.rubybox.dev")

      _ ->
        assert true
    end
  end
end
