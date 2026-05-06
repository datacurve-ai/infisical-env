# infisical-mise

A first-class [mise](https://mise.jdx.dev/) environment plugin that loads
[Infisical](https://infisical.com/) secrets into `mise env`.

The plugin uses the existing `.infisical.json` created by `infisical init`,
runs `infisical export --format=json`, and returns the exported secrets as mise
environment variables.

## Installation

Add the plugin to your project `mise.toml`:

```toml
[plugins]
infisical-env = "https://github.com/charley/infisical-mise"

[tools]
infisical = "latest"

[env]
_.infisical-env = { tools = true }
```

`tools = true` is needed when `infisical` is installed by mise, because plugin
hooks otherwise run before mise-managed tool paths are available.

## Infisical Setup

Initialize Infisical in the project:

```sh
infisical login
infisical init
```

This creates `.infisical.json`, which is safe to commit and is watched by the
plugin for cache invalidation.

Machine identity and service-token workflows are supported through the standard
Infisical CLI environment:

```sh
export INFISICAL_TOKEN="<token>"
mise env
```

## Configuration

All options are optional. If `env`, `path`, or `project_id` are omitted,
Infisical's CLI defaults and `.infisical.json` settings apply.

```toml
[env]
_.infisical-env = {
  tools = true,
  env = "dev",
  path = "/",
  domain = "https://app.infisical.com/api",
  tags = ["backend", "local"],
}
```

Supported options:

| Option | Description | Default |
| --- | --- | --- |
| `infisical_bin` | Path/name of the Infisical CLI binary | `infisical` |
| `config_file` | Explicit `.infisical.json` path | Search current directory and parents |
| `env` / `environment` | Infisical environment slug | CLI default / `.infisical.json` |
| `path` / `secret_path` | Infisical secret folder path | CLI default |
| `project_id` / `projectId` | Infisical project ID | `.infisical.json` |
| `domain` / `api_url` | Infisical API domain | CLI default / `INFISICAL_API_URL` |
| `tags` | Tag slug or list of tag slugs | All secrets |
| `expand` | Pass `--expand=<bool>` | CLI default |
| `include_imports` | Pass `--include-imports=<bool>` | CLI default |
| `secret_overriding` | Pass `--secret-overriding=<bool>` | CLI default |
| `cache` | Whether mise may cache plugin output | `true` |

The plugin intentionally does not accept a token option in `mise.toml`; use
Infisical's standard `INFISICAL_TOKEN` environment variable for machine identity
or service-token authentication.

## Caching

The hook returns cache metadata for mise's environment cache and watches
`.infisical.json`. Remote secret changes are refreshed according to mise's
`env_cache_ttl` when `env_cache` is enabled.

```toml
[settings]
env_cache = true
```

## Development

```sh
mise run fmt
mise run lint
```
