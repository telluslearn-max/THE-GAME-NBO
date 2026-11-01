defmodule TheGame.Repo.Migrations.ReviewKinds do
  use Ecto.Migration

  # payment_reviews.kind / status are plain strings backed by Ecto.Enum in the schema;
  # nothing to alter, but make the intent explicit and enforce the allowed values.
  def change do
    create constraint(:payment_reviews, :kind_values,
             check: "kind in ('late','unmatched','extra','short')"
           )

    create constraint(:payment_reviews, :status_values,
             check: "status in ('pending','refunded','closed','honored')"
           )
  end
end
