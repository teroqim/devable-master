# Phase 3: AI Agent Integration -- Detailed Plan

> **Status**: Approved
> **Created**: 2026-04-04
> **Parent plan**: `2026-03-28-20-30-devable-grand-plan.md`

---

## Context

### What already exists

Phase 1 & 2 delivered:

- **Project lifecycle**: Full create/delete orchestration (DB record, file scaffolding, Docker start/stop, Caddy route registration)
- **Templates**: 3 disk-based templates (nextjs-ts, bun-elysia-api, fullstack) with `{{VARIABLE}}` substitution via TemplateEngine
- **Design themes**: 3 CSS themes (clean, bold, soft) injected as `globals.css` during scaffolding
- **Dashboard UI**: Project list, create dialog with visual card pickers, delete confirmation, start/stop/restart
- **Services**: ProjectService, ProjectFileService, DockerService, CaddyService -- all wired via RunContext DI
- **DB models**: Project, ProjectContainer, ChatSession (schema exists but ChatSessionRepository not yet created)
- **API routes**: Full CRUD + start/stop/restart/status for projects
- **Auth**: Clerk JWT on both frontend (Next.js proxy) and backend (Elysia middleware)

### What Phase 3 delivers

By the end of Phase 3, a user can:

1. Open a project and see a chat interface with a live preview
2. Type a message (with optional image attachments) describing what they want to build
3. See the AI agent respond in real-time (streaming text)
4. See tool use indicators (file reads, edits, container commands)
5. Have the agent modify project files and run commands inside the Docker container (sandboxed)
6. See the results in a live preview iframe
7. Continue a conversation across page reloads (full message history displayed)
8. See token usage and cost information per message

---

## Resolved Design Decisions

### 1. Dual-mode: Claude Agent SDK + Claude Code CLI

Support **both** integration modes:

- **Claude Agent SDK** (`@anthropic-ai/claude-agent-sdk`): Used when deploying the service or when the user provides an Anthropic API key. Native TypeScript, typed messages, async iterators.
- **Claude Code CLI** (via `Bun.spawn()`): Used for local development with a Max subscription. Spawns `claude -p` with `--output-format stream-json` and `--include-partial-messages`.

Both modes produce the same stream of events to the frontend. The `ChatService` uses an **AgentAdapter** interface with two implementations:

```typescript
interface AgentAdapter {
  sendMessage(options: AgentQueryOptions): AsyncIterable<AgentEvent>;
  cancel(): void;
}

class SdkAgentAdapter implements AgentAdapter { /* uses @anthropic-ai/claude-agent-sdk */ }
class CliAgentAdapter implements AgentAdapter { /* uses Bun.spawn('claude', ...) */ }
```

**Selection logic**: Determined by `AGENT_MODE` env var:

- `sdk` -- Use the Agent SDK. Requires `ANTHROPIC_API_KEY` to be set. Fails with a clear error if missing.
- `cli` (default) -- Use Claude Code CLI. Assumes `claude` is on PATH with an active Max subscription. No API key needed.

**CLI flags used**:

- `-p` -- print mode (non-interactive)
- `--output-format stream-json` -- streaming JSON events
- `--include-partial-messages` -- real-time token streaming
- `--session-id <uuid>` -- session persistence
- `--resume <uuid>` -- resume previous session
- `--append-system-prompt <prompt>` -- project-aware context
- `--allowedTools <tools>` -- restrict tool access
- `--permission-mode bypassPermissions` -- sandboxed environment, no prompts
- `--mcp-config <json>` -- attach container exec MCP server

**SDK options used**:

- `prompt` -- the user's message
- `sessionId` / `resume` -- session management
- `allowedTools` -- tool restrictions
- `appendSystemPrompt` -- project context
- `includePartialMessages: true` -- streaming
- `mcpServers` -- attach container exec MCP server
- `permissionMode: 'bypassPermissions'`
- `maxBudgetUsd` -- cost safety limit (SDK only)

### 2. Server-Sent Events (SSE) for streaming

- SSE is unidirectional (server -> client), matching our use case
- HTTP-native, works through Next.js API proxy
- Elysia has built-in SSE support via generators
- User messages sent via regular POST requests
- Supports image attachments as base64 in the POST body

### 3. Container Sandbox MCP Server -- all tools routed through Docker

**All agent operations run inside the Docker container**, never on the host. There is no reliable way to restrict Claude's built-in file tools (`Read`, `Edit`, `Write`, `Glob`, `Grep`) to a specific directory -- the agent could use absolute paths or `../` to escape. Therefore, **all built-in tools are disallowed** and replaced by a single MCP tool that executes inside the container.

**The MCP server lives in `devable-backend`** under `src/mcp/container-sandbox-server/`. It provides one tool:

| MCP Tool | What it does | Implementation |
|----------|-------------|----------------|
| `exec_command` | Run any shell command in the container | `docker compose exec -T <service> sh -c "<command>"` |

The agent uses `exec_command` for everything -- reading files (`cat`), writing files (`cat > file`), searching (`grep`), listing (`find`/`ls`), installing packages (`npm install`), running scripts, etc. Claude is already very good at using shell commands for these operations.

**Workspace container**: Every project gets a `workspace` container that mounts the full project root at `/workspace`. This is the **only container the agent interacts with**. It has all necessary runtimes pre-installed (Node, Bun, etc.) via a `Dockerfile.workspace` in the project root. The app containers (`app`, `frontend`, `backend`) only run dev servers and pick up file/dependency changes via shared volume mounts.

If the agent needs a new runtime (e.g., Python), it edits `Dockerfile.workspace` and calls `rebuild_workspace` to rebuild the container. The user can also manage this Dockerfile directly.

**Workspace Dockerfile generation**: Each template includes a `Dockerfile.workspace.tmpl` that pre-installs the right tooling:

- `nextjs-ts`: Node 22, npm, git
- `bun-elysia-api`: Bun 1.3, Node 22, npm, git
- `fullstack`: Node 22, Bun 1.3, npm, git

**Container targeting**: Since there's only one workspace container per project, `exec_command` doesn't need a container selector. The MCP server receives a pre-validated `--workspace-container-id` at startup and targets only that container.

The MCP server uses `docker exec <workspaceContainerId> sh -c "<command>"` directly.

**Rebuild tool**: A second MCP tool, `rebuild_workspace`, allows the agent to rebuild the workspace container after Dockerfile changes. This runs on the host (it has to -- you can't rebuild a container from inside itself), but it's a controlled, specific operation -- not a general-purpose host shell. Before rebuilding, it **validates `docker-compose.yml`** to ensure no volume mounts point outside the project directory (rejects absolute paths and `../` escapes). This is a basic guard for the POC -- see "Known Limitations" below for the full discussion.

**MCP server lifecycle**: The MCP server is **not managed by our backend**. The agent runtime (SDK or CLI) spawns it as a child process and kills it when the agent turn completes:

1. User sends a message
2. `ChatService` verifies project ownership (via `ProjectService`) and looks up the workspace container ID (via `DockerService`)
3. `ChatService` calls `agentAdapter.query()` with `mcpConfig` containing the startup command + pre-validated container ID
4. The SDK/CLI spawns the MCP server process: `bun run container-sandbox-server.ts --workspace-container-id <id> --project-dir <dir>`
5. The agent uses `exec_command` / `rebuild_workspace` → SDK/CLI routes calls to the MCP server → `docker exec` → result
6. Agent turn finishes → SDK/CLI kills the MCP server process

Each active agent query has its own short-lived MCP server process. If 5 users chat simultaneously, there are 5 MCP processes, each targeting a different workspace container. They're lightweight (a Bun process piping `docker exec` commands) and automatically cleaned up.

**Security model**: The MCP server itself has no authentication or DB access. It's a thin execution layer that trusts the container ID it received at startup. Security is enforced **before** the MCP server is spawned:

- `ChatService` verifies the user owns the project (via `ProjectService`)
- `ChatService` looks up the correct workspace container ID from the DB
- The MCP server receives only that pre-validated container ID -- it cannot be redirected by the agent

**Command filtering**: Every command passes through a `CommandFilter` before execution. The initial implementation is permissive, but the interface is designed for future security rules:

- Block network attack patterns (`nmap`, `nc` to external hosts, `curl | sh`)
- Block destructive host-escape attempts
- Block crypto mining or resource abuse
- Rate-limit commands
- Log all commands for audit

If we later find the agent struggling with file operations via shell commands, we can add dedicated tools (`read_file`, `edit_file`, etc.) to the MCP server. But starting simple.

**How it's attached**: When creating an agent query, we pass the MCP server config:

```typescript
// For SDK mode
mcpServers: {
  'container-sandbox': {
    command: 'bun',
    args: ['run', '<path>/container-sandbox-server.ts',
           '--workspace-container-id', workspaceContainerId,
           '--project-dir', projectDir],
  }
}

// For CLI mode
--mcp-config '{"servers":{"container-sandbox":{"command":"bun","args":["run",
  "<path>/container-sandbox-server.ts",
  "--workspace-container-id","<id>",
  "--project-dir","<dir>"]}}}'
```

**Tool control**: ALL built-in tools that touch the filesystem or run commands are **disallowed** via `disallowedTools: ['Bash', 'Read', 'Edit', 'Write', 'Glob', 'Grep']`. The agent only has access to `exec_command` and `rebuild_workspace` via MCP. This guarantees the agent cannot access anything outside the container.

**Template changes required**: Each template's `docker-compose.yml.tmpl` needs a `workspace` service added, and each template needs a `Dockerfile.workspace.tmpl`. See Step 1b for details.

**Why not a separate repo**: The MCP server is tightly coupled to our Docker setup and project structure. It runs as a child process spawned per agent session. No need for a separate package.

### 4. Image attachments in chat

Users can drop/paste images into the chat input. Images are:

- Converted to base64 on the frontend
- Sent in the POST body alongside the text message
- Passed to the agent as image content blocks (both SDK and CLI support multimodal input)
- Displayed inline in the chat message history

This enables users to share screenshots of what they want, UI mockups, error screenshots, etc.

### 5. Message history persistence

We store chat messages in our own DB alongside the agent's session persistence:

- New `ChatMessage` Prisma model stores each user and assistant message
- Tool use events stored as structured JSON in the message content
- When resuming a session, we load message history from our DB and display it in the UI
- The agent's context is managed separately by the SDK/CLI session system

**Two independent layers:**

- **UI display** (our DB): Full conversation history -- every message ever sent. Never compacted. This is what the user sees when they refresh or come back later.
- **Agent context** (SDK/CLI session files): The agent's working memory. May be compacted over time. When we `--resume` a session, the agent gets its own persisted state back, including any compaction that happened. We never replay our DB messages into the agent -- we always resume the existing session.

**Lost session handling**: If a session can't be resumed (files deleted, corrupted, server migration, mode switch between CLI/SDK), we mark the session as `lost` in the DB and start a new session. The user is clearly informed that the previous session's agent context was lost. They can still **view** the old session's message history (read-only from our DB), but they cannot continue it. The new session starts fresh with no agent context.

**Future consideration**: Once the system's direction is clearer (production deployment model, multi-server setup, session storage strategy), revisit session management holistically -- including reconstruction from stored messages, cross-server session portability, and graceful handling of edge cases.

### 6. Cost display in the UI

Each agent response includes token usage and cost information:

- Displayed per-message (input tokens, output tokens, estimated cost)
- Running total for the session shown in the chat header
- Both SDK and CLI provide this data in their result events

### 7. User API key settings -- DEFERRED

For now, the system uses either:

- `ANTHROPIC_API_KEY` from `.env` (SDK mode)
- Max subscription via `claude` CLI (CLI mode)

User-provided API keys and a `UserSettings` table will be added in a future phase.

### 8. Agent screenshots -- DEFERRED

Playwright MCP for automated screenshots is deferred to a later phase. For now, users can take their own screenshots and drop them into the chat (see decision 4). The agent can describe what to look for in the preview URL.

---

## Step-by-Step Implementation

### Step 1: Container Sandbox MCP Server (backend)

**New files:**

- `src/mcp/container-sandbox-server/index.ts` -- Stdio MCP server entry point
- `src/mcp/container-sandbox-server/command-filter.ts` -- Command filtering interface + initial (permissive) implementation
- `src/mcp/container-sandbox-server/types.ts` -- Tool input/output types

**MCP server startup args:**

```bash
bun run src/mcp/container-sandbox-server/index.ts \
  --workspace-container-id <containerId> \
  --project-dir <projectDir>
```

**MCP server implementation:**

The server implements the MCP protocol (stdio transport) and exposes two tools:

```typescript
// Tool: exec_command
// Input: { command: string }
// Output: { stdout: string, stderr: string, exitCode: number }
//
// Implementation:
// 1. Pass command through CommandFilter (reject if blocked)
// 2. Run: docker exec <workspaceContainerId> sh -c "<command>"
// 3. Capture stdout, stderr, exit code
// 4. Return as tool result

// Tool: rebuild_workspace
// Input: {} (no parameters)
// Output: { success: boolean, message: string }
//
// Implementation:
// 1. Parse docker-compose.yml and validate all volume mounts:
//    - Reject absolute host paths (e.g., /etc:/hack)
//    - Reject paths escaping the project dir (e.g., ../../:/data)
//    - Only allow relative paths within the project directory
// 2. Run on HOST: docker compose -f <projectDir>/docker-compose.yml build workspace
// 3. Run on HOST: docker compose -f <projectDir>/docker-compose.yml up -d workspace
// 4. Update --workspace-container-id with new container's ID
// 5. Return success/failure
```

**CommandFilter interface:**

```typescript
interface CommandFilter {
  check(command: string): { allowed: boolean; reason?: string };
}

// Initial implementation: PermissiveFilter
// - Allows everything
// - Logs all commands for audit
// - Prepared for future rules:
//   - Block network attack patterns (nmap, nc to external hosts)
//   - Block curl|sh, wget|bash patterns
//   - Block rm -rf / type destructive patterns
//   - Block crypto mining commands
//   - Rate limiting
```

**Dependency**: `@modelcontextprotocol/sdk` -- Official MCP SDK for building servers

**Security layers:**

1. **Ownership check**: `ChatService` verifies the user owns the project before spawning the MCP server (using existing `ProjectService`)
2. **Container isolation**: All commands run inside the workspace Docker container
3. **Command filtering**: Every command passes through `CommandFilter` (permissive now, extensible)
4. **No built-in tools**: Agent has no access to host filesystem or shell (`Bash`, `Read`, `Edit`, `Write`, `Glob`, `Grep` all disallowed)
5. **Single container target**: Only the pre-validated workspace container can be targeted (hardcoded at MCP server startup)
6. **Audit logging**: All commands logged

**Tests:**

- `tests/mcp/container-sandbox-server/index.test.ts`
  - Verify tool listing returns `exec_command` and `rebuild_workspace`
  - Verify `exec_command` calls `docker exec` with correct workspace container ID
  - Verify stdout/stderr/exitCode captured correctly
  - Verify error handling (container not running, command fails)

- `tests/mcp/container-sandbox-server/command-filter.test.ts`
  - Verify permissive filter allows all commands (for now)
  - Verify filter interface is called before execution
  - Prepare test structure for future block rules

---

### Step 2: AgentAdapter Interface & Implementations (backend)

**New files:**

- `src/services/chat-service/AgentAdapter.ts` -- Interface definition
- `src/services/chat-service/SdkAgentAdapter.ts` -- Agent SDK implementation
- `src/services/chat-service/CliAgentAdapter.ts` -- CLI spawning implementation
- `src/services/chat-service/AgentAdapter.types.ts` -- Shared event types

**AgentAdapter interface:**

```typescript
interface AgentQueryOptions {
  prompt: string;
  sessionId?: string;
  resume?: string;
  cwd: string;
  allowedTools: string[];
  disallowedTools?: string[];
  appendSystemPrompt: string;
  mcpConfig: McpServerConfig;
  permissionMode: string;
  maxBudgetUsd?: number;
  model?: string;
  images?: Array<{ mediaType: string; base64: string }>;
}

type AgentEvent =
  | { type: 'text_delta'; text: string }
  | { type: 'tool_use_start'; tool: string; id: string; input: unknown }
  | { type: 'tool_use_end'; tool: string; id: string; output?: string }
  | { type: 'thinking'; text: string }
  | { type: 'error'; message: string; category?: string }
  | { type: 'result'; sessionId: string; result?: string; cost?: number; usage?: TokenUsage }
  | { type: 'system'; subtype: string; sessionId?: string };

interface TokenUsage {
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens?: number;
  cacheCreationTokens?: number;
}

interface AgentAdapter {
  query(options: AgentQueryOptions): AsyncIterable<AgentEvent>;
  cancel(): void;
}
```

**SdkAgentAdapter:**

- Uses `import { query } from '@anthropic-ai/claude-agent-sdk'`
- Maps SDK message types to `AgentEvent`:
  - `StreamEvent` with `content_block_delta` (text_delta) -> `text_delta`
  - `StreamEvent` with `content_block_start` (tool_use) -> `tool_use_start`
  - `AssistantMessage` -> extract tool results -> `tool_use_end`
  - `ResultMessage` -> `result`
  - `SystemMessage` -> `system`
- Passes `mcpServers` option for container exec
- Sets `ANTHROPIC_API_KEY` from env

**CliAgentAdapter:**

- Spawns `claude -p <prompt>` via `Bun.spawn()`
- Passes flags: `--output-format stream-json`, `--include-partial-messages`, `--session-id`, `--resume`, `--append-system-prompt`, `--allowedTools`, `--disallowedTools Bash`, `--permission-mode`, `--mcp-config`
- Reads stdout line-by-line, parses JSON, maps to `AgentEvent`
- `cancel()` kills the spawned process
- Images passed via `--input-format stream-json` on stdin

**Adapter selection in RunContext (DI):**

No factory class needed. `RunContext` creates the right adapter and injects it into `ChatService`:

```typescript
// In RunContext
const agentAdapter = env.config.AGENT_MODE === 'sdk'
  ? new SdkAgentAdapter(env.config.ANTHROPIC_API_KEY!)
  : new CliAgentAdapter();

this.chatService = new ChatService(db, agentAdapter, env, logger);
```

`ChatService` receives an `AgentAdapter` interface and doesn't care which implementation it is. For tests, pass a mock adapter directly -- no factory to mock.

**New env vars:**

- `ANTHROPIC_API_KEY` -- API key for SDK mode (required when `AGENT_MODE=sdk`)
- `CLAUDE_MODEL` -- Model to use (default: `claude-sonnet-4-6`)
- `AGENT_MODE` -- `sdk` or `cli` (default: `cli`)
- `AGENT_MAX_BUDGET_USD` -- Max cost per message (default: `1.0`, SDK mode only)

**Tests:**

- `tests/services/chat-service/SdkAgentAdapter.test.ts`
  - Maps SDK events to AgentEvent correctly
  - Handles errors gracefully
  - Passes correct options to SDK query

- `tests/services/chat-service/CliAgentAdapter.test.ts`
  - Spawns CLI with correct flags
  - Parses stream-json output into AgentEvents
  - Cancel kills the process
  - Handles CLI errors (non-zero exit, stderr)

---

### Step 1b: Add Workspace Container to Templates (devable-master)

Each project template needs a workspace container added to its docker-compose and a `Dockerfile.workspace`.

**New template files:**

- `src/templates/nextjs-ts/Dockerfile.workspace.tmpl`
- `src/templates/bun-elysia-api/Dockerfile.workspace.tmpl`
- `src/templates/fullstack/Dockerfile.workspace.tmpl`

**Modified template files:**

- `src/templates/nextjs-ts/docker-compose.yml.tmpl` -- add `workspace` service
- `src/templates/bun-elysia-api/docker-compose.yml.tmpl` -- add `workspace` service
- `src/templates/fullstack/docker-compose.yml.tmpl` -- add `workspace` service

**Workspace Dockerfile per template:**

```dockerfile
# nextjs-ts: Dockerfile.workspace
FROM node:22-alpine
RUN apk add --no-cache git curl
WORKDIR /workspace
CMD ["sleep", "infinity"]
```

```dockerfile
# bun-elysia-api: Dockerfile.workspace
FROM oven/bun:1.3-alpine
RUN apk add --no-cache git curl
# Also install Node for npx/prisma compatibility
COPY --from=node:22-alpine /usr/local/bin/node /usr/local/bin/node
COPY --from=node:22-alpine /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm
RUN ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx
WORKDIR /workspace
CMD ["sleep", "infinity"]
```

```dockerfile
# fullstack: Dockerfile.workspace (needs both runtimes)
FROM node:22-alpine
RUN apk add --no-cache git curl
COPY --from=oven/bun:1.3-alpine /usr/local/bin/bun /usr/local/bin/bun
WORKDIR /workspace
CMD ["sleep", "infinity"]
```

**Docker-compose workspace service** (added to each template):

```yaml
  workspace:
    build:
      context: .
      dockerfile: Dockerfile.workspace
    volumes:
      - .:/workspace
    networks:
      - default
    restart: unless-stopped
```

The workspace container mounts the entire project root at `/workspace`. It shares the same Docker network as the app containers so it can connect to databases and other services.

`CMD ["sleep", "infinity"]` keeps the container running so `docker exec` can be used at any time.

**Update template manifests**: Add `Dockerfile.workspace.tmpl` to the `files` array in each `template.json`.

**Update ProjectService**: When creating container records after project start, also create a record for the workspace container (type: `workspace`). The workspace container ID is needed by the MCP server.

**Tests:**

- Verify workspace service is present in generated docker-compose for each template
- Verify Dockerfile.workspace has correct runtimes per template
- Verify workspace container starts and can execute commands
- Verify workspace container can access project files at `/workspace`
- Verify workspace container shares network with app containers

---

### Step 3: ChatService & ChatSessionRepository (backend)

**New files:**

- `src/services/chat-service/ChatService.ts` -- Core chat orchestration
- `src/services/chat-service/ChatService.types.ts` -- Service-level types
- `src/services/chat-service/ChatService.utils.ts` -- Utility functions (including `buildAgentPrompt`)
- `src/db/ChatSessionRepository.ts` -- DB access for chat sessions
- `src/db/ChatMessageRepository.ts` -- DB access for message history

**New Prisma model** (add to existing schema):

```prisma
model ChatMessage {
  id        String   @id @default(uuid())
  sessionId String
  role      String   @db.VarChar(50)   // 'user' | 'assistant' | 'system'
  content   String   @db.Text          // Text content or JSON for structured content
  images    Json?                       // Array of image references (if any)
  toolUses  Json?                       // Array of tool use records (if assistant message)
  usage     Json?                       // Token usage for this message (if assistant)
  cost      Float?                      // Cost in USD for this message (if assistant)
  createdAt DateTime @default(now())

  session ChatSession @relation(fields: [sessionId], references: [id], onDelete: Cascade)

  @@map("chat_messages")
}
```

Update `ChatSession` model to add the relation:

```prisma
model ChatSession {
  // ... existing fields ...
  messages ChatMessage[]
}
```

**ChatSessionRepository methods:**

- `createAsync(data: { projectId, sessionName })` -- Create session record
- `findByIdAsync(id)` -- Get session by ID
- `findByProjectIdAsync(projectId)` -- List sessions for a project (ordered by lastActiveAt desc)
- `updateLastActiveAsync(id)` -- Update `lastActiveAt` timestamp
- `deleteAsync(id)` -- Delete session (cascade deletes messages)

**ChatMessageRepository methods:**

- `createAsync(data: { sessionId, role, content, images?, toolUses?, usage?, cost? })` -- Store a message
- `findBySessionIdAsync(sessionId)` -- Get all messages for a session (ordered by createdAt asc)
- `deleteBySessionIdAsync(sessionId)` -- Delete all messages for a session

**ChatService:**

```typescript
class ChatService {
  constructor(
    private db: DB,
    private agentAdapter: AgentAdapter,
    private env: Env,
    private logger: Logger,
  ) {}

  async createSessionAsync(projectId: string, userId: string): Promise<ChatSession>
  async *sendMessageAsync(sessionId: string, projectId: string, userId: string, message: string, images?: ImageAttachment[]): AsyncGenerator<AgentEvent>
  async listSessionsAsync(projectId: string, userId: string): Promise<ChatSession[]>
  async getSessionMessagesAsync(sessionId: string, userId: string): Promise<ChatMessage[]>
  async cancelAsync(sessionId: string): void
}
```

**sendMessageAsync flow:**

1. Verify project ownership
2. Store user message in DB (`ChatMessage` with role='user')
3. Update session `lastActiveAt`
4. Build system prompt via `buildAgentPrompt()` utility
5. Build MCP config for container exec server
6. Call `agentAdapter.query()` with all options
7. Iterate events:
   - Yield each `AgentEvent` to caller (for SSE streaming)
   - Accumulate text deltas and tool uses for the assistant message
8. On completion (`result` event): store assistant message in DB with accumulated content, tool uses, usage, and cost
9. On error: store error message, yield error event

`buildAgentPrompt()` is a utility function in `ChatService.utils.ts`. It generates a context-aware system prompt per project using simple string building (not a template engine -- these are runtime-generated, not disk-based templates). See the system prompt template in the "Agent System Prompt" section below.

**Wire into DI:**

- Add `chatSessionRepository` and `chatMessageRepository` to `DB`
- Add `agentAdapter` and `chatService` to `RunContext`
- Add new env vars to `Env.ts`

**Tests:**

- `tests/services/chat-service/ChatService.test.ts`
  - Create session (happy path, project not found, not owner)
  - Send message (mocked adapter, verify events yielded, messages stored in DB)
  - Resume session (verify adapter called with resume option)
  - Cancel (verify adapter.cancel called)
  - List sessions
  - Get session messages

- Tests for `buildAgentPrompt()` in `tests/services/chat-service/ChatService.utils.test.ts`
  - Build prompt for each template type
  - Verify conditional sections (database, frontend, bun vs node)
  - Verify project metadata included

- `tests/db/ChatSessionRepository.test.ts` -- CRUD operations
- `tests/db/ChatMessageRepository.test.ts` -- CRUD operations

---

### Step 4: Chat API Routes (backend)

**New files:**

- `src/routes/chat-routes.ts`

**Modify:**

- `src/routes.ts` -- Register chat routes under `/v1/projects/:id/chat`

**Endpoints:**

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/v1/projects/:id/chat/sessions` | List chat sessions for a project |
| `POST` | `/v1/projects/:id/chat/sessions` | Create a new chat session |
| `DELETE` | `/v1/projects/:id/chat/sessions/:sessionId` | Delete a chat session |
| `GET` | `/v1/projects/:id/chat/sessions/:sessionId/messages` | Get message history |
| `POST` | `/v1/projects/:id/chat/sessions/:sessionId/messages` | Send a message (returns SSE stream) |
| `POST` | `/v1/projects/:id/chat/sessions/:sessionId/cancel` | Cancel a running agent query |

**SSE streaming endpoint** (`POST /v1/projects/:id/chat/sessions/:sessionId/messages`):

Returns `Content-Type: text/event-stream`. Each SSE event contains a JSON `AgentEvent`:

```typescript
// Event types sent over SSE:
type ChatStreamEvent =
  | { type: 'text_delta'; text: string }
  | { type: 'tool_use_start'; tool: string; id: string; input: unknown }
  | { type: 'tool_use_end'; tool: string; id: string; output?: string }
  | { type: 'thinking'; text: string }
  | { type: 'error'; message: string }
  | { type: 'result'; sessionId: string; usage?: TokenUsage; cost?: number }
```

**Request body for POST /v1/projects/:id/chat/sessions/:sessionId/messages:**

```typescript
{
  message: string;
  images?: Array<{
    mediaType: 'image/png' | 'image/jpeg' | 'image/gif' | 'image/webp';
    base64: string;
  }>;
}
```

**API schemas (TypeBox):**

- `CreateChatSessionBody`: `{ name?: string }`
- `SendMessageBody`: `{ message: string, images?: ImageAttachment[] }`
- `ChatSessionResponse`: `{ id, projectId, sessionName, createdAt, lastActiveAt }`
- `ChatMessageResponse`: `{ id, role, content, images?, toolUses?, usage?, cost?, createdAt }`

---

### Step 5: Frontend API Client (frontend)

The chat endpoints call the backend API **directly** -- no Next.js proxy routes. The backend already handles auth (Clerk JWT) and CORS. The proxy pattern from Phase 1 adds unnecessary boilerplate, latency, and maintenance for no real benefit. SSE works fine cross-origin with `fetch()`.

**Modify:**

- `src/lib/api-client.ts` -- Add chat methods that call backend directly
- `src/types/api.ts` -- Add chat types
- `src/lib/env.ts` -- Ensure `NEXT_PUBLIC_API_URL` is available for direct backend calls

**New api-client methods:**

- `fetchChatSessions(getToken, projectId)` -- GET sessions
- `createChatSession(getToken, projectId, name?)` -- POST create session
- `deleteChatSession(getToken, projectId, sessionId)` -- DELETE session
- `fetchChatMessages(getToken, projectId, sessionId)` -- GET message history
- `sendChatMessage(getToken, projectId, sessionId, message, images?, onEvent)` -- POST with SSE streaming
- `cancelChatMessage(getToken, projectId, sessionId)` -- POST cancel

**SSE handling pattern:**

```typescript
export async function sendChatMessage(
  getToken: () => Promise<string | null>,
  projectId: string,
  sessionId: string,
  message: string,
  images: ImageAttachment[] | undefined,
  onEvent: (event: ChatStreamEvent) => void,
): Promise<void> {
  const token = await getToken();
  const apiUrl = process.env.NEXT_PUBLIC_API_URL;
  const response = await fetch(
    `${apiUrl}/v1/projects/${projectId}/chat/sessions/${sessionId}/messages`,
    {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ message, images }),
    },
  );

  const reader = response.body!.getReader();
  const decoder = new TextDecoder();
  let buffer = '';

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop()!;
    for (const line of lines) {
      if (line.startsWith('data: ')) {
        const event = JSON.parse(line.slice(6));
        onEvent(event);
      }
    }
  }
}
```

**Future cleanup**: The existing Phase 1 proxy routes (`src/app/api/projects/`, `src/app/api/announcements/`) should be migrated to direct backend calls as well, removing the proxy layer entirely.

---

### Step 6: Project Editor Page with Chat Panel (frontend)

**New files:**

- `src/app/project/[id]/page.tsx` -- Project editor page (server component)
- `src/app/project/[id]/layout.tsx` -- Layout with auth protection
- `src/components/pages/ProjectEditorPage/ProjectEditorPage.tsx` -- Main editor page component
- `src/components/pages/ProjectEditorPage/ProjectEditorPage.css`
- `src/components/ChatPanel/ChatPanel.tsx` -- Chat panel with message list + input
- `src/components/ChatPanel/ChatPanel.css`
- `src/components/ChatPanel/ChatPanel.types.ts`
- `src/components/ChatPanel/ChatPanel.constants.ts`
- `src/components/ChatPanel/ChatMessage/ChatMessage.tsx` -- Single message (user or assistant)
- `src/components/ChatPanel/ChatMessage/ChatMessage.css`
- `src/components/ChatPanel/ChatInput/ChatInput.tsx` -- Message input with send button + image drop
- `src/components/ChatPanel/ChatInput/ChatInput.css`
- `src/components/ChatPanel/ToolUseIndicator/ToolUseIndicator.tsx` -- Shows what tool the agent is using
- `src/components/ChatPanel/ToolUseIndicator/ToolUseIndicator.css`
- `src/components/ChatPanel/SessionSelector/SessionSelector.tsx` -- Session picker dropdown
- `src/components/ChatPanel/SessionSelector/SessionSelector.css`
- `src/components/ChatPanel/CostDisplay/CostDisplay.tsx` -- Token/cost info per message and session total
- `src/components/ChatPanel/CostDisplay/CostDisplay.css`
- `src/components/PreviewPanel/PreviewPanel.tsx` -- Iframe showing project preview
- `src/components/PreviewPanel/PreviewPanel.css`

**Modify:**

- `src/components/ProjectCard/ProjectCard.tsx` -- Make project name a link to `/project/{id}`

**Page layout:**

```text
+--------------------------------------------------------------+
|  Header: [<- Back]  Project Name  |  Status Badge  |  Cost   |
+--------------------------------------------------------------+
|  Session Selector: [Session 1 v] [+ New]                     |
+-------------------------------+------------------------------+
|                               |                              |
|   Chat Panel (left, ~40%)     |   Preview Panel (right, ~60%)|
|                               |                              |
|   [Assistant message]         |   [iframe: slug.localhost]   |
|     [Tool use: Edit file.tsx] |                              |
|     [cost: 0.02 USD]         |                              |
|                               |                              |
|   [User message]              |   [Refresh] [Open in tab]   |
|     [attached image]          |                              |
|                               |                              |
|   [Assistant streaming...]    |                              |
|                               |                              |
|   +-------------------------+ |                              |
|   | Type a message...  [📎] | |                              |
|   | [Send]                  | |                              |
|   +-------------------------+ |                              |
+-------------------------------+------------------------------+
```

**Chat Panel state management:**

```typescript
const [messages, setMessages] = useState<DisplayMessage[]>([]);
const [isStreaming, setIsStreaming] = useState(false);
const [currentSessionId, setCurrentSessionId] = useState<string | null>(null);
const [sessions, setSessions] = useState<ChatSession[]>([]);
const [sessionCost, setSessionCost] = useState(0);

// On page load:
// 1. Fetch sessions for this project
// 2. If sessions exist, select most recent, load its messages from DB
// 3. Display message history

// On send message:
// 1. Add user message to local state (optimistic)
// 2. If no session exists, create one first
// 3. Set isStreaming = true
// 4. Call sendChatMessage() with onEvent callback:
//    - text_delta -> append to current streaming assistant message
//    - tool_use_start -> add tool indicator to current message
//    - tool_use_end -> update tool indicator with result
//    - result -> finalize message, update cost, set isStreaming = false
//    - error -> show error, set isStreaming = false
// 5. On stream complete, auto-refresh preview iframe

// On session switch:
// 1. Fetch messages for selected session from DB
// 2. Replace messages in state
```

**ChatMessage component:**

- User messages: right-aligned, colored background, optional image thumbnails
- Assistant messages: left-aligned, rendered as markdown (need a markdown renderer)
- Tool use blocks: collapsible sections showing tool name + input/output summary
- Per-message cost: small text showing tokens and cost (for assistant messages)
- Streaming indicator: animated cursor/dots while streaming

**ChatInput component:**

- Textarea with auto-resize
- Send button (disabled when empty or streaming)
- Image attachment: drag-and-drop zone + paste support + file picker button (📎)
- Image preview thumbnails before sending
- Enter to send, Shift+Enter for newline

**Preview Panel:**

- Iframe pointing to `{slug}.localhost:8888`
- Refresh button (manual reload)
- "Open in new tab" link
- Auto-refresh toggle (off by default) -- reloads iframe after each agent turn completes. Useful for projects without hot reload.

**Markdown rendering:**

We need a lightweight markdown renderer for assistant messages. Options:

- `react-markdown` -- popular, supports GFM, code highlighting
- `marked` + `DOMPurify` -- lighter, but more manual

Recommend `react-markdown` with `remark-gfm` for GitHub-flavored markdown.

**New dependencies (frontend):**

- `react-markdown` -- Markdown rendering
- `remark-gfm` -- GitHub-flavored markdown support (tables, strikethrough, etc.)

---

### Step 7: Agent System Prompt & Tool Configuration (backend)

**Function:** `buildAgentPrompt()` in `src/services/chat-service/ChatService.utils.ts` (created in Step 3)

**System prompt template** (generated per project via string building):

The prompt describes the project as it **currently exists**, not as it was originally scaffolded. The starter template and design theme are just starting points -- the user may have changed anything since then.

```markdown
# Project Context

You are an AI development assistant working on "{{PROJECT_NAME}}".

## Project Details

- **Preview URL**: {{PREVIEW_URL}}

## Working Directory

Your working directory is `/workspace` (the project root). The project structure is:

{{DIRECTORY_TREE}}

## Development Guidelines

- Read the existing code before making changes -- understand the patterns in use
- Follow the existing project patterns, file structure, and language choices
- If the project has CSS custom properties (check `globals.css`), use them instead of hardcoding values
- When creating new React components, create a `.tsx` file and a `.css` file in the same directory

## Running Commands

All commands run inside the Docker container via the `exec_command` tool.
The dev server is already running -- you do not need to start it.

Check `package.json` to determine the package manager and available scripts.

## Important Rules

- Do NOT modify `docker-compose.yml` unless explicitly asked to add a new service
- Do NOT modify `.env` without telling the user
- Use the `exec_command` tool for all shell commands
- After making changes, tell the user what to look for in the preview
- If you encounter an error, explain it clearly and suggest a fix
```

**Variables resolved at runtime:**

| Variable | Source |
|----------|--------|
| `PROJECT_NAME` | `project.name` |
| `PREVIEW_URL` | `{slug}.localhost:8888` |
| `DIRECTORY_TREE` | `exec_command('find . -maxdepth 3 -not -path ./node_modules/*')` or similar |

The prompt is intentionally minimal and avoids assumptions about the project's current state. The agent should read the actual code (`package.json`, `globals.css`, `prisma/schema.prisma`, etc.) to understand what it's working with.

**Tool configuration:**

All templates get the same tool setup:

- **Disallowed built-in tools**: `Bash`, `Read`, `Edit`, `Write`, `Glob`, `Grep` -- prevents any host filesystem or shell access
- **MCP tool (via container-sandbox server)**: `exec_command` -- runs any shell command inside the Docker container

The agent uses `exec_command` for everything: file operations via `cat`/`grep`/`find`/`sed`, package installs, script execution, etc.

---

### Step 8: Tests

Write tests alongside each step (TDD per project rules). Summary of all test files:

**Backend:**

- `tests/mcp/container-sandbox-server/index.test.ts` -- MCP server tool listing, exec_command, error handling
- `tests/services/chat-service/SdkAgentAdapter.test.ts` -- SDK event mapping
- `tests/services/chat-service/CliAgentAdapter.test.ts` -- CLI spawning, stream parsing
- `tests/services/chat-service/ChatService.test.ts` -- Session CRUD, message flow, error handling
- `tests/services/chat-service/ChatService.utils.test.ts` -- `buildAgentPrompt()` for each template type
- `tests/db/ChatSessionRepository.test.ts` -- CRUD
- `tests/db/ChatMessageRepository.test.ts` -- CRUD, findBySessionId

**Frontend:**

- `src/components/ChatPanel/ChatPanel.test.tsx` -- Message display, send flow, streaming, session switching
- `src/components/ChatPanel/ChatInput/ChatInput.test.tsx` -- Input, image attachment, send button states
- `src/components/ChatPanel/ChatMessage/ChatMessage.test.tsx` -- User/assistant rendering, markdown, tool uses, cost
- `src/components/ChatPanel/ToolUseIndicator/ToolUseIndicator.test.tsx` -- Collapsible tool display
- `src/components/ChatPanel/SessionSelector/SessionSelector.test.tsx` -- Session list, new session, switch
- `src/components/ChatPanel/CostDisplay/CostDisplay.test.tsx` -- Token/cost formatting
- `src/components/PreviewPanel/PreviewPanel.test.tsx` -- Iframe, refresh, open in tab
- `src/components/pages/ProjectEditorPage/ProjectEditorPage.test.tsx` -- Layout, data loading

---

### Step 9: Integration Testing & Verification

**Manual E2E flow:**

1. Start infrastructure (`src/scripts/dev-start.sh`)
2. Start backend + frontend
3. Create a project (e.g., nextjs-ts with clean theme)
4. Click project to open editor page
5. Verify: chat panel and preview iframe load correctly
6. Type "Create a hello world page with a counter button"
7. Verify:
   - Streaming text appears in chat
   - Tool use indicators show (Read, Edit of project files)
   - `exec_command` used for any installs (shown as tool use)
   - Cost/token info displayed on the response
   - Preview iframe shows the result after refresh
8. Send follow-up: "Change the button color to red and make it bigger"
9. Verify agent modifies correct file, preview updates
10. Drop a screenshot into chat: "Make it look like this"
11. Verify agent receives the image and responds appropriately
12. Reload page -- verify message history loads from DB
13. Create new session -- verify clean conversation starts
14. Switch back to old session -- verify history loads
15. Test with bun-elysia-api template (no frontend, API-only)
16. Test with fullstack template (frontend + backend)
17. Test cancel button while agent is streaming
18. Verify session cost tracking across multiple messages
19. Test both SDK mode (with API key) and CLI mode (Max subscription)

---

## Implementation Order

```text
Step 1  (Container Sandbox MCP)    -- sandbox first, no dependencies
  |
Step 1b (Workspace in templates)   -- MCP needs a workspace container to target
  |
Step 2  (AgentAdapter interface)   -- core abstraction for SDK + CLI
  |
Step 3  (ChatService + DB repos)   -- business logic + persistence
  |
Step 4 (Chat API routes)          -- expose to frontend
  |
Step 5 (Frontend proxy + client)  -- connect frontend to backend
  |
Step 6 (Editor page + UI)         -- the main user experience
  |
Step 7 (System prompt)            -- refine after initial testing
  |
Step 8 (Tests)                    -- written alongside each step
  |
Step 9 (Integration testing)      -- final verification
```

Steps 1-2 are foundational. Step 3 ties them together. Steps 4-5 are the API layer. Step 6 is the big UI step. Step 7 is iterative refinement. Tests are written alongside each step.

---

## Dependencies to Install

**Backend (`apps/devable-backend`):**

- `@anthropic-ai/claude-agent-sdk` -- Agent SDK for programmatic Claude integration
- `@modelcontextprotocol/sdk` -- MCP SDK for building the container exec server

**Frontend (`apps/devable-frontend`):**

- `react-markdown` -- Markdown rendering for assistant messages
- `remark-gfm` -- GitHub-flavored markdown plugin

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Agent SDK not compatible with Bun | Test early in Step 2. CLI adapter is the fallback. |
| MCP SDK not compatible with Bun | Test in Step 1. Fallback: raw stdio JSON protocol (MCP is simple). |
| SSE cross-origin issues | Unlikely -- backend CORS is configured and we use `fetch()` not `EventSource`. |
| Agent accessing host filesystem | All built-in file/bash tools disallowed. Everything routed through container sandbox MCP. |
| Cost runaway | `maxBudgetUsd` per message (SDK), monitor in UI, session totals. |
| CLI mode doesn't support all SDK features | Document differences. Core features (streaming, tools, sessions) work in both. |
| Large images in chat slow down requests | Resize/compress on frontend before base64 encoding. Set max image size. |
| Session files grow large over time | Not a concern for POC. Production: periodic cleanup, message compaction. |

---

## Known Limitations (POC)

- **Docker configuration as an attack vector**: Since the agent can edit files inside the workspace container (including `docker-compose.yml` and Dockerfiles), there are several ways it could access host files or run arbitrary host-side code:
  - **Volume mount escape**: `docker-compose.yml` could map host directories (e.g., `volumes: - /etc:/hack`). The `rebuild_workspace` tool validates volume mounts before rebuilding (rejects absolute paths and `../` escapes), but this is a basic guard.
  - **Build context escape**: Changing the `context:` in docker-compose to `../../` or `/` would let `COPY`/`ADD` in Dockerfiles access files outside the project.
  - **Dockerfile `ADD <url>`**: Can download arbitrary content from the internet during build.
  - **Malicious base images**: `FROM malicious-image:latest` could run anything.
  - For the POC running locally, these are acceptable risks. For production, the proper solution is **Docker-in-Docker** (or Firecracker/sandboxed VMs) so the "host" the agent can escape to is itself an isolated container with no access to the real host. Alternatively, don't let the agent edit Docker config files directly -- provide a controlled API that validates and applies changes.

- **No MCP server authentication**: The MCP server runs as a local stdio child process. There's no auth on the MCP server itself -- security relies on `ChatService` verifying ownership before spawning it. This is fine for the POC but needs proper authentication if the MCP server is ever exposed over HTTP for remote access (see "Remote MCP access" in Deferred Features).

---

## Deferred Features (future phases)

- **Agent screenshots via Playwright MCP**: Automated screenshot capability for the agent to verify its own work. Very useful -- plan to add in a near-future phase.
- **User-provided API keys**: `UserSettings` table with encrypted API key storage. Allows users to bring their own key when deployed.
- **Multiple chat panels / split view**: Allow side-by-side conversations or chat + code editor.
- **Message search**: Full-text search across chat history.
- **Conversation export**: Download chat history as markdown.

- **Remote MCP access for local Claude Code**: The container sandbox MCP server currently uses stdio transport (spawned as a child process). Adding an HTTP/SSE transport would allow users to connect their local Claude Code (with Max subscription) to a remote Devable project. The MCP server already handles ownership verification, command filtering, and container isolation -- so the security model works for remote access out of the box. This would let power users use their own Claude Code setup while working on Devable-hosted projects. **Note**: Remote access requires proper authentication on the MCP server itself (e.g., Clerk JWT validation, API tokens, or OAuth). The current POC has no MCP-level auth since it runs locally as a stdio child process -- the trust boundary is the host machine. For production with HTTP transport, the MCP server must authenticate every request before executing commands.

- **Shared conversation context across local and web agents**: When a user works on a project via local Claude Code + remote MCP, the conversation lives locally and is invisible to the web UI (and vice versa). To bridge this gap, we could:
  - Expose a `conversation_history` MCP resource so local Claude Code can read the web UI's chat history and understand prior context.
  - Add a `log_message` MCP tool so local Claude Code sessions can write to the shared `ChatMessage` table, contributing to the shared history.
  - This way both local and web agents share the same **code** (same container) and can at least *read* each other's conversation context, even if full session continuity across clients isn't possible.

- **Git repositories per project with branch isolation**: Each project should have an actual git repository initialized. When multiple agents (or a mix of web UI agents and local Claude Code sessions) work on the same project, each agent session should work on its own branch to avoid conflicts. The flow would be:
  - Project creation initializes a git repo with an initial commit
  - Each new agent session creates a feature branch (e.g., `agent/<sessionId>`)
  - When the user approves changes, the branch is merged to main
  - Conflicts are surfaced to the user for resolution
  - This also provides version history and rollback capability for free
  - The web UI could show a branch/commit timeline alongside the chat
