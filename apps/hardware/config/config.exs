use Mix.Config

config :hardware,
  ecto_repos: [Helix.Hardware.Repo]
config :hardware, Helix.Hardware.Repo,
  size: 4,
  adapter: Ecto.Adapters.Postgres,
  database: "hardware_service",
  username: System.get_env("HELIX_DB_USER") || "postgres",
  password: System.get_env("HELIX_DB_PASS") || "postgres",
  hostname: System.get_env("HELIX_DB_HOST") || "localhost",
  extensions: [
    {Postgrex.Extensions.Network, nil}
  ]

import_config "#{Mix.env}.exs"