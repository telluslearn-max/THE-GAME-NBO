defmodule TheGameWeb.OrdersHTML do
  use TheGameWeb, :html
  embed_templates "orders_html/*"

  def status_tag(:pending_payment), do: {"Unpaid", "warn"}
  def status_tag(:paid), do: {"Paid", "ok"}
  def status_tag(:preparing), do: {"Preparing", "ok"}
  def status_tag(:ready), do: {"Ready", "go"}
  def status_tag(:completed), do: {"Collected", ""}
  def status_tag(:expired), do: {"Expired", ""}
  def status_tag(:cancelled), do: {"Cancelled", ""}
  def status_tag(:flagged), do: {"Checking", "warn"}
  def status_tag(:closed), do: {"Closed", ""}

  def when_eat(%DateTime{} = dt),
    do: dt |> DateTime.add(3 * 3600) |> Calendar.strftime("%d %b, %H:%M")

  def summary(order), do: Enum.map_join(order.items, ", ", &"#{&1.qty}× #{&1.name}")
end
