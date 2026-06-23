# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Glass Keep — a Google Keep-style notes app. Vite + React 19 frontend, Express + SQLite (`better-sqlite3`) backend. Features Markdown notes, checklists, freehand drawings, images, tags, multi-user auth, real-time collaboration, an admin panel, PWA support, and an optional private server-side AI assistant (Llama 3.2 1B via `@huggingface/transformers`).

Note: package name is `liquid-keep` and Docker images use `glass-keep`; these refer to the same app.

## Commands

```bash
npm install              # install deps (native: better-sqlite3, sharp)
npm run dev              # runs Vite (web :5173) + API (:8080) concurrently
npm run api              # API only (nodemon, NODE_ENV=development, API_PORT=8080)
npm run build            # production build → dist/
npm run preview          # preview built frontend
npx eslint .             # lint (no lint script defined in package.json)
./local_docker_run.sh    # build + run prod-style Docker container on :8080
```

There is no test suite.

To run with admin auto-promotion in dev: `ADMIN_EMAILS="your-username" npm run dev`.

## Architecture

The app is essentially two large files. Be prepared to navigate within them rather than expecting many small modules.

- **`src/App.jsx`** (~6700 lines): the entire React frontend — auth screens, notes grid, modal editor, composer, admin panel, settings, collaboration UI, drag-and-drop (`@dnd-kit`), search/AI bar. Components are co-located in this one file.
- **`server/index.js`** (~1300 lines): the entire Express API — auth, notes CRUD, collaboration, admin, AI endpoints, SSE, and (in production) serving the built frontend.
- **`src/DrawingCanvas.jsx`**: freehand drawing component.
- **`src/ai.js`**: thin client wrapper that POSTs to `/api/ai/ask`; AI inference runs server-side, not in the browser.

### Dev vs. production topology
- **Dev**: Vite serves the UI on `:5173` and proxies `/api` → `http://localhost:8080` (see `vite.config.js`). The API runs separately.
- **Production**: a single Express process on `API_PORT` (default 8080) serves both the API and the static `dist/` build. The catch-all route (`app.get("*")`) only mounts when `NODE_ENV=production`.

### Data layer
SQLite via `better-sqlite3`, file at `DB_FILE` (default `/app/data/notes.db` in Docker). Three tables: `users`, `notes`, `note_collaborators`. Schema is created with `CREATE TABLE IF NOT EXISTS` on startup, and migrations are done in-line via `PRAGMA table_info` checks followed by `ALTER TABLE ADD COLUMN` — when adding a column, follow this same idempotent pattern. SQL statements are pre-compiled with `db.prepare(...)` near the top of the file and reused.

### Auth
JWT (`jsonwebtoken`) signed with `JWT_SECRET`; passwords hashed with `bcryptjs`. The `auth` middleware reads `Authorization: Bearer`; `authFromQueryOrHeader` also accepts a token query param (needed for SSE/`EventSource`, which can't set headers). `adminOnly` gates admin routes. There's also a "secret key" recovery flow (`/api/secret-key`, `/api/login/secret`).

### Real-time collaboration (SSE)
Clients open an `EventSource` to `/api/events`. The server keeps an in-memory `sseClients` map of `userId → Set<res>`. `broadcastNoteUpdated(noteId)` pushes a `note_updated` event to the note owner and all collaborators after mutations. Because client tracking is in-memory, it does not survive restarts and won't work across multiple server instances without a shared pub/sub layer.

### AI assistant
Server-side, lazy-loaded. The model is **not** downloaded on startup (auto-init is intentionally disabled — see `AI_CHANGES.md`). `/api/ai/initialize` and the first `/api/ai/ask` trigger `initServerAI()`, which loads the ~700MB quantized Llama-3.2-1B ONNX model. `/api/ai/ask` does keyword-based note filtering (RAG-lite, top 5 notes) and builds a Llama-3 chat-template prompt grounded only in those notes. Model cache lives in `/app/data/ai-cache` in Docker.

## Key environment variables

| Var | Purpose | Default |
|-----|---------|---------|
| `API_PORT` / `PORT` | API listen port | `8080` |
| `JWT_SECRET` | JWT signing secret — **must** change in prod | `dev-secret-please-change` |
| `NODE_ENV` | enables static serving + prod behavior when `production` | `development` |
| `DB_FILE` / `SQLITE_FILE` | SQLite path | `/app/data/notes.db` (Docker) |
| `ADMIN_EMAILS` | comma-separated usernames auto-promoted to admin | empty |
| `ALLOW_REGISTRATION` | whether new account creation is allowed | `false` |

On a fresh DB with no users, a default `admin` / `admin` account is created (see the user-count check around the `insertUser` logic). Registration is off by default.

## Docker

Multi-stage `Dockerfile`: builder stage runs `npm ci` + `npm run build`, runtime stage installs `libvips-dev` and runs `npm rebuild sharp` (fixes platform-binary mismatch for the `sharp` dep), then serves via `node server/index.js`. Data persists through a volume mounted at `/app/data`.

## Conventions

- ESLint flat config (`eslint.config.js`); `no-unused-vars` ignores identifiers matching `^[A-Z_]` (constants/components).
- ES modules throughout (`"type": "module"`).
- Tailwind v4 (via `@tailwindcss/vite`) with a glassmorphism aesthetic; dark/light mode persisted client-side.
- `AI_CHANGES.md` documents the rationale behind the opt-in AI behavior — consult it before changing AI init flow.
- When adding a new feature, always update `README.md` — specifically the "About this fork" section — to reflect it.
