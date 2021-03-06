use Mix.Config

config :helix,
  ecto_repos: [
    Helix.Account.Repo,
    Helix.Cache.Repo,
    Helix.Client.Repo,
    Helix.Core.Repo,
    Helix.Entity.Repo,
    Helix.Log.Repo,
    Helix.Network.Repo,
    Helix.Universe.Repo,
    Helix.Process.Repo,
    Helix.Server.Repo,
    Helix.Software.Repo,
    Helix.Story.Repo
  ],
  env: Mix.env

default_key = "asdfghjklzxcvbnm,./';[]-=1234567890!"
config :helix, Helix.Endpoint,
  secret_key_base: System.get_env("HELIX_ENDPOINT_SECRET_KEY") || default_key,
  pubsub: [
    adapter: Phoenix.PubSub.PG2,
    size: 1,
    name: Helix.Endpoint.PubSub
  ]

config :helix, :migration_token, "defaultMigrationToken"

config :distillery, no_warn_missing: [:burette, :elixir_make]

import_config "#{Mix.env}.exs"
import_config "*/config.exs"
import_config "*/#{Mix.env}.exs"

config :timber, Timber.Integrations.EctoLogger,
  query_time_ms_threshold: 1_000
