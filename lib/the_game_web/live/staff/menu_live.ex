defmodule TheGameWeb.Staff.MenuLive do
  @moduledoc "Stock, prices and availability. Changes reach customers' menus immediately."
  use TheGameWeb, :live_view
  import TheGameWeb.StaffComponents
  alias TheGame.{Catalog, Payments}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Menu — THE GAME staff",
       q: "",
       error: nil,
       saved: nil,
       reviews: length(Payments.list_reviews())
     )
     |> load()}
  end

  defp load(socket) do
    assign(socket, products: Catalog.list_products(), categories: Catalog.list_categories())
  end

  @impl true
  def handle_event("filter", %{"q" => q}, socket), do: {:noreply, assign(socket, q: q)}

  def handle_event("save", %{"pid" => id} = p, socket) do
    attrs = %{
      "price_cents" => kes_to_cents(p["price"]),
      "stock" => blank_to_nil(p["stock"]),
      "active" => p["active"] == "true"
    }

    case Catalog.update_product(Catalog.get_product!(id), attrs) do
      {:ok, prod} -> {:noreply, socket |> assign(error: nil, saved: prod.id) |> load()}
      {:error, cs} -> {:noreply, assign(socket, error: first_error(cs), saved: nil)}
    end
  end

  def handle_event("create", %{"name" => name, "price" => price, "stock" => stock} = p, socket) do
    attrs = %{
      "name" => String.trim(name),
      "price_cents" => kes_to_cents(price),
      "stock" => blank_to_nil(stock)
    }

    with {:ok, cat_id} <- category_id(p),
         {:ok, prod} <- Catalog.create_product(attrs, cat_id) do
      {:noreply, socket |> assign(error: nil, saved: prod.id) |> load()}
    else
      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, error: first_error(cs))}

      {:error, :no_category} ->
        {:noreply, assign(socket, error: "Pick a category or type a new one.")}
    end
  end

  # An existing category, or a new one typed in the box (found by name if it already exists).
  defp category_id(%{"new_category" => new}) when is_binary(new) and new != "" do
    case Catalog.ensure_category(new) do
      {:ok, cat} -> {:ok, cat.id}
      _ -> {:error, :no_category}
    end
  end

  defp category_id(%{"category" => cat}) when is_binary(cat) and cat != "", do: {:ok, cat}
  defp category_id(_), do: {:error, :no_category}

  defp kes_to_cents(v) do
    case Integer.parse(to_string(v) |> String.replace(",", "") |> String.trim()) do
      {n, ""} -> n * 100
      _ -> nil
    end
  end

  defp blank_to_nil(v) do
    case String.trim(to_string(v)) do
      "" -> nil
      s -> s
    end
  end

  defp first_error(cs) do
    case cs.errors do
      [{field, {msg, _}} | _] -> "#{Phoenix.Naming.humanize(field)} #{msg}"
      _ -> "Couldn’t save."
    end
  end

  defp visible(products, ""), do: products

  defp visible(products, q),
    do: Enum.filter(products, &String.contains?(String.downcase(&1.name), String.downcase(q)))

  @impl true
  def render(assigns) do
    ~H"""
    <.header admin={@admin} active={:menu} paused={@paused} reviews={@reviews} />
    <main id="main" class="wrap swide">
      <h1 class="h1">Menu and stock</h1>
      <p :if={@error} class="notice" role="alert">{@error}</p>

      <details class="newp">
        <summary>Add a product</summary>
        <form phx-submit="create" class="pform">
          <input class="text" name="name" placeholder="Name" required />
          <input class="text" name="price" inputmode="numeric" placeholder="Price (KES)" required />
          <select class="text" name="category">
            <option value="">Category…</option>
            <option :for={c <- @categories} value={c.id}>{c.name}</option>
          </select>
          <input class="text" name="new_category" maxlength="40" placeholder="…or a new category" />
          <input
            class="text"
            name="stock"
            inputmode="numeric"
            placeholder="Stock (blank = not counted)"
          />
          <button class="sbtn go" type="submit">Add</button>
        </form>
      </details>

      <form phx-change="filter" class="sfind">
        <label class="sr" for="mq">Filter products</label>
        <input
          id="mq"
          class="text"
          name="q"
          value={@q}
          placeholder="Filter products"
          autocomplete="off"
          phx-debounce="100"
        />
      </form>

      <ul class="plist">
        <li
          :for={p <- visible(@products, @q)}
          id={"p-" <> p.id}
          class={[!p.active && "off", @saved == p.id && "saved"]}
        >
          <form phx-submit="save" class="prow">
            <input type="hidden" name="pid" value={p.id} />
            <span class="pname">{p.name}</span>
            <label class="pf">
              <span>KES</span>
              <input class="text" name="price" inputmode="numeric" value={div(p.price_cents, 100)} />
            </label>
            <label class="pf">
              <span>Stock</span>
              <input class="text" name="stock" inputmode="numeric" value={p.stock} placeholder="—" />
            </label>
            <label class="pc">
              <input type="checkbox" name="active" value="true" checked={p.active} /> On menu
            </label>
            <button class="sbtn" type="submit">Save</button>
          </form>
        </li>
      </ul>
    </main>
    """
  end
end
