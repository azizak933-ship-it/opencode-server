# OpenCode on a server

Turns a Linux box you leave running into your OpenCode host: the agent, its
sessions, its credentials and its files all live there, and none of them live on
your laptop or phone. You drive it from any device, and it keeps working while
your device is off.

## What you need

- A Linux host that stays on (VPS, home server, spare machine) with systemd.
- Root or sudo access over SSH.
- A model provider account (or an OpenCode Console subscription).

No domain is required. No ports need to be opened to the internet either — the
default setup reaches the server through OpenTunnel.

## Free option: GitHub Codespaces (no card needed)

If you have no host and no money, a codespace works and costs nothing. GitHub
Free personal accounts include 120 core-hours and 15 GB per month, and you can
start without a payment method on file.

1. Open this repository on GitHub and click **Code → Codespaces → Create
   codespace on main** (or go to `https://codespaces.new/<owner>/<repo>`).
2. Wait for the container to build. `.devcontainer/setup.sh` installs OpenCode,
   writes the config, generates a password and starts the server. The password
   is printed in the terminal and kept at `~/.opencode-server-password`.
3. In the **Ports** tab, open port `49374` in a browser, then sign in with
   username `opencode` and that password.

On every start, `postStartCommand` runs the same script, so the server comes
back when the codespace wakes up.

Limits, stated plainly:

- 120 core-hours a month is 60 hours on a 2-core codespace, so this cannot run
  24/7. It is "on while you are using it".
- A codespace stops itself after an idle timeout; start it again from
  `github.com/codespaces` on any device, phone included.
- There is no systemd in a codespace, so the unit files here do not apply.
  The server runs through OpenCode's own background service instead — which is
  also what makes `opencode pair` work.

## Install

From your workstation, with SSH access to the host:

```bash
bash deploy.sh root@your-server            # install
bash deploy.sh root@your-server --remote   # install and enable access from anywhere
```

Or copy this directory to the server and run it there:

```bash
scp -r opencode-server root@your-server:/tmp/
ssh root@your-server
sudo bash /tmp/opencode-server/install.sh
```

`install.sh` options: `--remote`, `--bind ADDR`, `--port N`, `--projects DIR`.

## What it sets up

| Thing | Where |
| --- | --- |
| OpenCode binary | `/usr/local/bin/opencode` (real path under `/home/opencode/.opencode/bin`) |
| Service user | `opencode` — unprivileged, because the agent runs shell commands with this user's authority |
| systemd unit | `opencode.service` — starts the shared server at boot, stops it cleanly |
| Optional self-heal timer | `opencode-ensure.timer` — restarts the server within 5 minutes if it dies |
| Server config | `/home/opencode/.config/opencode/opencode.jsonc` |
| Provider credentials | `/etc/opencode/env` (or `/connect`, see below) |
| Server password | `/etc/opencode/server.env`, mode 0600 |
| Projects | `/srv/projects` |
| Sessions + logs | `/home/opencode/.local/share/opencode/` |

It is idempotent: configs you have edited are left alone, and re-running it
after an upgrade re-links the binary.

## Connect your devices

Run these **on the server** as the `opencode` user:

```bash
su - opencode -c 'opencode pair'            # same network or SSH-tunnelled
su - opencode -c 'opencode pair --remote'   # from anywhere, over OpenTunnel
```

Both print a link and a QR code. Pair links are one-time and expire in five
minutes; each device you pair stays signed in for 30 days.

| Device | How |
| --- | --- |
| Any browser | Open the printed link — the web UI is served by the server itself |
| Phone or tablet | OpenCode app: scan the QR code, or paste the link |
| Desktop app | Paste the link into its server address field |
| Terminal on any machine | `opencode --server http://your-server:49374` |

Every device sees the same sessions, so you can start something on your phone
and pick it up on your laptop later.

### First-run credential

Pair one device, then run `/connect` in it to add a provider, and `/models` to
pick a default. Credentials entered this way are stored **on the server**. If
you would rather have credentials in place before any client connects (useful
for unattended work), put them in `/etc/opencode/env` and
`systemctl restart opencode`.

### SSH tunnel instead of OpenTunnel

If the server listens only on loopback (the default) and you would rather not
use OpenTunnel:

```bash
ssh -L 49374:127.0.0.1:49374 your-server
# then open the link from `opencode pair` in your local browser
```

## Getting your code on the server

Sessions run against directories **on the server**, so clone your repositories
into `/srv/projects` (or wherever `--projects` points):

```bash
sudo -u opencode git clone git@github.com:you/repo.git /srv/projects/repo
```

`opencode.jsonc` allows `external_directory` inside that directory, so the agent
can work there unattended without waiting for an approval prompt.

## Operating it

```bash
systemctl status opencode            # is it up?
systemctl restart opencode           # restart (also activates an update)
journalctl -u opencode -f            # unit output
sudo bash verify.sh                  # health check: unit, API, service, log tail
tail -f /home/opencode/.local/share/opencode/log/opencode.log
```

- **Rotate the password:** `su - opencode -c 'opencode service set password "new-secret"'`
  then `systemctl restart opencode`. This signs every paired device out.
- **Turn remote access off:** `su - opencode -c 'opencode service set remote false'`
- **Self-healing:** `systemctl enable --now opencode-ensure.timer`
- **Updates:** `update` is `auto` in `opencode.jsonc`, but activation needs a
  restart — `systemctl restart opencode`. Set it to `"notify"` and restart by
  hand if you prefer to control timing.
- **Remove it:** `sudo bash uninstall.sh` (keeps data) or `--purge` (deletes it).

## Security

- The server listens on **127.0.0.1** by default. `--remote` is what makes it
  reachable from anywhere, and it is password-gated and end-to-end encrypted.
- The agent is never root, and `sudo` plus `git push` are hard-denied by
  `policies`, which project config and "Allow always" approvals cannot override.
- `.env`, private keys and `*.pem` files are denied to `read`.
- Anything you leave at `ask` is a deliberate pause: if no device is connected,
  the task waits for you instead of guessing. Everything else runs unattended.
- Changing the service password signs out every paired device, which is how you
  evict a lost phone.

## Optional: Docker

`docker-compose.yml` runs the published image instead of the native install.
Read its comments first: the native install is the path that pairing is
documented against.

## Troubleshooting

| Symptom | Try |
| --- | --- |
| `opencode` not found after install | `ln -sf ~opencode/.opencode/bin/opencode /usr/local/bin/opencode` |
| Server did not come up | `journalctl -u opencode`, then the log file above |
| Client cannot connect | `sudo bash verify.sh`; make sure the client uses the address the server is bound to |
| Browser client blocked on another origin | `su - opencode -c 'opencode service set cors https://origin'` |
| Pair link expired | Run `opencode pair` again — links last five minutes |

Upstream references: [CLI](https://opencode.ai/v2/docs/cli) ·
[Web and pairing](https://opencode.ai/v2/docs/cli/web) ·
[Permissions](https://opencode.ai/v2/docs/permissions) ·
[Policies](https://opencode.ai/v2/docs/policies) ·
[Troubleshooting](https://opencode.ai/v2/docs/troubleshooting)

## Defaults I chose, so you can flip them

- **Loopback binding**, with `--remote` as the opt-in exposure. Safer than
  binding `0.0.0.0` on a machine that may sit on an untrusted network.
- **`git push` and `sudo` denied**, in permissions *and* policies. Relax
  `git push` if you want unattended commits pushed.
- **`.env` reads denied** rather than the default `ask`, so unattended work does
  not stall, at the cost of the agent not seeing local secrets.
- **Dedicated unprivileged `opencode` user** rather than running as root.
- **`update: "auto"`** with a manual restart to activate.
