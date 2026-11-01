defmodule TheGameWeb.BookingController do
  @moduledoc "Booking requests: reservations, large groups, events, collabs and VIP. No JS, no accounts."
  use TheGameWeb, :controller
  alias TheGame.Bookings

  @kinds %{
    "table" => :table,
    "group" => :group,
    "event" => :event,
    "collab" => :collab,
    "vip" => :vip
  }

  def index(conn, _params), do: render(conn, :index, page_title: "Book — THE GAME")

  def new(conn, %{"kind" => slug}) do
    with_kind(conn, slug, fn kind -> render_form(conn, kind, %{}, %{}) end)
  end

  def create(conn, %{"kind" => slug} = params) do
    with_kind(conn, slug, fn kind ->
      attrs = params["booking"] || %{}

      # The "website" field is invisible to people. A bot that fills it gets the same thanks
      # page and nothing is stored.
      if blank?(attrs["website"]) do
        case Bookings.create(kind, attrs) do
          {:ok, b} ->
            redirect(conn, to: ~p"/book/thanks/#{b.ref}")

          {:error, :too_many} ->
            conn
            |> put_status(429)
            |> render_form(
              kind,
              attrs,
              %{},
              "That’s a lot of requests from this number. Please call us instead."
            )

          {:error, %Ecto.Changeset{} = cs} ->
            conn |> put_status(422) |> render_form(kind, attrs, errors(cs))
        end
      else
        redirect(conn, to: ~p"/book/thanks/#{fake_ref()}")
      end
    end)
  end

  def thanks(conn, %{"ref" => ref}) do
    render(conn, :thanks,
      ref: ref,
      booking: Bookings.get_by_ref(ref),
      whatsapp: Application.get_env(:the_game, :venue_whatsapp),
      page_title: "Request received — THE GAME"
    )
  end

  defp render_form(conn, kind, values, errors, notice \\ nil) do
    render(conn, :form,
      kind: kind,
      v: values,
      errors: errors,
      notice: notice,
      today: Date.to_iso8601(Bookings.today()),
      page_title: "#{TheGameWeb.BookingHTML.title(kind)} — THE GAME"
    )
  end

  defp with_kind(conn, slug, fun) do
    case @kinds[slug] do
      nil ->
        conn |> put_status(404) |> put_view(html: TheGameWeb.ErrorHTML) |> render(:"404")

      kind ->
        fun.(kind)
    end
  end

  defp errors(cs) do
    cs
    |> Ecto.Changeset.traverse_errors(fn {msg, _} -> msg end)
    |> Map.new(fn {k, [msg | _]} -> {Atom.to_string(k), upcase_first(msg)} end)
  end

  defp upcase_first(<<c::utf8, rest::binary>>), do: String.upcase(<<c::utf8>>) <> rest

  defp blank?(v), do: v in [nil, ""]

  defp fake_ref,
    do: for(_ <- 1..6, into: "", do: <<Enum.random(~c"23456789ABCDEFGHJKMNPQRSTUVWXYZ")>>)
end
