# Future Considerations

This file collects future considerations, known limitations, deferred features, and technical debt discovered during development. Each item includes enough context to be picked up later without needing to re-read the original plan files.

---

## Known Limitations (POC)

### Docker configuration as attack vector

The agent can edit `docker-compose.yml` and Dockerfiles inside the workspace container, enabling several host escapes:

- **Volume mount escape**: Map host directories (e.g., `volumes: - /etc:/hack`). The `rebuild_workspace` MCP tool validates mounts before rebuilding, but this is a basic guard.
- **Build context escape**: Changing `context:` to `../../` or `/` lets `COPY`/`ADD` reach files outside the project.
- **Dockerfile `ADD <url>`**: Downloads arbitrary content during build.
- **Malicious base images**: `FROM malicious-image:latest` could run anything.

**Mitigation for production**: Docker-in-Docker or Firecracker/sandboxed VMs so the "host" the agent can escape to is itself isolated. Alternatively, provide a controlled API for Docker config changes instead of letting the agent edit these files directly.

A related consideration: restricting direct editing of `Dockerfile.workspace` and `docker-compose.yml`. A controlled API (e.g., "add runtime X", "add service Y") would be safer, but limits flexibility -- the agent can't install arbitrary tools or add custom services without API support for each case. Trade-offs to evaluate:

- Controlled API: safe but rigid, requires anticipating every legitimate use case
- Allowlist approach: let the agent edit these files but validate changes against an allowlist of base images, volume patterns, and commands
- Hybrid: free editing in development/POC mode, locked down in production with an approval workflow (user reviews and confirms Dockerfile changes before rebuild)

*Source: Phase 3 plan, Phase 4 planning*

### Container network access to host services

Docker containers can reach the host machine via the Docker bridge gateway IP (typically `172.17.0.1` or `host.docker.internal`). This means the agent running inside a workspace container could potentially:

- Access the Devable backend API directly (bypassing auth if it listens on all interfaces)
- Access the PostgreSQL platform database on its host port
- Access Caddy admin API or other infrastructure services
- Access other project containers via the shared Docker network
- Probe other services running on the host

Mitigations to explore:

- Block outbound traffic to the Docker gateway IP via iptables rules in the container or Docker network configuration
- Add the host gateway IP to the `CommandFilter` deny list (block `curl`/`wget`/`nc` to those IPs)
- Use `--internal` Docker networks that have no gateway route to the host
- Bind infrastructure services (backend, Caddy admin, platform DB) to `127.0.0.1` only, not `0.0.0.0`
- Use separate Docker networks per project so containers can't reach other projects' services

*Source: Phase 4 planning*



The container sandbox MCP server runs as a local stdio child process with no server-level auth. Security relies on `ChatService` verifying project ownership before spawning the MCP server. Fine for the POC (trust boundary is the host machine), but needs proper authentication (Clerk JWT, API tokens, or OAuth) if the MCP server is ever exposed over HTTP for remote access.

*Source: Phase 3 plan*

### Single app container routed via Caddy

Currently only the main `type = "app"` container gets a Caddy route per project. A project may have multiple publicly routable services (webapp, API, admin panel) that each need distinct subdomains (e.g., `my-app.localhost`, `my-app-api.localhost`). The `ProjectContainer.port` field already supports this -- each container has its own port -- but the Caddy routing logic only creates one route per project.

*Source: Phase 1 plan, Grand plan*

---

## Infrastructure (Production)

### Replace Caddy with Traefik

Traefik offers auto-discovery of Docker containers via labels, better scaling, a built-in dashboard, and Let's Encrypt integration. Caddy works for the POC but Traefik is better suited for multi-service, multi-project routing at scale.

*Source: Grand plan*

### Move from Docker Compose to Kubernetes or Docker Swarm

Docker Compose is per-host. For multi-node scaling, move to Kubernetes or Docker Swarm for orchestration, scheduling, and self-healing.

*Source: Grand plan*

### Project isolation with Docker-in-Docker or Firecracker

Each project should run in its own isolated environment (Docker-in-Docker or sandboxed VM) for proper security isolation between users. Currently all projects share the host Docker daemon.

*Source: Grand plan*

### Cloud code storage

Move from local disk (`user-projects/`) to cloud storage (S3/GCS) with a git-backed system, or provide each project its own git repo with GitHub/GitLab integration.

*Source: Grand plan*

### Container resource limits

Enforce CPU, memory, and disk space limits per project container to prevent resource abuse. Currently no limits are configured, so a single project (or the agent running inside it) could exhaust host resources. Areas to address:

- **CPU**: Use `cpus` / `cpu_shares` in docker-compose to cap CPU per container
- **Memory**: Use `mem_limit` / `memswap_limit` to prevent OOM of host
- **Disk space (bind mounts)**: The agent could fill host disk via `npm install`, build artifacts, or log output. Options include filesystem-level quotas, periodic monitoring with alerts/cleanup, or running projects in volume-backed storage with size limits.
- **Container image size**: The agent can install arbitrary packages into the workspace container (via `apt install`, `npm install -g`, etc.) and rebuild it, causing the image to grow unbounded. Consider max image size checks before/after rebuild, layer squashing, or periodic base image resets.
- **Network bandwidth**: Rate-limit outbound traffic to prevent abuse (crypto mining, DDoS)
- **Process count**: Use `pids_limit` to prevent fork bombs

Consider making limits configurable per subscription tier (e.g., free vs paid users get different resource allocations).

*Source: Grand plan, Phase 4 planning*

### Network isolation

Each project's Docker network should be fully isolated with no cross-project access. Currently all projects share the default Docker network.

*Source: Grand plan*

### Secrets management

Move from `.env` files to a proper secrets manager (HashiCorp Vault, AWS Secrets Manager) for production.

*Source: Grand plan*

---

## AI Agent

### User-provided API keys

Create a `UserSettings` table with encrypted API key storage. Allows users to bring their own Anthropic API key when the service is deployed. Currently the system uses either `ANTHROPIC_API_KEY` from `.env` (SDK mode) or Max subscription (CLI mode).

*Source: Phase 3 plan*

### Agent screenshots via Playwright MCP

Add automated screenshot capability so the agent can verify its own work by taking screenshots of the preview URL. Use the Playwright MCP server. Currently users can manually drop screenshots into the chat.

*Source: Phase 3 plan*

### Remote MCP access for local Claude Code

Add HTTP/SSE transport to the container sandbox MCP server so users can connect their local Claude Code (with Max subscription) to a remote Devable project. The MCP server already handles container isolation and command filtering. Requires proper authentication on the MCP server (see "No MCP server authentication" in limitations).

*Source: Phase 3 plan*

### Shared conversation context across local and web agents

When a user works on a project via local Claude Code + remote MCP, the conversation lives locally and is invisible to the web UI (and vice versa). To bridge this:

- Expose a `conversation_history` MCP resource so local Claude Code can read the web UI's chat history.
- Add a `log_message` MCP tool so local sessions can write to the shared `ChatMessage` table.

*Source: Phase 3 plan*

### Session management improvements

Currently, if a session is lost (files deleted, corrupted, server migration, CLI/SDK mode switch), a new session starts and the old one is marked read-only. Future work:

- Reconstruct sessions from stored messages (summarize/truncate to fit context limits).
- Cross-server session portability.
- Graceful handling of edge cases.

Revisit once the production deployment model is clearer.

*Source: Phase 3 plan*

### Rate limiting and cost tracking

Per-user token/message rate limits and API cost tracking per user/project. Surface cost data and enforce budget limits.

*Source: Grand plan*

---

## Features

### Git repositories per project with branch isolation

Each project should have an actual git repository. When multiple agents or a mix of web UI and local Claude Code sessions work on the same project, each agent session should work on its own branch to avoid conflicts:

- Project creation initializes a git repo with an initial commit.
- Each new agent session creates a feature branch (e.g., `agent/<sessionId>`).
- When the user approves changes, the branch is merged to main.
- Conflicts are surfaced to the user for resolution.
- Provides version history and rollback for free.
- The web UI could show a branch/commit timeline alongside the chat.

*Source: Phase 3 plan*

### Publishing / deployment

Deploy projects to hosting providers (Vercel, Fly.io, Railway).

*Source: Grand plan*

### Code download

Git clone or zip download capability for user projects.

*Source: Grand plan*

### Collaboration

Multiple users on a project with real-time cursors.

*Source: Grand plan*

### Version history

Git-based rollback and conversation-linked snapshots.

*Source: Grand plan*

### Custom domains

User brings their own domain for published projects.

*Source: Grand plan*

### Managed database integration

Supabase/Neon integration as a managed database option alongside self-hosted PostgreSQL.

*Source: Grand plan*

### Edge functions

Serverless function support for projects.

*Source: Grand plan*

### Chat panel elapsed time indicator

Add a timer in the chat panel that shows how long the user has been waiting for the agent to respond. Currently there is no visible indication of elapsed time during long agent operations (which can take 30-120+ seconds for multi-tool tasks). The timer should start when a message is sent and stop when the response completes.

*Source: Phase 3 integration testing*

### Better agent activity visibility in chat

The current chat panel shows sparse text updates during agent operations. When the agent is using tools (reading files, running commands, writing code), the user sees very little feedback. Improvements needed:

- Show real-time tool use progress (which file is being read/written, what command is running)
- Show intermediate results from tool calls (command output, file diffs)
- Make the "streaming" indicator more informative than just "..."
- Consider a log/activity panel showing raw tool use alongside the conversation
- The conversation flow feels disconnected when the agent does many tool calls between text responses

*Source: Phase 3 integration testing*

### Chronological ordering of messages and tool uses in chat

Currently, assistant text and tool use indicators are not displayed in chronological order. The agent may emit tool use events first, then text — but the text renders above the tool indicators because text_delta events and tool_use events are accumulated separately. The chat should render all content blocks (text, tool use start, tool use end, intermediate text) in the exact order they arrive from the stream, so the conversation reads naturally as a timeline.

*Source: Phase 3 integration testing*

### Monitor workspace container command failures

Track commands that fail inside the workspace container (`exec_command` returning non-zero exit codes) and analyze patterns over time. This helps identify:

- Missing tools/runtimes in the workspace container (e.g., `bunx: not found` was observed during testing)
- Common agent mistakes that could be prevented via better system prompts
- Commands that should be pre-installed in `Dockerfile.workspace` templates
- Patterns that the `CommandFilter` could catch proactively

Consider a dashboard or log aggregation for failed commands per project/template type.

*Source: Phase 3 integration testing*

### Preview panel alternative to iframe

The preview panel currently uses an `<iframe>` to embed the live project. For the POC this works well, but alternatives to explore for production:

- Headless browser streaming (screenshot-based preview) for better isolation
- WebContainer-based approach for Node.js projects
- Split between iframe (simple) and screenshot mode (when cross-origin issues arise)

*Source: Phase 3 integration testing*

### Multiple chat panels / split view

Side-by-side conversations or chat + code editor layout.

*Source: Phase 3 plan*

### Message search

Full-text search across chat history.

*Source: Phase 3 plan*

### Conversation export

Download chat history as markdown.

*Source: Phase 3 plan*

---

## Technical Debt

### Migrate frontend proxy routes to direct backend calls

Phase 1 created Next.js API proxy routes (`src/app/api/projects/`, `src/app/api/announcements/`) that forward requests to the backend. Phase 3 calls the backend directly instead. The Phase 1 proxy routes should be migrated to direct calls and removed.

*Source: Phase 3 plan*

### Separation of infrastructure files from project code

Currently, infrastructure files (`docker-compose.yml`, `Dockerfile`, `Dockerfile.workspace`, `.env`) live alongside project code and can be freely edited or deleted by the user or agent. This creates several problems:

- Deleting or breaking these files prevents container rebuild/restart (not immediate — running containers keep going, but recovery is blocked)
- Users creating additional Dockerfiles (e.g., for new services) have no way to build/start containers from them through the UI
- The agent can modify infrastructure files in ways that compromise security (see "Docker configuration as attack vector")

A cleaner model would separate infrastructure management from code editing:

- **Infrastructure layer**: `docker-compose.yml`, Dockerfiles, `.env` managed through a dedicated UI (service manager, not the code editor). Changes go through validation before applying.
- **Code layer**: Everything else — freely editable by user and agent
- **Service manager UI**: Add/remove/configure services (databases, caches, custom containers), manage environment variables, view service topology. User-created Dockerfiles register as new services here.
- **Build/deploy pipeline**: Explicit "rebuild" and "restart" actions per service, with validation and rollback if the build fails

For the POC, infrastructure files are editable with warning dialogs, and rebuild/restart is available via buttons in the editor header.

*Source: Phase 4 planning*

### Real-time build output streaming for container rebuilds

The POC uses fire-and-forget with status polling for container rebuilds (`POST /rebuild` returns 202, frontend polls `/status`). This gives no visibility into what's happening during a build. Future improvements:

- **SSE stream of build output**: Return real-time `docker compose build` output lines so users can see which layer is building, what's being installed, and where errors occur
- **Build log persistence**: Store build logs in DB so users can review them after the build completes. Critical for debugging failed builds — the POC only shows a generic "Rebuild failed" error with no details about what went wrong (missing package, syntax error in Dockerfile, etc.)
- **Build error details in UI**: Surface the last N lines of build output when a rebuild fails, so users can diagnose the issue without SSH access. Could be shown in a modal, the logs panel, or a dedicated "build history" view.
- **Per-service rebuild**: Allow rebuilding individual services instead of the whole project (e.g., only rebuild the workspace container after editing `Dockerfile.workspace`)
- **Build caching visibility**: Show which layers were cached vs rebuilt, helping users understand build times

*Source: Phase 4 planning*

### Rebuild status polling in the UI

When a container rebuild is triggered, the UI shows "rebuilding" status but never updates to "running" or "error" without a manual page reload. The plan called for polling `GET /projects/:id/status` every 3s while `status === 'rebuilding'` with a 5-minute timeout, but this polling was not implemented in the POC. The `refreshProjectAsync` call after `rebuildProjectAsync` returns immediately (since rebuild is fire-and-forget with 202 Accepted), so it reads the status as "rebuilding" and stops there.

To fix: add a polling loop in the `EditorHeader` (or a custom hook) that polls the project status at intervals while it's "rebuilding", and stops when it transitions to "running" or "error".

*Source: Phase 4 integration testing*

### Background job system for container rebuilds

Container rebuilds currently use a fire-and-forget pattern: the service method starts the rebuild as an untracked promise and the frontend polls for status. This works for the POC but has downsides: no retry on failure, no job tracking, no visibility into queued work, and risk of lost state if the server restarts mid-rebuild. Future improvements:

- Replace fire-and-forget with a proper job/queue system (e.g., BullMQ, pg-boss, or a custom job table in PostgreSQL) so background work is durable and observable
- Track job state (queued, running, succeeded, failed) with timestamps and error details
- Support retry with backoff for transient failures
- Allow cancellation of in-progress builds
- Provide job history for debugging (when did the last build run, how long did it take, what was the error)

This pattern would also apply to other long-running operations beyond container rebuilds (e.g., template scaffolding, project deletion cleanup).

*Source: Phase 4 implementation*

### SSE stream lifecycle management

Long-lived SSE streams (log streaming, chat streaming) can become zombies if the caller abandons them without proper cleanup. Current mitigations are AbortSignal on component unmount and tab switching, but production needs more:

- **Frontend idle timeout**: Auto-close streams that receive no events for a configurable duration (e.g., 5 minutes). Protects against zombie streams where the `onEvent` handler is no longer active.
- **Backend idle timeout**: If the server detects no client reads (SSE response buffer not being consumed), kill the spawned `docker compose logs` process. Currently the backend spawns `docker compose logs -f` which runs indefinitely.
- **"Are you still there?" UX**: After extended inactivity on a streaming view (e.g., 5 minutes of no user interaction), prompt the user and pause the stream if they don't respond. Reduces resource waste from forgotten browser tabs.
- **Max stream duration**: Hard limit (e.g., 30 minutes) to prevent indefinitely open connections regardless of activity.
- **Connection counting**: Track open SSE connections per user/project to prevent resource exhaustion from many concurrent streams.

This applies to both log streaming and chat streaming SSE connections.

*Source: Phase 4 implementation*

### Persist editor UI state across page reloads

When the user reloads the browser page, all editor UI state is lost: active view tab (Code/Preview/Logs/Split), open file tabs in the code editor, file tree expansion state, and resizable panel positions. The user has to re-select their view, re-open files, and re-adjust panel sizes every time.

Options to persist this state:
- **localStorage**: Store `activeView`, `openFiles` paths, `activeFilePath`, panel sizes per project. Simple and fast, but local to the browser.
- **URL hash/query params**: Encode the active view and file path in the URL (e.g., `?view=split&file=src/app/globals.css`). Enables sharing links to specific files/views.
- **Backend/DB**: Store per-user per-project editor preferences. Persists across devices but adds API calls.

For the POC, localStorage is the easiest win. Panel sizes can be persisted via `react-resizable-panels`'s built-in `autoSaveId` prop on the `Group` component.

*Source: Phase 4 integration testing*

### Non-interactive database migrations in workspace containers

Some database migration tools (e.g., Prisma) require interactive confirmation prompts that the agent cannot handle via `exec_command`. For example, `prisma migrate dev` may ask "Are you sure you want to reset the database?" and hang waiting for input. Options to explore:

- Use non-interactive flags where available (e.g., `prisma migrate deploy` instead of `prisma migrate dev`, or `--force` flags)
- Pipe `yes` or use `echo y |` to auto-confirm (fragile, tool-specific)
- Add a dedicated MCP tool for migrations that handles interactive prompts programmatically
- Provide the agent with guidance in the system prompt about which migration commands to use and which to avoid

This applies to any CLI tool the agent might invoke that expects interactive input.

*Source: Phase 4 planning*
