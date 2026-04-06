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

*Source: Phase 3 plan*

### No MCP server authentication

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

Enforce CPU/memory limits per project container to prevent resource abuse. Not currently configured.

*Source: Grand plan*

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
