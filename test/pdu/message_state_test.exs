defmodule SMPPEX.Pdu.MessageStateTest do
  alias SMPPEX.Pdu.MessageState

  use ExUnit.Case

  doctest MessageState

  test "format" do
    assert_raise FunctionClauseError, fn ->
      MessageState.format(:not_an_integer)
    end
  end
end
