# Infrastructure Setup — Sharan Fincorp Local Development Stack

> **Last Updated**: 2026-07-26
> **Maintainer**: Sharan Fincorp Dev Team
> **Status**: Active

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Repository Layout](#2-repository-layout)
3. [Tech Stack & Versions](#3-tech-stack--versions)
4. [Colima VM Setup (macOS)](#4-colima-vm-setup-macos)
5. [One-Command Stack Startup](#5-one-command-stack-startup)
6. [Service Map & Port Reference](#6-service-map--port-reference)
7. [Migration System](#7-migration-system)
8. [Accessing Supabase Studio](#8-accessing-supabase-studio)
9. [SSH Tunnel Workaround (Colima without --network-address)](#9-ssh-tunnel-workaround)
10. [Stopping & Resetting the Stack](#10-stopping--resetting-the-stack)
11. [Credentials & Secrets](#11-credentials--secrets)
12. [Daily Developer Workflow](#12-daily-developer-workflow)
13. [Troubleshooting Reference](#13-troubleshooting-reference)
14. [Key Changes Made to docker-compose.yml](#14-key-changes-made-to-docker-composeyml)

---

## 1. Architecture Overview

```
┌─────────────────────────── macOS Host ──────────────────────────────┐
│                                                                       │
│  Flutter App (Web/Android)                                            │
│       │                                                               │
│       │ HTTP / WebSocket                                              │
│       ▼                                                               │
│  localhost:8000  ◄──────────────────────────────────────────────┐    │
│  localhost:3000 (Studio)                                         │    │
│                                                                  │    │
│ ┌─────────────────────── Colima QEMU VM ───────────────────────┐ │    │
│ │                                                               │ │    │
│ │  ┌─────────────────── docker-compose ───────────────────┐    │ │    │
│ │  │                                                       │    │ │    │
│ │  │  supabase-kong (API Gateway) :8000 ◄─────────────────┼────┘ │    │
│ │  │        │                                              │      │    │
│ │  │        ├──► supabase-rest  (PostgREST)                │      │    │
│ │  │        ├──► supabase-auth  (GoTrue)                   │      │    │
│ │  │        ├──► supabase-realtime                         │      │    │
│ │  │        ├──► supabase-storage                          │      │    │
│ │  │        └──► supabase-edge-functions                   │      │    │
│ │  │                                                       │      │    │
│ │  │  supabase-studio (Dashboard) :3000                    │      │    │
│ │  │  supabase-meta   (pg-meta)   :8080                    │      │    │
│ │  │  supabase-pooler (Supavisor) :5432 / :6543            │      │    │
│ │  │  supabase-db     (Postgres)  :5432 (internal)         │      │    │
│ │  │  supabase-migration-runner   (one-shot)               │      │    │
│ │  └───────────────────────────────────────────────────────┘      │    │
│ └──────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Repository Layout

```
/Users/manjit/work/revi-saran/
│
├── supabase/docker/                    ← Self-hosted Supabase docker-compose stack
│   ├── docker-compose.yml              ← PRIMARY: start everything with this
│   ├── .env                            ← Stack secrets (gitignored)
│   ├── .env.example                    ← Template for secrets
│   ├── reset.sh                        ← Full data wipe + restart script
│   ├── run.sh                          ← Helper run script
│   └── volumes/
│       ├── db/
│       │   ├── migrate.sh              ← ✨ Idempotent migration runner (NEW)
│       │   ├── jwt.sql
│       │   ├── roles.sql
│       │   └── ...
│       ├── api/                        ← Kong config
│       ├── pooler/                     ← Supavisor config
│       └── functions/                  ← Edge Function code
│
└── Mutual_Fund_Portfolio_App/          ← Flutter application
    ├── .env                            ← App-level Supabase URL + keys
    ├── AGENTS.md                       ← AI operating manual
    ├── lib/                            ← Dart source code
    └── supabase/
        ├── config.toml                 ← Supabase CLI project config
        ├── migrations/                 ← ✨ SQL migrations (auto-applied on up)
        │   ├── 20260717000000_init_schema.sql
        │   ├── 20260717000001_ingestion_system.sql
        │   ├── ... (26 files total)
        │   └── 20260730000001_user_management_workspace.sql
        └── functions/                  ← Edge function source
```

---

## 3. Tech Stack & Versions

| Component | Image / Tool | Version |
|-----------|-------------|---------|
| Container Runtime | Colima (QEMU) | latest |
| Docker Compose | docker compose v2 | bundled |
| Postgres | supabase/postgres | 17.6.1.136 |
| PostgREST | supabase/postgrest | (via Kong) |
| GoTrue (Auth) | supabase/gotrue | (via compose) |
| Realtime | supabase/realtime | (via compose) |
| Studio | supabase/studio | 2026.07.07-sha-a6a04f2 |
| Kong (API GW) | kong/kong | 3.9.1 |
| Supavisor (Pooler) | supabase/supavisor | 2.9.5 |
| pg-meta | supabase/postgres-meta | (via compose) |

---

## 4. Colima VM Setup (macOS)

Colima is a lightweight, open-source alternative to Docker Desktop for macOS.
It runs a Linux VM via QEMU/Lima and provides the Docker socket.

### Install Colima (one-time)
```bash
brew install colima
brew install docker
brew install docker-compose
```

### Start Colima (recommended — with network address)
```bash
colima start --network-address
```

Using `--network-address` assigns a routable IP to the VM so that all
published container ports are accessible at `localhost` directly. Without
this flag, you need an SSH tunnel (see Section 9).

### Verify Colima is running
```bash
colima status
colima list
```

### Stop Colima (stops all containers)
```bash
colima stop
```

---

## 5. One-Command Stack Startup

After Colima is running, a **single command** starts all services AND
runs all pending migrations automatically:

```bash
cd /Users/manjit/work/revi-saran/supabase/docker
docker compose up -d
```

### What happens on `docker compose up -d`

| Order | Service | Action |
|-------|---------|--------|
| 1 | `supabase-db` | Starts Postgres 17, runs init SQL scripts |
| 2 | `supabase-migration-runner` | Waits for DB health, applies all pending migrations, exits |
| 3 | `supabase-meta` | Starts pg-meta metadata API |
| 4 | `supabase-rest` | Starts PostgREST |
| 5 | `supabase-auth` | Starts GoTrue |
| 6 | `supabase-realtime` | Starts Realtime |
| 7 | `supabase-storage` | Starts Storage |
| 8 | `supabase-edge-functions` | Starts Deno runtime |
| 9 | `supabase-studio` | Starts Dashboard UI on port 3000 |
| 10 | `supabase-kong` | Starts API Gateway on port 8000 |
| 11 | `supabase-pooler` | Starts Supavisor connection pooler |

---

## 6. Service Map & Port Reference

| Container | Service | Host Port | Internal Port | Purpose |
|-----------|---------|-----------|---------------|---------|
| `supabase-studio` | Studio | **3000** | 3000 | Dashboard UI |
| `supabase-kong` | Kong | **8000** | 8000 | REST API + Auth gateway |
| `supabase-kong` | Kong HTTPS | **8443** | 8443 | HTTPS gateway |
| `supabase-pooler` | Supavisor | **5432** | 5432 | Postgres session pooling |
| `supabase-pooler` | Supavisor | **6543** | 6543 | Postgres transaction pooling |
| `supabase-db` | Postgres | internal | 5432 | Raw database |
| `supabase-migration-runner` | Migration | — | — | One-shot, exits after run |

---

## 7. Migration System

### How it works

The `migration-runner` service is a one-shot Docker container that:
1. Waits for `supabase-db` to be healthy (via `pg_isready`)
2. Creates `supabase_migrations.schema_migrations` table if it doesn't exist
3. Iterates all `.sql` files in `/migrations` (mounted from the app repo) in sorted order
4. Skips files whose `version` is already in the tracking table
5. Applies new migrations and records them in the tracking table
6. Exits with code 0 on success, 1 on failure

### Migration runner script

Location: `/Users/manjit/work/revi-saran/supabase/docker/volumes/db/migrate.sh`

The script is mounted read-only into the `migration-runner` container and
executed on every `docker compose up`.

### Migration file naming convention

```
YYYYMMDD000000_descriptive_name.sql
```

Example: `20260730000001_user_management_workspace.sql`

The timestamp-based version ensures correct ordering and uniqueness.

### Tracking table

```sql
-- Check which migrations have been applied
SELECT version, name, applied_at
FROM supabase_migrations.schema_migrations
ORDER BY version;
```

### Adding a new migration

1. Create your SQL file in `Mutual_Fund_Portfolio_App/supabase/migrations/`
2. Use the next sequential timestamp prefix
3. Run `docker compose up -d` from the docker directory
4. The runner applies it automatically

### Manually replaying all migrations

```bash
docker compose run --rm migration-runner
```

### Applying a single file manually

```bash
docker exec -i supabase-db psql -U postgres -d postgres \
  < Mutual_Fund_Portfolio_App/supabase/migrations/<filename>.sql
```

---

## 8. Accessing Supabase Studio

**URL**: http://localhost:3000

| Section | Path | Description |
|---------|------|-------------|
| Table Editor | `/project/default/editor` | Browse and edit table data |
| SQL Editor | `/project/default/sql` | Run raw SQL queries |
| Migrations | `/project/default/database/migrations` | View migration history |
| Auth Users | `/project/default/auth/users` | Manage auth users |
| Storage | `/project/default/storage/buckets` | File storage |
| Edge Functions | `/project/default/functions` | Deno edge functions |

---

## 9. SSH Tunnel Workaround

> Only needed if Colima was started **without** `--network-address`.

### Get Colima SSH details
```bash
colima ssh-config
# Note the Port and IdentityFile values
```

### Open port tunnels
```bash
ssh \
  -i "/Users/manjit/.colima/_lima/_config/user" \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o IdentitiesOnly=yes \
  -N \
  -L 3000:localhost:3000 \
  -L 8000:localhost:8000 \
  -L 8443:localhost:8443 \
  -L 5432:localhost:5432 \
  -p <COLIMA_SSH_PORT> manjit@127.0.0.1 &
echo "Tunnel PID: $!"
```

> **Note**: The Colima SSH port changes across restarts. Always check with
> `colima ssh-config | grep Port` before running the tunnel.

### Permanent fix
```bash
colima stop
colima start --network-address
```

---

## 10. Stopping & Resetting the Stack

### Graceful stop (preserves data)
```bash
cd /Users/manjit/work/revi-saran/supabase/docker
docker compose down
```

### Stop and remove all data (full reset)
```bash
docker compose down -v
# All database data is wiped. Next `up` will re-run all migrations.
```

### Use the built-in reset script
```bash
cd /Users/manjit/work/revi-saran/supabase/docker
sh reset.sh
```

---

## 11. Credentials & Secrets

> ⚠️ **Never commit `.env` files to git.**

### Stack secrets (docker-compose)
File: `/Users/manjit/work/revi-saran/supabase/docker/.env`

| Variable | Purpose |
|----------|---------|
| `POSTGRES_PASSWORD` | Postgres superuser password |
| `JWT_SECRET` | Signs all Supabase JWTs |
| `ANON_KEY` | Public anon JWT for client apps |
| `SERVICE_ROLE_KEY` | Admin JWT (bypasses RLS) |
| `PG_META_CRYPTO_KEY` | Encrypts connection strings in Studio |

### App secrets (Flutter)
File: `/Users/manjit/work/revi-saran/Mutual_Fund_Portfolio_App/.env`

| Variable | Purpose |
|----------|---------|
| `SUPABASE_URL` | API gateway URL (http://localhost:8000) |
| `SUPABASE_ANON_KEY` | Public anon JWT for Flutter client |

---

## 12. Daily Developer Workflow

```bash
# 1. Start Colima (if not running)
colima start --network-address

# 2. Start the full Supabase stack (auto-migrates)
cd /Users/manjit/work/revi-saran/supabase/docker
docker compose up -d

# 3. Verify all healthy
docker ps --format "table {{.Names}}\t{{.Status}}"

# 4. Open Studio
open http://localhost:3000

# 5. Run the Flutter app
cd /Users/manjit/work/revi-saran/Mutual_Fund_Portfolio_App
flutter run -d chrome   # web
flutter run             # android

# --- At end of day ---
cd /Users/manjit/work/revi-saran/supabase/docker
docker compose down
colima stop
```

---

## 13. Troubleshooting Reference

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| `localhost:3000` connection refused | Colima without `--network-address` | SSH tunnel (Section 9) or restart with `--network-address` |
| Studio loads but tables missing | Migration runner did not run | `docker logs supabase-migration-runner` |
| Migration runner exits with error | SQL error in a migration file | Check logs, fix the SQL, re-run `docker compose run --rm migration-runner` |
| `supabase migration up` fails | CLI can't find local DB on port 54322 | Use `docker exec` psql or the migration-runner container instead |
| `docker compose up` fails | Colima not running | `colima start --network-address` |
| Port already in use | Another process on same port | `lsof -i :<PORT>` then `kill -9 <PID>` |
| DB not ready errors | Postgres still initializing | Wait 30s, check `docker logs supabase-db` |

---

## 14. Key Changes Made to docker-compose.yml

The following modifications were made to
`/Users/manjit/work/revi-saran/supabase/docker/docker-compose.yml`
beyond the upstream Supabase defaults:

### 1. Studio port exposed (line ~64)
```yaml
studio:
  ports:
    - "3000:3000"   # ← ADDED: exposes Studio to host
```
Without this, Supabase Studio was only accessible internally within Docker.

### 2. Migration runner service added (before `db` service)
```yaml
migration-runner:
  container_name: supabase-migration-runner
  image: supabase/postgres:17.6.1.136
  restart: "no"
  depends_on:
    db:
      condition: service_healthy
  environment:
    POSTGRES_HOST: ${POSTGRES_HOST}
    POSTGRES_PORT: ${POSTGRES_PORT}
    POSTGRES_DB: ${POSTGRES_DB}
    POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    POSTGRES_USER: postgres
  volumes:
    - ./volumes/db/migrate.sh:/migrate.sh:ro,z
    - ../../Mutual_Fund_Portfolio_App/supabase/migrations:/migrations:ro,z
  command: ["/bin/sh", "/migrate.sh"]
```

This ensures every `docker compose up` automatically applies any new
migrations without manual intervention.
