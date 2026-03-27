# deploy-action

Deploys a repo to a server via SSH using Docker Compose.

## Usage

```yaml
- uses: robocy-lab/deploy-action@main
  with:
    host: lab.robocy.org
    ssh-user: lab-stuff
    ssh-key: ${{ secrets.SSH_KEY }}
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `host` | yes | — | Server hostname |
| `ssh-user` | no | `root` | SSH user |
| `ssh-key` | yes | — | SSH private key |
| `github-token` | no | `github.token` | Token for private repos |
| `cloudflare-tunnel` | no | `false` | Route SSH through Cloudflare tunnel |
| `directory` | no | `/var/apps/<repo>` | Deploy directory on server |
| `environment` | no | — | Environment suffix (e.g. `prod`) |
| `compose-file` | no | `docker-compose.yml` | Compose file name |
| `env-vars` | no | — | Newline-separated `KEY=VALUE` pairs written as `.env` on the server |

## Environment variables

Use `env-vars` to inject secrets into a `.env` file on the server before `docker compose up` runs. Docker Compose reads it automatically for variable substitution.

```yaml
- uses: robocy-lab/deploy-action@main
  with:
    host: ${{ secrets.HOST }}
    ssh-key: ${{ secrets.SSH_KEY }}
    env-vars: |
      DB_PASSWORD=${{ secrets.DB_PASSWORD }}
      API_KEY=${{ secrets.API_KEY }}
      APP_ENV=production
```

The `.env` file is overwritten on every deploy. Make sure it's in `.gitignore` on the deployed repo.

## Server setup

Add the public key to `~/.ssh/authorized_keys` on the server and make sure the deploy directory is writable by the SSH user. Docker-compose and docker should be installed on server

## Cloudflare tunnel

If the server is behind a Cloudflare tunnel, set `cloudflare-tunnel: 'true'`. `cloudflared` will be installed on the runner automatically.
