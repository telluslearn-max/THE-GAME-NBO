defmodule TheGameWeb.OrderHTML do
  use TheGameWeb, :html
  embed_templates "order_html/*"

  def status_text(:pending_payment), do: "Waiting for payment"
  def status_text(:paid), do: "Paid. The bar has your order"
  def status_text(:preparing), do: "Being prepared"
  def status_text(:ready), do: "Ready. Collect at the bar"
  def status_text(:completed), do: "Collected"
  def status_text(:expired), do: "Expired"
  def status_text(:cancelled), do: "Cancelled"
  def status_text(:flagged), do: "Needs staff attention"
  def status_text(:closed), do: "Closed"
end
