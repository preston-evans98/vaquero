# Vaquero

The owner's apps and control service for the chief of staff system. `spec.md` describes the whole system; its "Owner apps" section covers this code.

| Path | What it is |
| --- | --- |
| `Sources/VaqueroKit` | Models and the API table, shared by the server and the apps |
| `Sources/VaqueroServer` | The control service (Hummingbird) |
| `Sources/VaqueroUI` | SwiftUI screens for both apps |
| `Apps/` | The entry points of the Mac app and the iPhone app, as an XcodeGen project |
| `Fixtures/demo` | Sample data for demo mode and tests |
| `deploy/` | The installer, the systemd units, the polkit rule, and the script that starts each agent |

## Develop

Xcode must be the active developer directory, or set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

```sh
swift test
swift run vaquero-server --demo Fixtures/demo     # serves a temporary copy on 127.0.0.1:8080
cd Apps && xcodegen && open Vaquero.xcodeproj     # run VaqueroMac or VaqueroiOS
shellcheck -s sh deploy/vaquero-agent deploy/install.sh
```

In demo mode the tokens are `demo` for the owner, `demo-agent` for agents and `demo-bot` for the Telegram bot. In the app, set the server to `http://127.0.0.1:8080` and the token to `demo`. You can also launch the app with `VAQUERO_URL` and `VAQUERO_TOKEN` in the environment.

## Deploy

The server needs Ubuntu 24.04 or later, because older polkit versions ignore the rule in `deploy/vaquero.rules`.

1. Install Swift, `jq`, `tmux`, `acl` and Tailscale. Sync Drive to a folder, `/srv/drive/vaquero` by default, so that the `vaquero-agent` user can write it.
2. In the checkout, run `swift build -c release --product vaquero-server`.
3. Run `sudo deploy/install.sh`. It creates the two users and the folders. It writes `/etc/vaquero/server.env` and `/etc/vaquero/agent.env` with fresh tokens, installs the binaries and units, and starts the service. To change the default folders, set `VAQUERO_ROOT` or `VAQUERO_DRIVE` first.
4. As `vaquero-agent`, install Claude Code and sign in once.
5. Run `sudo tailscale serve --bg --https=443 http://127.0.0.1:8080`. In the apps, enter the server's Tailscale address and `VAQUERO_TOKEN` from `server.env`. Give `VAQUERO_BOT_TOKEN` to the Telegram bot.

After an update, build again and rerun `install.sh`.

### The first agent

The chief of staff opens the leads, and the leads open project sessions, so only the chief of staff needs a file by hand. As root, write `/srv/vaquero/agents/chief-of-staff.json`, owned by `vaquero`:

```json
{
  "name": "chief-of-staff",
  "role": "chiefOfStaff",
  "model": "opus",
  "workdir": "/srv/vaquero/sessions/chief-of-staff",
  "statusFile": "cos/state.md"
}
```

Then restart the service, which starts every agent on file. `statusFile` is relative to the Drive folder.
