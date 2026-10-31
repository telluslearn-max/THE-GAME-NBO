defmodule TheGame.PhoneTest do
  use ExUnit.Case, async: true
  alias TheGame.Phone

  test "normalizes the common Kenyan formats" do
    for input <- [
          "0712345678",
          "712345678",
          "254712345678",
          "+254712345678",
          "0712 345 678",
          "+254 712-345-678"
        ] do
      assert Phone.normalize(input) == {:ok, "254712345678"}
    end

    assert Phone.normalize("0112345678") == {:ok, "254112345678"}
  end

  test "rejects junk" do
    for input <- ["", "12345", "0612345678", "+255712345678", "07123456789", nil, 7_123_456_78] do
      assert Phone.normalize(input) == :error
    end
  end

  test "last4" do
    assert Phone.last4("254712345678") == "5678"
  end
end
