defmodule TheGame.Staff.User do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  @type t :: %__MODULE__{}

  schema "staff_users" do
    field :role, Ecto.Enum, values: [:staff, :admin], default: :staff
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :password_hash, :string, redact: true
    field :active, :boolean, default: true
    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :password, :role])
    |> update_change(:email, &(&1 |> String.trim() |> String.downcase()))
    |> validate_required([:email, :password])
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/)
    |> validate_length(:password, min: 8, max: 72)
    |> unique_constraint(:email)
    |> hash()
  end

  defp hash(%{valid?: true, changes: %{password: pw}} = cs) do
    cs |> put_change(:password_hash, Pbkdf2.hash_pwd_salt(pw)) |> delete_change(:password)
  end

  defp hash(cs), do: cs
end

defmodule TheGame.Staff.PasswordChange do
  @moduledoc false
  import Ecto.Changeset

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_length(:password, min: 8, max: 72)
    |> then(fn
      %{valid?: true, changes: %{password: pw}} = cs ->
        cs |> put_change(:password_hash, Pbkdf2.hash_pwd_salt(pw)) |> delete_change(:password)

      cs ->
        cs
    end)
  end
end
