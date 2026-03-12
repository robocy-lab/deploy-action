#!/usr/bin/env bash
set -euo pipefail

log() { echo "[INFO] $1"; }
err() { echo "[ERROR] $1" >&2; }

deploy_to_server() {
    local ssh_host="$1"
    local ssh_user="$2"
    local ssh_key="$3"
    local repo_url="$4"
    local repo_name="$5"
    local branch="${6:-main}"
    local deploy_dir="${7:-/var/apps/${repo_name}}"
    local environment="${8:-}"
    local compose_file="${9:-docker-compose.yml}"

    local project_name="${repo_name}"
    [[ -n "$environment" ]] && project_name="${repo_name}-${environment}"

    local ssh_key_file
    ssh_key_file=$(mktemp)
    chmod 600 "$ssh_key_file"
    echo "$ssh_key" > "$ssh_key_file"

    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30 -i $ssh_key_file"

    if [[ "${CLOUDFLARE_TUNNEL:-false}" == "true" ]]; then
        if ! command -v cloudflared &> /dev/null; then
            log "Installing cloudflared..."
            curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
                -o /usr/local/bin/cloudflared
            chmod +x /usr/local/bin/cloudflared
        fi
        local ssh_config_file
        ssh_config_file=$(mktemp)
        cat > "$ssh_config_file" << SSHCONF
Host ${ssh_host}
    ProxyCommand cloudflared access ssh --hostname %h
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    ConnectTimeout 30
    IdentityFile ${ssh_key_file}
SSHCONF
        ssh_opts="-F $ssh_config_file"
    fi

    ssh $ssh_opts "${ssh_user}@${ssh_host}" /bin/bash << EOF
set -euo pipefail

REPO_URL="$repo_url"
BRANCH="$branch"
DEPLOY_DIR="$deploy_dir"
PROJECT_NAME="$project_name"
COMPOSE_FILE="$compose_file"

mkdir -p "\$(dirname "\$DEPLOY_DIR")"

if [ -d "\$DEPLOY_DIR" ]; then
    cd "\$DEPLOY_DIR"
    git fetch origin
    git reset --hard "origin/\${BRANCH}"
    git clean -fd
else
    git clone --depth 1 --single-branch --branch "\${BRANCH}" "\$REPO_URL" "\$DEPLOY_DIR"
    cd "\$DEPLOY_DIR"
fi

[[ ! -f "\$COMPOSE_FILE" ]] && { echo "[ERROR] \$COMPOSE_FILE not found"; exit 1; }

if command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
elif docker compose version &> /dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
else
    echo "[ERROR] docker compose not found"
    exit 1
fi

\$COMPOSE_CMD -p "\${PROJECT_NAME}" -f "\$COMPOSE_FILE" down 2>/dev/null || true
\$COMPOSE_CMD -p "\${PROJECT_NAME}" -f "\$COMPOSE_FILE" up -d --build

sleep 3

if \$COMPOSE_CMD -p "\${PROJECT_NAME}" -f "\$COMPOSE_FILE" ps | grep -q "Up"; then
    docker image prune -f --filter "until=24h"
else
    \$COMPOSE_CMD -p "\${PROJECT_NAME}" -f "\$COMPOSE_FILE" logs --tail=50
    exit 1
fi
EOF

    local exit_code=$?
    rm -f "$ssh_key_file"
    [[ $exit_code -ne 0 ]] && { err "Deployment failed (exit $exit_code)"; return $exit_code; }
    log "Done"
}

SSH_HOST="${HOST:-}"
SSH_USER="${SSH_USER:-root}"
SSH_KEY="${SSH_KEY:-}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
GITHUB_REF="${GITHUB_REF:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
DEPLOY_DIRECTORY="${DEPLOY_DIRECTORY:-}"
DEPLOY_ENVIRONMENT="${DEPLOY_ENVIRONMENT:-}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
DEPLOY_BRANCH="${DEPLOY_BRANCH:-}"

[[ -z "$SSH_HOST" ]]          && { err "HOST is required"; exit 1; }
[[ -z "$SSH_KEY" ]]           && { err "SSH_KEY is required"; exit 1; }
[[ -z "$GITHUB_REPOSITORY" ]] && { err "GITHUB_REPOSITORY is required"; exit 1; }

BRANCH_NAME="$DEPLOY_BRANCH"
if [[ -z "$BRANCH_NAME" ]]; then
    if [[ "$GITHUB_REF" =~ refs/heads/(.*) ]]; then
        BRANCH_NAME="${BASH_REMATCH[1]}"
    elif [[ "$GITHUB_REF" =~ refs/tags/(.*) ]]; then
        BRANCH_NAME="${BASH_REMATCH[1]}"
    else
        BRANCH_NAME="main"
    fi
fi

REPO_NAME=$(basename "$GITHUB_REPOSITORY")
REPO_URL="https://github.com/${GITHUB_REPOSITORY}.git"
[[ -n "$GITHUB_TOKEN" ]] && REPO_URL="https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"

deploy_to_server "$SSH_HOST" "$SSH_USER" "$SSH_KEY" "$REPO_URL" "$REPO_NAME" "$BRANCH_NAME" "$DEPLOY_DIRECTORY" "$DEPLOY_ENVIRONMENT" "$COMPOSE_FILE"