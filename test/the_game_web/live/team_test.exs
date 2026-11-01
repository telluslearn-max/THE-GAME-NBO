defmodule TheGameWeb.TeamTest do
  use TheGameWeb.ConnCase
  import Phoenix.LiveViewTest
  import TheGame.Fixtures
  alias TheGame.{Settings, Staff}

  @pw "correct horse battery"

  defp user!(role, attrs \\ %{}) do
    {:ok, u} =
      Staff.create_user(
        Map.merge(
          %{
            email: "#{role}#{System.unique_integer([:positive])}@bar.test",
            password: @pw,
            role: role,
            name: "#{role}"
          },
          attrs
        )
      )

    u
  end

  defp as(conn, u), do: init_test_session(conn, %{"staff_id" => u.id})

  # live/2 on a page the role may not open ends in a redirect to the board
  defp bounced?(conn, path) do
    match?(
      {:error, {kind, %{to: "/staff"}}} when kind in [:redirect, :live_redirect],
      live(conn, path)
    )
  end

  describe "what each role can open" do
    test "waiter: the board only; floor staff: the floor pages; manager: everything", %{
      conn: conn
    } do
      w = user!(:waiter)
      f = user!(:staff)
      m = user!(:admin)

      for {path, who_may} <- [
            {"/staff", [w, f, m]},
            {"/staff/menu", [f, m]},
            {"/staff/reviews", [f, m]},
            {"/staff/today", [f, m]},
            {"/staff/insights", [m]},
            {"/staff/team", [m]}
          ],
          user <- [w, f, m] do
        if user in who_may do
          assert {:ok, _, _} = live(as(build_conn(), user), path),
                 "#{user.role} should open #{path}"
        else
          assert bounced?(as(build_conn(), user), path), "#{user.role} must not open #{path}"
        end
      end
    end

    test "the header only offers what the role may open", %{conn: _} do
      links = fn user ->
        {:ok, _, html} = live(as(build_conn(), user), "/staff")

        for href <- ~w(/staff/reviews /staff/menu /staff/today /staff/insights /staff/team),
            into: %{},
            do: {href, html =~ ~s(href="#{href}")}
      end

      assert links.(user!(:waiter)) |> Map.values() |> Enum.all?(&(&1 == false))
      f = links.(user!(:staff))
      assert f["/staff/menu"] and f["/staff/reviews"] and f["/staff/today"]
      refute f["/staff/insights"] or f["/staff/team"]
      assert links.(user!(:admin)) |> Map.values() |> Enum.all?(& &1)
    end

    test "waiters cannot pause ordering, even with a forged request", %{conn: conn} do
      {:ok, view, html} = live(as(conn, user!(:waiter)), "/staff")
      refute html =~ "Taking orders"
      render_hook(view, "toggle_pause", %{})
      refute Settings.ordering_paused?()

      {:ok, fview, fhtml} = live(as(build_conn(), user!(:staff)), "/staff")
      assert fhtml =~ "Taking orders"
      fview |> element("button.switch") |> render_click()
      assert Settings.ordering_paused?()
    end

    test "after signing in: managers land on Insights, everyone else on the board", %{conn: conn} do
      m = user!(:admin)

      for r <- [:staff, :waiter] do
        u = user!(r)

        assert redirected_to(
                 post(build_conn(), "/staff/login", %{"email" => u.email, "password" => @pw})
               ) == "/staff"
      end

      assert redirected_to(post(conn, "/staff/login", %{"email" => m.email, "password" => @pw})) ==
               "/staff/insights"
    end

    test "a waiter still works the board: sees unpaid orders, can claim and deliver", %{
      conn: conn
    } do
      gin = product(%{name: "Gin"})

      {:ok, o} =
        TheGame.Orders.create_order(order_attrs([{gin, 1}], %{payer_phone: unique_phone()}))

      {:ok, view, html} = live(as(conn, user!(:waiter)), "/staff")
      assert html =~ o.pickup_code

      render_hook(view, "set_waiter", %{"waiter" => "Amina"})

      view
      |> form("#o-#{o.id} form.claimform", %{"last4" => "K932", "time" => "16:52"})
      |> render_submit()

      view |> element(~s(#o-#{o.id} button), "Confirmed at counter") |> render_click()
      assert TheGame.Orders.get_order!(o.id).status == :paid
    end
  end

  describe "Team page" do
    setup %{conn: conn} do
      m = user!(:admin, %{name: "Manager Mary"})
      {:ok, conn: as(conn, m), m: m}
    end

    test "lists everyone and explains the roles", %{conn: conn, m: m} do
      user!(:waiter, %{name: "Amina", email: "amina@bar.test"})
      {:ok, _view, html} = live(conn, "/staff/team")
      assert html =~ "Manager Mary"
      assert html =~ "amina@bar.test"
      assert html =~ "Floor staff"
      assert html =~ "The board only"
      assert html =~ m.email
    end

    test "add a person with a role; they can sign in with it", %{conn: conn} do
      {:ok, view, _} = live(conn, "/staff/team")

      html =
        view
        |> form("form[phx-submit=add]", %{
          "name" => "Brian",
          "email" => "Brian@Bar.test",
          "role" => "waiter",
          "password" => "Game1234"
        })
        |> render_submit()

      assert html =~ "brian@bar.test added as Waiter."

      assert {:ok, %{role: :waiter, name: "Brian"}} =
               Staff.authenticate("brian@bar.test", "Game1234")
    end

    test "bad input is explained and nothing is created", %{conn: conn} do
      {:ok, view, _} = live(conn, "/staff/team")
      before = length(Staff.list_users())

      html =
        view
        |> form("form[phx-submit=add]", %{
          "name" => "X",
          "email" => "nope",
          "role" => "staff",
          "password" => "short"
        })
        |> render_submit()

      assert html =~ "Email" or html =~ "Password"
      assert length(Staff.list_users()) == before
    end

    test "change a role", %{conn: conn} do
      w = user!(:waiter, %{email: "w@bar.test"})
      {:ok, view, _} = live(conn, "/staff/team")

      html =
        view |> form("#u-#{w.id} form[phx-change=role]", %{"role" => "staff"}) |> render_change()

      assert html =~ "w@bar.test is now Floor staff."
      assert Staff.get_user(w.id).role == :staff
    end

    test "switch an account off and on; a switched-off person can't sign in", %{conn: conn} do
      w = user!(:waiter, %{email: "off@bar.test"})
      {:ok, view, _} = live(conn, "/staff/team")
      view |> element("#u-#{w.id} button", "Switch off") |> render_click()
      assert {:error, :invalid} = Staff.authenticate("off@bar.test", @pw)
      assert redirected_to(get(as(build_conn(), w), "/staff")) == "/staff/login"
      view |> element("#u-#{w.id} button", "Switch on") |> render_click()
      assert {:ok, _} = Staff.authenticate("off@bar.test", @pw)
    end

    test "reset a password: the new one works, the old one doesn't", %{conn: conn} do
      w = user!(:waiter, %{email: "pw@bar.test"})
      {:ok, view, _} = live(conn, "/staff/team")

      html =
        view
        |> form("#u-#{w.id} form[phx-submit=reset]", %{"password" => "Fresh1234"})
        |> render_submit()

      assert html =~ "New password set for pw@bar.test."
      assert {:ok, _} = Staff.authenticate("pw@bar.test", "Fresh1234", "a")
      assert {:error, :invalid} = Staff.authenticate("pw@bar.test", @pw, "b")

      html =
        view |> form("#u-#{w.id} form[phx-submit=reset]", %{"password" => "x"}) |> render_submit()

      assert html =~ "Password"
    end

    test "you can't switch yourself off, and there is always one active manager", %{
      conn: conn,
      m: m
    } do
      {:ok, view, html} = live(conn, "/staff/team")
      refute html =~ ~s(phx-value-uid="#{m.id}")

      assert render_hook(view, "active", %{"uid" => m.id, "to" => "off"}) =~
               "can’t switch off your own account"

      assert Staff.get_user(m.id).active

      # demoting the only manager is refused
      html =
        view |> form("#u-#{m.id} form[phx-change=role]", %{"role" => "waiter"}) |> render_change()

      assert html =~ "There must always be one active manager."
      assert Staff.get_user(m.id).role == :admin
    end

    test "with two managers, one may be demoted or switched off", %{conn: conn, m: m} do
      other = user!(:admin, %{email: "second@bar.test"})
      {:ok, view, _} = live(conn, "/staff/team")
      view |> element("#u-#{other.id} button", "Switch off") |> render_click()
      refute Staff.get_user(other.id)
      # now the original is the last one again
      assert {:error, :last_admin} = Staff.update_role(m.id, :staff)
    end

    test "forged ids and roles do nothing", %{conn: conn} do
      {:ok, view, _} = live(conn, "/staff/team")
      assert render_hook(view, "role", %{"uid" => "not-a-uuid", "role" => "admin"}) =~ "Couldn’t"

      assert render_hook(view, "role", %{"uid" => Ecto.UUID.generate(), "role" => "admin"}) =~
               "Couldn’t"

      w = user!(:waiter)
      assert render_hook(view, "role", %{"uid" => w.id, "role" => "superuser"}) =~ "Couldn’t"
      assert Staff.get_user(w.id).role == :waiter
    end
  end
end
