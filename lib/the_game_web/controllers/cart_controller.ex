defmodule TheGameWeb.CartController do
  use TheGameWeb, :controller
  alias TheGame.{Catalog, Orders, Phone}
  alias TheGameWeb.History

  def show(conn, _params), do: render_cart(conn, nil, "")

  @doc "Checkout. Validates everything on the server; the client's cart is only a request."
  def create(conn, params) do
    phone = to_string(params["phone"] || "")

    with {:ok, items} <- parse_items(params["items"]),
         {:ok, order} <-
           Orders.create_order(%{
             payer_phone: phone,
             items: items,
             expected_total_cents: parse_int(params["expected_total"])
           }) do
      conn
      |> History.add(order.id)
      |> put_session(:fresh_order, order.id)
      |> redirect(to: ~p"/order/#{order.id}?new=1")
    else
      {:error, :pending_order} -> pending_order(conn, phone)
      {:error, reason} -> conn |> put_status(422) |> render_cart(message(reason), phone)
    end
  end

  # The one-unpaid-order-per-phone rule. We only hand the visitor their own order back;
  # a stranger typing someone's number must not learn that order's id.
  defp pending_order(conn, phone) do
    with {:ok, norm} <- Phone.normalize(phone),
         %{id: id} <- Orders.unpaid_for_phone(norm),
         true <- History.member?(conn, id) do
      redirect(conn, to: ~p"/order/#{id}")
    else
      _ ->
        conn
        |> put_status(422)
        |> render_cart(
          "This number already has an unpaid order. Open it from Orders on this phone, or ask staff for help. Please don’t pay twice.",
          phone
        )
    end
  end

  defp render_cart(conn, error, phone) do
    conn
    |> assign(:page_js, "cart")
    |> render(:show,
      error: error,
      phone: phone,
      paused: TheGame.Settings.ordering_paused?(),
      page_title: "Your order — THE GAME"
    )
  end

  defp parse_items(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, list} when is_list(list) ->
        items =
          for %{"id" => id, "q" => q} <- list,
              is_binary(id),
              is_integer(q),
              do: %{product_id: id, qty: q}

        if length(items) == length(list), do: {:ok, items}, else: {:error, :unreadable}

      _ ->
        {:error, :unreadable}
    end
  end

  defp parse_items(_), do: {:error, :unreadable}

  defp parse_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_int(_), do: nil

  defp message(:ordering_paused),
    do:
      "Ordering is paused for a short stock count. Check back soon, and don’t pay at the till while it’s paused."

  defp message(:empty), do: "Your cart is empty."
  defp message(:invalid_phone), do: "Enter the M-Pesa number that will pay, like 0712 345 678."

  defp message(:too_many_units),
    do: "Orders can hold up to #{Orders.max_units()} drinks. Ask staff for a larger order."

  defp message(:invalid_quantity), do: "Check the quantities in your cart."
  defp message(:unreadable), do: "We couldn’t read your cart. Go back to the menu and try again."

  defp message({:unavailable, names}),
    do: "Sold out right now: #{Enum.join(names, ", ")}. Remove them to continue."

  defp message({:total_mismatch, total}),
    do:
      "Prices changed. The new total is #{Catalog.money(total)}. Check your order and pay again."

  defp message(_), do: "We couldn’t place your order. Please try again."
end
