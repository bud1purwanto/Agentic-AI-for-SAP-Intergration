# MCP Email Connector

A standalone **MCP (Model Context Protocol) server** that acts purely as an
**Email Connector**. It reads mail via IMAP (`imapflow`) and sends mail via SMTP
(`nodemailer`), exposing three tools over the stdio transport so an external AI
Orchestrator can use them.

## Tools

| Tool            | Description                                              | Arguments |
|-----------------|----------------------------------------------------------|-----------|
| `search_emails` | Search the INBOX, return summaries.                      | `query?` (string), `maxResults` (number, default 5), `unreadOnly` (bool, default false) |
| `read_email`    | Fetch one email; body cleaned to plain text / Markdown.  | `messageId` (string, required) |
| `send_email`    | Send a new email or reply.                               | `to`, `subject`, `body` (all required) |

## Configuration

The mail server is **Microsoft Exchange Server 2007**, which has two quirks
that shape this setup:

1. **Legacy TLS only.** Exchange 2007 speaks TLS 1.0, which modern
   Node/OpenSSL has removed. IMAP (port 993) is therefore reached through a
   local **`stunnel`** bridge (see [`stunnel.conf`](stunnel.conf)) that
   terminates the old TLS and exposes a plaintext loopback port:

   ```
   Node app --plaintext--> 127.0.0.1:11993 --[stunnel: TLS 1.0]--> Exchange:993
   ```

   SMTP doesn't need a bridge: port 465 (implicit TLS) is firewall-blocked, so
   the app talks directly to the plain submission port 587.

2. **AD-style login.** Exchange 2007 authenticates against Active Directory
   using `DOMAIN\username`, not the SMTP address. The mailbox address
   (configured via `EMAIL_USER`, used as From/search target) and the login
   identity (configured via `EMAIL_LOGIN_USER`, used for auth) are configured
   via environment variables.

Endpoints/login are overridable via env (see `.env.example`):

| Var | Default | Purpose |
|-----|---------|---------|
| `EMAIL_PASS` | *(required)* | AD account password. Never hardcoded. |
| `EMAIL_USER` | *(required)* | Mailbox email address (e.g. `user@trst.co.id`). |
| `EMAIL_LOGIN_USER` | *(required)* | Auth identity for IMAP/SMTP/EWS (`DOMAIN\username`). |
| `IMAP_HOST` / `IMAP_PORT` | `127.0.0.1` / `11993` | Points at the stunnel bridge. |
| `SMTP_HOST` / `SMTP_PORT` | `mail.triasmail.co.id` / `587` | Direct submission port. |

## Setup

```bash
# 1. Install dependencies
npm install

# 2. Configure credentials
cp .env.example .env
#   then edit .env and set EMAIL_PASS=... (EMAIL_LOGIN_USER default is usually fine)

# 3. Install & start the stunnel bridge (one-time, needs Administrator)
winget install --id MichalTrojnara.Stunnel -e
#   In an elevated PowerShell:
$exe="C:\Program Files (x86)\stunnel\bin\stunnel.exe"
$cfg="<path to this project>\stunnel.conf"
& $exe -install $cfg
Start-Service stunnel
Set-Service stunnel -StartupType Automatic   # survives reboot

# 4. Build
npm run build

# 5. Run
npm start
# or directly:  node dist/index.js
```

For development with auto-recompile: `npm run dev`.

To verify IMAP/SMTP connectivity independently of an MCP client, run
`node dist/testConnection.js` after building — it checks both transports and
prints recent inbox messages without sending anything.

## Registering with an MCP client / Orchestrator

Add an entry like this to your MCP client config:

```json
{
  "mcpServers": {
    "email": {
      "command": "node",
      "args": ["C:\\Users\\Lenovo\\Documents\\Claude\\MCP Email\\dist\\index.js"],
      "env": {
        "EMAIL_PASS": "your-email-password"
      }
    }
  }
}
```

## Notes on connection efficiency

- A single long-lived IMAP connection is reused across tool calls. It is created
  lazily, guarded by an in-flight promise (so concurrent calls share it), and
  automatically dropped/reconnected on `close`/`error`.
- SMTP uses a `nodemailer` connection **pool** (`pool: true`, `maxConnections: 3`).
- On `SIGINT`/`SIGTERM` the IMAP connection logs out and the SMTP pool closes.
- The `stunnel` Windows service runs independently of this app (Automatic
  startup), so the IMAP bridge is already up before the MCP server is spawned.
