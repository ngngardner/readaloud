defmodule ReadaloudLibrary.Repo.Migrations.AddLastObservedAtToReadingProgress do
  use Ecto.Migration

  # `last_observed_at` is the wall-clock at the moment the *client* observed
  # the position (not when the server wrote it). Stale-drop semantics in
  # ReadaloudReader.observe!/1 compare against this column so out-of-order
  # arrivals — common when the JS-side progress buffer flushes a backlog on
  # WebSocket reconnect or via sendBeacon at lock-screen time — never roll
  # state backwards.
  def change do
    alter table(:reading_progress) do
      add(:last_observed_at, :utc_datetime)
    end
  end
end
