#!/bin/sh
# Sets up the control service and the agent units on an Ubuntu 24.04 (or later) server.
# Build first with `swift build -c release --product vaquero-server`, then run this as root
# from the checkout. Run it again after each update.
#
# Two users keep the agents away from the owner's controls:
# - vaquero runs the control service. Only it writes the agent list, the resolved queue and the config.
# - vaquero-agent runs every agent session, and holds only the agent token.
# Each user has a group of its own. Both also join vaquero-bus, which owns the folders they share:
# the bus, the pending queue, the logs, the heartbeats and the session folders.
set -eu
cd "$(dirname "$0")/.."

for tool in jq tmux flock setfacl systemctl pkaction; do
    command -v "$tool" >/dev/null || { echo "Install $tool first." >&2; exit 1; }
done
case $(pkaction --version) in
    *" 0.10"[0-5]*) echo "This polkit ignores JavaScript rules. Use Ubuntu 24.04 or later." >&2; exit 1 ;;
esac
[ -x .build/release/vaquero-server ] || { echo "Build the server first." >&2; exit 1; }

root=${VAQUERO_ROOT:-/srv/vaquero}
drive=${VAQUERO_DRIVE:-/srv/drive/vaquero}
[ -d "$drive" ] || echo "Warning: $drive does not exist yet. Sync Drive there, writable by vaquero-agent." >&2

getent group vaquero-bus >/dev/null || groupadd --system vaquero-bus
id vaquero >/dev/null 2>&1 || useradd --system --create-home --home-dir /var/lib/vaquero --user-group vaquero
id vaquero-agent >/dev/null 2>&1 || useradd --create-home --user-group vaquero-agent
usermod -aG vaquero-bus vaquero
usermod -aG vaquero-bus vaquero-agent
agent_home=$(getent passwd vaquero-agent | cut -d: -f6)

# Only the service writes these. Agents may read them.
install -d -o vaquero -g vaquero -m 755 "$root" "$root/agents" "$root/config" "$root/queue" "$root/queue/resolved"
# The chat lists name private chats, so only the service reads them.
install -d -o vaquero -g vaquero -m 700 "$root/private"
# The service and the agents both write these.
install -d -o vaquero -g vaquero-bus -m 2775 \
    "$root/bus" "$root/queue/pending" "$root/log" "$root/health" "$root/usage" "$root/sessions"

# The service reads the agents' transcripts and nothing else in their home folder.
install -d -o vaquero-agent -g vaquero-agent -m 700 "$agent_home/.claude" "$agent_home/.claude/projects"
setfacl -m u:vaquero:x "$agent_home" "$agent_home/.claude"
setfacl -R -m u:vaquero:rX -m d:u:vaquero:rX "$agent_home/.claude/projects"

# Each token is random. Only root reads these files; systemd hands each unit its own.
install -d -m 755 /etc/vaquero
if [ ! -e /etc/vaquero/server.env ]; then
    token() { head -c 32 /dev/urandom | base64 | tr -d '/+='; }
    owner_token=$(token)
    agent_token=$(token)
    bot_token=$(token)
    umask 077
    cat > /etc/vaquero/server.env <<ENV
VAQUERO_ROOT=$root
VAQUERO_DRIVE=$drive
VAQUERO_TRANSCRIPTS=$agent_home/.claude/projects
VAQUERO_TOKEN=$owner_token
VAQUERO_AGENT_TOKEN=$agent_token
VAQUERO_BOT_TOKEN=$bot_token
VAQUERO_PORT=8080
# VAQUERO_SEARCH_URL=http://127.0.0.1:8090/search
ENV
    cat > /etc/vaquero/agent.env <<ENV
VAQUERO_ROOT=$root
VAQUERO_DRIVE=$drive
VAQUERO_URL=http://127.0.0.1:8080
VAQUERO_AGENT_TOKEN=$agent_token
# VAQUERO_CLAUDE=$agent_home/.local/bin/claude
# VAQUERO_CLAUDE_ARGS=
ENV
    umask 022
    echo "The tokens are in /etc/vaquero/server.env: VAQUERO_TOKEN for the apps, VAQUERO_BOT_TOKEN for the Telegram bot."
fi

install -m 755 .build/release/vaquero-server /usr/local/bin/vaquero-server
install -m 755 deploy/vaquero-agent /usr/local/bin/vaquero-agent
install -m 644 deploy/vaquero-server.service deploy/vaquero-agent@.service /etc/systemd/system/
install -m 644 deploy/vaquero.rules /etc/polkit-1/rules.d/50-vaquero.rules
systemctl daemon-reload
systemctl enable vaquero-server
systemctl restart vaquero-server

echo "Next: install Claude Code as vaquero-agent and sign in once, then run"
echo "  tailscale serve --bg --https=443 http://127.0.0.1:8080"
