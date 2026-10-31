defmodule TheGame.Repo.Migrations.CreateCore do
  use Ecto.Migration

  def change do
    create table(:categories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :position, :integer, null: false, default: 0
      timestamps(type: :utc_datetime)
    end

    create unique_index(:categories, [:slug])

    create table(:products, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :price_cents, :integer, null: false
      add :active, :boolean, null: false, default: true
      # nil = stock is not tracked (always available while active)
      add :stock, :integer
      timestamps(type: :utc_datetime)
    end

    create constraint(:products, :price_positive, check: "price_cents > 0")
    create constraint(:products, :stock_non_negative, check: "stock is null or stock >= 0")

    create table(:product_categories, primary_key: false) do
      add :category_id, references(:categories, type: :binary_id, on_delete: :delete_all),
        null: false

      add :product_id, references(:products, type: :binary_id, on_delete: :delete_all),
        null: false

      add :position, :integer, null: false, default: 0
    end

    create unique_index(:product_categories, [:category_id, :product_id])
    create index(:product_categories, [:product_id])

    create table(:orders, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :status, :string, null: false, default: "pending_payment"
      add :phone, :string, null: false
      add :payer_phone, :string, null: false
      add :total_cents, :integer, null: false
      add :pickup_code, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :mpesa_receipt, :string
      add :paid_at, :utc_datetime
      add :ready_at, :utc_datetime
      add :completed_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    # One unpaid order per payer phone (money-safety rule from the study).
    create unique_index(:orders, [:payer_phone],
             where: "status = 'pending_payment'",
             name: :orders_one_unpaid_per_phone
           )

    # Pickup codes must be unique among live orders so the bar can't confuse two.
    create unique_index(:orders, [:pickup_code],
             where: "status in ('pending_payment','paid','preparing','ready','flagged')",
             name: :orders_live_pickup_code
           )

    create index(:orders, [:status, :inserted_at])
    create index(:orders, [:expires_at], where: "status = 'pending_payment'")

    create table(:order_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :order_id, references(:orders, type: :binary_id, on_delete: :delete_all), null: false
      add :product_id, references(:products, type: :binary_id, on_delete: :nilify_all)
      add :name, :string, null: false
      add :unit_price_cents, :integer, null: false
      add :qty, :integer, null: false
    end

    create index(:order_items, [:order_id])
    create constraint(:order_items, :qty_range, check: "qty between 1 and 15")

    create table(:payments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :order_id, references(:orders, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "queued"
      add :phone, :string, null: false
      add :amount_cents, :integer, null: false
      add :checkout_request_id, :string
      add :merchant_request_id, :string
      add :result_code, :integer
      add :result_desc, :string
      add :mpesa_receipt, :string
      add :sent_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:payments, [:checkout_request_id],
             where: "checkout_request_id is not null"
           )

    create index(:payments, [:order_id])
    create unique_index(:payments, [:mpesa_receipt], where: "mpesa_receipt is not null")

    create table(:payment_reviews, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :order_id, references(:orders, type: :binary_id, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :mpesa_receipt, :string, null: false
      add :phone, :string
      add :amount_cents, :integer, null: false
      add :note, :text
      timestamps(type: :utc_datetime)
    end

    create unique_index(:payment_reviews, [:mpesa_receipt])
    create index(:payment_reviews, [:status])

    create table(:push_subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :order_id, references(:orders, type: :binary_id, on_delete: :delete_all), null: false
      add :endpoint, :text, null: false
      add :p256dh, :text, null: false
      add :auth, :text, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:push_subscriptions, [:order_id, :endpoint])

    create table(:settings, primary_key: false) do
      add :key, :string, primary_key: true
      add :value, :string, null: false
    end
  end
end
