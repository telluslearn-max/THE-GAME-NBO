defmodule TheGame.Phone do
  @moduledoc "Kenyan mobile number handling. Canonical form is `2547XXXXXXXX` / `2541XXXXXXXX`."

  @re ~r/^(?:0|\+?254)?([17]\d{8})$/

  @spec normalize(term) :: {:ok, String.t()} | :error
  def normalize(input) when is_binary(input) do
    cleaned = String.replace(input, ~r/[\s\-()]/, "")

    case Regex.run(@re, cleaned) do
      [_, rest] -> {:ok, "254" <> rest}
      _ -> :error
    end
  end

  def normalize(_), do: :error

  @spec last4(String.t()) :: String.t()
  def last4(phone), do: String.slice(phone, -4, 4)
end
