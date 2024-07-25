defmodule Phoneix.Repo do
  use Ecto.Repo,
    otp_app: :phoneix,
    adapter: Ecto.Adapters.Postgres
end
