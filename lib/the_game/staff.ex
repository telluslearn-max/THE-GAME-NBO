defmodule TheGame.Staff do
  @moduledoc "Staff accounts and login. All staff share one role in v1."
  import Ecto.Query
  alias TheGame.Repo
  alias TheGame.Staff.{RateLimit, User}

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
