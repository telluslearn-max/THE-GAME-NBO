defmodule TheGame.Staff do
  @moduledoc "Staff accounts and login. All staff share one role in v1."
  import Ecto.Query
  alias TheGame.Repo
  alias TheGame.Staff.{RateLimit, User}

  def list_users, do: Repo.all(from u in User, order_by: [asc: u.role, asc: u.email])

  def create_user(attrs), do: %User{} |> User.changeset(attrs) |> Repo.insert()
  @doc "Set the password of the account with this email (used by the env-driven reset on deploy)."
  def set_password(email, password) do
    email = email |> String.trim() |> String.downcase()

    case Repo.get_by(User, email: email) do
      nil ->
        {:error, :not_found}

      user ->
        user |> TheGame.Staff.PasswordChange.changeset(%{password: password}) |> Repo.update()
    end
  end

  @doc "Who may see what. Waiters: the board. Floor staff: the board, payments, menu, today. Managers: everything."
  def allowed?(%User{role: :admin}, _area), do: true
  def allowed?(%User{role: :staff}, area), do: area in [:board, :floor]
  def allowed?(%User{role: :waiter}, area), do: area == :board
  def allowed?(_, _), do: false

  def role_label(:admin), do: "Manager"
  def role_label(:staff), do: "Floor staff"
  def role_label(:waiter), do: "Waiter"

  @doc "Change someone's role. The last active manager can't be demoted (everyone would be locked out of Team)."
  def update_role(id, role) when role in [:admin, :staff, :waiter] do
    user = Repo.get!(User, id)

    if user.role == :admin and role != :admin and last_active_admin?(user) do
      {:error, :last_admin}
    else
      user |> Ecto.Changeset.change(role: role) |> Repo.update()
    end
  end

  @doc "Switch an account on or off. The last active manager can't be switched off."
  def set_active(id, active?) do
    user = Repo.get!(User, id)

    if not active? and user.role == :admin and last_active_admin?(user) do
      {:error, :last_admin}
    else
      user |> Ecto.Changeset.change(active: active?) |> Repo.update()
    end
  end

  def reset_password(id, password) do
    Repo.get!(User, id)
    |> TheGame.Staff.PasswordChange.changeset(%{password: password})
    |> Repo.update()
  end

  defp last_active_admin?(%User{id: id}) do
    Repo.aggregate(
      from(u in User, where: u.role == :admin and u.active == true and u.id != ^id),
      :count
    ) == 0
  end

  def admin?(%User{role: :admin}), do: true
  def admin?(_), do: false

  def get_user(id), do: Repo.get_by(User, id: id, active: true)

  @doc """
  Verify credentials. Rate limited per email and per client key, and unknown emails still
  pay for a password hash so response time does not reveal which emails exist.
  """
  @spec authenticate(String.t(), String.t(), String.t()) ::
          {:ok, User.t()} | {:error, :invalid | :rate_limited}
  def authenticate(email, password, client \\ "-")
      when is_binary(email) and is_binary(password) do
    email = email |> String.trim() |> String.downcase()
    key = {email, client}

    if RateLimit.blocked?(key) do
      {:error, :rate_limited}
    else
      user = Repo.one(from u in User, where: u.email == ^email and u.active == true)

      cond do
        user && Pbkdf2.verify_pass(password, user.password_hash) ->
          RateLimit.clear(key)
          {:ok, user}

        true ->
          unless user, do: Pbkdf2.no_user_verify()
          RateLimit.hit(key)
          {:error, :invalid}
      end
    end
  end
end
