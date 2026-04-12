# Phase 4: IDE Experience -- Detailed Plan

> **Status**: Completed
> **Created**: 2026-04-11
> **Completed**: 2026-04-12
> **Parent plan**: `2026-03-28-20-30-devable-grand-plan.md`
>
> ### Deviations discovered during implementation
>
> - **No directory exclusions in file tree**: The plan specified excluding `node_modules`, `.git`, `.next`, `dist`, `build`, `.cache` from listings. Changed to show all files/directories (only OS system files like `.DS_Store` excluded). Instead, directories with >50 items are returned with `lazy: true` and no children — the frontend fetches their contents on demand when the user clicks to expand. This requires a `path` query param on `GET /files` for subdirectory listings, and a `lazy` boolean flag on `FileTreeEntry`.
> - **react-resizable-panels v4 API**: The plan used `PanelGroup` and `PanelResizeHandle` names, but v4 exports `Group` (with `orientation` prop) and `Separator`. Imports aliased accordingly.
> - **Context menu for file CRUD**: The plan mentioned "context menu or action buttons" for delete/rename in the file tree. Implemented as a right-click context menu on each FileTreeNode with Rename, Delete (and New File/New Folder for directories).
> - **File tree sidebar collapse**: Added a toggle button in the Code view toolbar to show/hide the file tree panel.
> - **Start/stop/restart DB status updates**: The Phase 1 routes didn't update project status in DB after container actions. Moved logic to `ProjectService.startContainersAsync`/`stopContainersAsync`/`restartContainersAsync` that handle both Docker + DB status.
> - **Chat message race condition**: When creating a new session, the `currentSessionId` change triggered a message fetch from DB that overwrote the local streaming state (assistant message not saved to DB yet). Fixed with a `skipNextMessageFetchRef` guard.
> - **Logs route split**: The plan had a single `/logs` route as a generator. Elysia wraps all generator yields in SSE even for non-follow requests. Split into `/logs` (regular JSON) and `/logs/stream` (SSE generator).
> - **Elapsed timer moved to message footer**: The plan placed the elapsed timer in the chat panel header. Moved it to the assistant message footer so each message shows its own elapsed time (e.g., "4s $0.06"), persisting for the session. The timer ticks during streaming and shows the final time after completion.
> - **Monaco Cmd+S stale closure**: The `addCommand` keybinding captured the save handler at mount time. Fixed by using a ref that always points to the latest handler.
> - **Editor file reload after agent changes**: The plan described reloading on `lastAgentFileChange` events, but this was unreliable due to hot-reload killing stream handlers. Simplified to: when `isAgentStreaming` transitions from true to false, reload the active file from disk.
> - **Tool use notification timing**: Changed from notifying on `tool_use_start` (file not written yet) to `tool_use_end` (file written) for file change detection.
> - **Rebuild status polling not implemented**: The plan specified polling every 3s while status is "rebuilding". Not implemented in the POC — the UI requires a manual page reload to see the final status. Tracked in FUTURE_CONSIDERATIONS.md.
> - **Automated frontend tests deferred**: The plan specified component tests for all new frontend components. Only backend tests were written (168 tests). Frontend component tests are deferred — integration testing was done manually via Chrome DevTools.

---

## Context

### What already exists

Phase 1-3 delivered:

- **Project lifecycle**: Full create/delete/start/stop orchestration, Caddy routing, port allocation
- **Templates**: 3 disk-based templates (nextjs-ts, bun-elysia-api, fullstack) with workspace containers
- **Design themes**: 3 CSS themes (clean, bold, soft)
- **Dashboard UI**: Project list, create dialog, delete confirmation, start/stop/restart
- **Chat with AI agent**: Dual-mode (CLI/SDK) via AgentAdapter, SSE streaming, MCP container sandbox
- **Preview panel**: Iframe-based at `{slug}.localhost:8888`
- **Chat panel**: Message list, streaming, tool use indicators, session selector, cost display, image attachments
- **Backend services**: ProjectService, ProjectFileService, DockerService, CaddyService, ChatService -- all via RunContext DI
- **DB models**: Project, ProjectContainer, ChatSession, ChatMessage

### What Phase 4 delivers

Transform the basic 2-column chat+preview layout into a full IDE experience. By the end, a user can:

1. See a 2-pane layout: chat (left) + main area (right) with a tab bar to switch views
2. Switch between views: Code, Preview, Logs, or Split (code + preview side-by-side)
3. Browse the project's file tree with expand/collapse in the Code view
4. Open files in a tabbed Monaco editor with syntax highlighting
5. Edit files directly and save to disk (Ctrl+S)
6. Create, rename, delete, and move (drag-and-drop) files and folders
7. See warnings when modifying infrastructure files (docker-compose.yml, Dockerfile*, .env)
8. See a notification when the agent modifies an open file
9. View container logs in the Logs view with service filtering and follow mode
10. Rebuild containers after editing Dockerfiles (async with status polling)
11. See chat messages and tool uses in correct chronological order
12. See an elapsed time indicator while waiting for agent responses
13. Toggle auto-refresh on the preview panel

### Learnings from previous phases

- **Elysia SSE**: Auto-wraps generator yields in `data: ...\n\n` -- yield raw JSON strings
- **SSE keepalive**: Required for long operations (15s interval)
- **Frontend API pattern**: Use `{ success, data, statusCode }` result objects, not thrown errors
- **Bun-native file I/O**: Prefer `Bun.file().text()` / `Bun.write()` over `node:fs/promises` for read/write
- **Types in dedicated files**: All interfaces/types go in `.types.ts` files
- **Focused try-catch**: Only wrap the specific throwable operation
- **Async postfix**: All async functions must have `Async` suffix
- **Component structure**: Each component in its own folder with `.tsx` + `.css`
- **CSS**: Plain CSS with native nesting, custom properties from `globals.css`, mobile-first, hover in `@media (hover: hover)`
- **Phase 3 deferred frontend tests**: Component tests were skipped -- this phase should include them
- **Tech debt**: Phase 1 proxy routes still exist but Phase 3+ uses direct backend calls

---

## Design Decisions

### 1. Tab-based main area with resizable chat/main split

The layout is a 2-pane split: chat (left) + main area (right), with a resizable divider between them. The main area has a horizontal tab bar at the top with four views: **Code**, **Preview**, **Logs**, and **Split** (code + preview side-by-side). Only one view is active at a time. This is simpler than a 3-pane layout and lets each view use the full main area width.

`react-resizable-panels` (~8KB gzipped) handles the chat/main divider and the Split view's code/preview split. Mature, accessible, SSR-safe.

### 2. Code editor: `@monaco-editor/react`

The standard React wrapper for Monaco editor. Loads Monaco from CDN by default (~3MB). No lighter alternative provides full syntax highlighting, multi-tab, and language services.

### 3. Read-write editor with always-dark theme

Users should be able to make quick edits directly (fix a typo, adjust CSS) without waiting for the agent. This is a core differentiator of being "developer-friendly." Save via Ctrl+S writes to disk through a PUT API. The editor always uses a dark theme regardless of app light/dark mode -- most developers prefer dark editors, and it visually separates the code area.

### 4. Collapsible file tree sidebar

The file tree is a collapsible sidebar (like VS Code) that can be toggled open/closed. Saves space when not needed. Toggle via a button in the Code view header area.

### 5. File change detection: agent events + polling fallback

The chat SSE stream already emits `tool_use_start`/`tool_use_end` events. The frontend can extract file paths from tool use input to know which files changed. A lightweight polling mechanism (file tree with timestamps, every 10s while agent is active) catches changes missed by events (e.g., `exec_command` that creates files).

### 6. Logs: SSE streaming

Use `docker compose logs -f` with SSE, following the same generator pattern as chat routes. No WebSocket -- stick with existing SSE infrastructure.

### 7. File APIs: direct host access via Bun

The backend reads files directly from `user-projects/` using `Bun.file()`. No need to exec into containers. Path traversal protection is critical.

### 8. ProjectEditorContext for shared state

A React context at the `ProjectEditorPage` level to share state between panels without prop-drilling: active view, open files, selected file, streaming state, last agent file change.

---

## New Dependencies

**Frontend (`apps/devable-frontend`):**

| Package | Size | Justification |
|---------|------|---------------|
| `react-resizable-panels` | ~8KB gz | Split-pane layout with drag handles |
| `@monaco-editor/react` | ~3MB (CDN) | Code editor with syntax highlighting |

**Backend (`apps/devable-backend`):**

No new dependencies. File operations use `Bun.file()` and `node:fs/promises`.

---

## Step-by-Step Implementation

### Step 1: Backend -- File Browsing Service & APIs

**Why**: The file tree and code editor need backend APIs to list, read, and write project files. This must come first since frontend components depend on it.

**New service: `src/services/project-file-browsing-service/`**

- `ProjectFileBrowsingService.ts` -- list directory tree, read file content, write file content
- `ProjectFileBrowsingService.types.ts` -- type definitions

Key types:

```typescript
interface FileTreeEntry {
  name: string;
  path: string;         // relative to project root
  type: 'file' | 'directory';
  size?: number;        // bytes, files only
  modifiedAt?: string;  // ISO timestamp
  children?: FileTreeEntry[];
}

type ListFilesResult =
  | { success: true; tree: FileTreeEntry[] }
  | { success: false; error: string };

type ReadFileResult =
  | { success: true; content: string; modifiedAt: string }
  | { success: false; error: string };

type WriteFileResult =
  | { success: true; modifiedAt: string }
  | { success: false; error: string };

type CreateFileResult =
  | { success: true; path: string }
  | { success: false; error: string };

type DeleteFileResult =
  | { success: true }
  | { success: false; error: string };

type RenameFileResult =
  | { success: true; newPath: string }
  | { success: false; error: string };
```

**Security -- path traversal prevention** (critical):

```typescript
function resolveAndValidatePath(projectDir: string, relativePath: string): string | null {
  const resolved = path.resolve(projectDir, relativePath);
  if (!resolved.startsWith(projectDir + path.sep) && resolved !== projectDir) {
    return null; // traversal attempt
  }
  return resolved;
}
```

- Configurable ignore list: `node_modules`, `.git`, `.next`, `dist`, `build`, `.cache`
- Max file size for reads: 1MB
- Binary file detection by extension (`.png`, `.jpg`, `.woff`, `.ico`, `.zip`, etc.)

**New route file: `src/routes/file-routes.ts`**

| Method | Path | Description |
|--------|------|-------------|
| GET | `/v1/projects/:id/files` | List file tree (query: `depth`, default 3) |
| GET | `/v1/projects/:id/files/*` | Read file content (wildcard captures path) |
| PUT | `/v1/projects/:id/files/*` | Write file content (body: `{ content: string }`) |
| POST | `/v1/projects/:id/files` | Create file or folder (body: `{ path, type: 'file'\|'directory', content? }`) |
| DELETE | `/v1/projects/:id/files/*` | Delete file or folder |
| PATCH | `/v1/projects/:id/files/*` | Rename/move (body: `{ newPath: string }`) |

All endpoints verify project ownership first (same pattern as existing routes).

**Files to create:**
- `apps/devable-backend/src/services/project-file-browsing-service/ProjectFileBrowsingService.ts`
- `apps/devable-backend/src/services/project-file-browsing-service/ProjectFileBrowsingService.types.ts`
- `apps/devable-backend/src/routes/file-routes.ts`
- `apps/devable-backend/tests/services/project-file-browsing-service/ProjectFileBrowsingService.test.ts`

**Files to modify:**
- `apps/devable-backend/src/lib/api-schemas.ts` -- add file schemas
- `apps/devable-backend/src/lib/RunContext.ts` -- add service to DI
- `apps/devable-backend/src/routes.ts` -- register file routes

---

### Step 1b: Backend -- Async Rebuild Containers Endpoint

**Why**: Users need to rebuild containers after editing Dockerfiles or docker-compose.yml. Rebuilds can take 30s to several minutes, so the endpoint must be non-blocking.

**New route in `project-routes.ts`:**

| Method | Path | Description |
|--------|------|-------------|
| POST | `/v1/projects/:id/rebuild` | Trigger async rebuild, returns `202 Accepted` immediately |

**Flow:**

1. POST `/rebuild` sets project status to `rebuilding` in DB, returns `202`
2. Backend runs `docker compose up -d --build` in the background (fire-and-forget)
3. On success: update project status to `running`
4. On failure: update project status to `error`
5. Frontend polls `GET /projects/:id/status` every 3s while `status === 'rebuilding'`
6. Frontend shows a spinner/progress indicator in EditorHeader during rebuild
7. Polling stops after max 5 minutes (100 polls). After timeout, show "Rebuild is taking longer than expected. Check status manually." with a retry button.
8. If status becomes `error`, show an error indicator in EditorHeader. For the POC, the error message is generic ("Rebuild failed"). Detailed build logs are a future consideration.

**New project status value**: Add `rebuilding` to the existing status enum (`created`, `running`, `stopped`, `error`).

**Frontend API client**: Add `rebuildProjectAsync()` in `api-client.ts`.

The route handler orchestrates the async flow (not DockerService, since it needs DB access to update status):

1. Route handler updates project status to `rebuilding` in DB
2. Route handler returns `202`
3. Route handler fires off background task: call `DockerService.startProjectAsync()` (which does `up -d --build`), then update status to `running` or `error`

**Files to modify:**
- `apps/devable-backend/src/routes/project-routes.ts` -- add rebuild route with background task
- `apps/devable-frontend/src/lib/api-client.ts` -- add `rebuildProjectAsync` function

---

### Step 2: Backend -- Logs Streaming API

**Why**: The logs panel needs an endpoint to fetch and stream container logs.

Add `streamLogsAsync` to `DockerService`:

```typescript
async *streamLogsAsync(filePath: string, service?: string, lines: number = 100): AsyncGenerator<string> {
  // Spawn: docker compose logs --tail <lines> -f [service]
  // Read stdout line by line, yield each line
}
```

**New route file: `src/routes/log-routes.ts`**

| Method | Path | Description |
|--------|------|-------------|
| GET | `/v1/projects/:id/logs` | Get/stream logs. Query: `service?`, `lines?` (default 100), `follow?` (default false) |

**Route logic based on `follow` parameter:**

- `follow=false`: Call existing `DockerService.getLogsAsync(filePath, service, lines)` → return JSON `{ logs: string }`
- `follow=true`: Call new `DockerService.streamLogsAsync(filePath, service, lines)` → return SSE stream, same generator pattern as chat routes (with keepalive)

**Files to create:**
- `apps/devable-backend/src/routes/log-routes.ts`

**Files to modify:**
- `apps/devable-backend/src/services/docker-service/DockerService.ts` -- add `streamLogsAsync`
- `apps/devable-backend/src/routes.ts` -- register log routes

---

### Step 3: Frontend -- Install Dependencies & ProjectEditorContext

**Why**: The layout shell and all new panels need the shared context and new packages.

**Install:**
- `react-resizable-panels` in `apps/devable-frontend`
- `@monaco-editor/react` in `apps/devable-frontend`

**Create ProjectEditorContext** to share state across panels:

```typescript
type MainView = 'code' | 'preview' | 'logs' | 'split';

interface ProjectEditorState {
  project: ApiProject | null;
  // Main area view
  activeView: MainView;
  setActiveView: (view: MainView) => void;
  // File tree & editor
  openFiles: OpenFile[];
  activeFilePath: string | null;
  selectFile: (path: string) => void;
  closeFile: (path: string) => void;
  markFileDirty: (path: string, isDirty: boolean) => void;
  // File tree refresh
  fileTreeVersion: number; // incremented to trigger tree refresh after CRUD or agent changes
  refreshFileTree: () => void;
  // Agent state
  isAgentStreaming: boolean;
  lastAgentFileChange: number; // timestamp, triggers preview refresh
  notifyAgentFileChange: () => void; // increments fileTreeVersion + updates lastAgentFileChange
}
```

**Files to create:**
- `apps/devable-frontend/src/contexts/ProjectEditorContext.tsx`
- `apps/devable-frontend/src/contexts/ProjectEditorContext.types.ts`

**Files to modify:**
- `apps/devable-frontend/src/lib/api-client.ts` -- add file/log API functions
- `apps/devable-frontend/src/types/api.ts` -- add file tree and related types

---

### Step 4: Frontend -- Layout Shell with Tab-Based Main Area

**Why**: Everything else slots into this layout. Must come before file tree, editor, and logs.

Transform `ProjectEditorPage` from 2-column flex to a chat + tabbed main area layout:

```text
ProjectEditorPage (wraps everything in ProjectEditorContext)
  EditorHeader (top bar: project name, status, controls)
  PanelGroup (horizontal - react-resizable-panels)
    Panel (left: chat)
      ChatPanel (existing)
    PanelResizeHandle
    Panel (right: main area)
      MainArea
        ViewTabBar (horizontal tabs: Code, Preview, Logs, Split)
        ViewContent (renders active view):
          CodeView: FileTreePanel (collapsible sidebar) + CodeEditorPanel
          PreviewView: PreviewPanel (existing, full width)
          LogsView: LogsPanel (full width)
          SplitView: PanelGroup with CodeView + PreviewPanel side-by-side
  EditorFooter (bottom bar)
```

**ViewTabBar** (new):
- Horizontal tab bar with icons + labels: Code, Preview, Logs, Split
- Active tab highlighted
- Icons from lucide-react (e.g., `Code` as CodeIcon, `Eye` as EyeIcon, `Terminal` as TerminalIcon, `Columns` as ColumnsIcon)

**EditorHeader** enhancements:
- Project name (existing)
- Container status indicator (colored dot)
- Start/Stop/Restart/Rebuild buttons (call existing API functions + new rebuild endpoint)
- Settings gear icon (placeholder)

**EditorFooter** (new):
- Connection status indicator
- Agent mode indicator (CLI/SDK)

**Files to create:**
- `apps/devable-frontend/src/components/EditorHeader/EditorHeader.tsx`
- `apps/devable-frontend/src/components/EditorHeader/EditorHeader.css`
- `apps/devable-frontend/src/components/EditorFooter/EditorFooter.tsx`
- `apps/devable-frontend/src/components/EditorFooter/EditorFooter.css`
- `apps/devable-frontend/src/components/MainArea/MainArea.tsx`
- `apps/devable-frontend/src/components/MainArea/MainArea.css`
- `apps/devable-frontend/src/components/MainArea/ViewTabBar/ViewTabBar.tsx`
- `apps/devable-frontend/src/components/MainArea/ViewTabBar/ViewTabBar.css`

**Files to modify:**
- `apps/devable-frontend/src/components/pages/ProjectEditorPage/ProjectEditorPage.tsx` -- rewrite layout
- `apps/devable-frontend/src/components/pages/ProjectEditorPage/ProjectEditorPage.css`
- `apps/devable-frontend/src/components/ChatPanel/ChatPanel.css` -- remove width: 40%
- `apps/devable-frontend/src/components/PreviewPanel/PreviewPanel.css` -- remove flex: 1

---

### Step 5: Frontend -- File Tree Panel

**Why**: Users need to browse project files and select files to open in the editor.

```
FileTreePanel/
  FileTreePanel.tsx
  FileTreePanel.css
  FileTreeNode/
    FileTreeNode.tsx
    FileTreeNode.css
  FileTreePanel.types.ts
  fileIcons.ts
```

Behavior:
- Fetch `GET /v1/projects/:id/files?depth=3` on mount
- Recursive tree with expand/collapse (directories lazy-load deeper levels)
- Click file -> `selectFile(path)` via context (switches to Code view if not already active)
- File icons using lucide-react mapped by extension
- Refresh button in panel header
- Auto-refresh: poll every 10s while `isAgentStreaming`, or on `lastAgentFileChange`
- Context menu (right-click) or action buttons for: New File, New Folder, Rename, Delete
- New file/folder: inline input field in the tree at the target location
- Rename: inline input field replacing the filename
- Delete: confirmation dialog before deleting
- Drag-and-drop: drag files/folders to move them into other folders. Uses the PATCH rename/move endpoint with the new path. Visual drop indicator on target folder.
- Infrastructure file warnings: editing, renaming, moving, or deleting `docker-compose.yml`, `Dockerfile*`, or `.env` shows a warning dialog explaining the risk (e.g., "Moving this file will prevent containers from being rebuilt. Are you sure?")

**Files to create:**
- `apps/devable-frontend/src/components/FileTreePanel/FileTreePanel.tsx`
- `apps/devable-frontend/src/components/FileTreePanel/FileTreePanel.css`
- `apps/devable-frontend/src/components/FileTreePanel/FileTreeNode/FileTreeNode.tsx`
- `apps/devable-frontend/src/components/FileTreePanel/FileTreeNode/FileTreeNode.css`
- `apps/devable-frontend/src/components/FileTreePanel/FileTreePanel.types.ts`
- `apps/devable-frontend/src/components/FileTreePanel/fileIcons.ts`

---

### Step 6: Frontend -- Monaco Code Editor

**Why**: The core IDE feature -- viewing and editing project files.

```
CodeEditorPanel/
  CodeEditorPanel.tsx
  CodeEditorPanel.css
  EditorTabs/
    EditorTabs.tsx
    EditorTabs.css
  CodeEditorPanel.types.ts
  languageMap.ts
```

Behavior:
- Multi-tab: `openFiles` tracked in context as `Array<{ path, content, isDirty, modifiedAt }>`
- File selected from tree -> fetch content if not already open, add tab, switch to it
- Monaco with `automaticLayout: true`, language from extension, always-dark theme (e.g., `vs-dark`)
- Save: Ctrl+S / Cmd+S -> PUT to backend. Explicit save only (no auto-save)
- Dirty indicator: dot on tab for unsaved changes
- Agent modification: when `lastAgentFileChange` updates and affects the open file, show banner: "File modified by agent. [Reload] [Keep my changes]"
- Binary/large files: show placeholder "Binary file" or "File too large (>1MB)"

**EditorTabs:**
- Horizontal tab bar above Monaco
- Filename (tooltip: full path), close button, dirty dot
- Active tab highlighted

**Files to create:**
- `apps/devable-frontend/src/components/CodeEditorPanel/CodeEditorPanel.tsx`
- `apps/devable-frontend/src/components/CodeEditorPanel/CodeEditorPanel.css`
- `apps/devable-frontend/src/components/CodeEditorPanel/EditorTabs/EditorTabs.tsx`
- `apps/devable-frontend/src/components/CodeEditorPanel/EditorTabs/EditorTabs.css`
- `apps/devable-frontend/src/components/CodeEditorPanel/CodeEditorPanel.types.ts`
- `apps/devable-frontend/src/components/CodeEditorPanel/languageMap.ts`

---

### Step 7: Frontend -- Logs View

**Why**: Developers need to see container output for debugging.

```
LogsPanel/
  LogsPanel.tsx
  LogsPanel.css
```

Behavior:
- Full-width view in the main area, activated via the Logs tab
- On activate: fetch `GET /v1/projects/:id/logs?lines=200`
- Monospace pre/code block with auto-scroll, uses full available height
- Service filter dropdown (from project containers)
- Clear button, follow toggle (SSE streaming when on)

**Files to create:**
- `apps/devable-frontend/src/components/LogsPanel/LogsPanel.tsx`
- `apps/devable-frontend/src/components/LogsPanel/LogsPanel.css`

---

### Step 8: Chat Panel Improvements

Address items from FUTURE_CONSIDERATIONS.md:

**8a. Chronological ordering of messages/tool uses**

Current problem: `ChatMessage` renders all text first, then all tool uses, regardless of order.

Fix: Change `DisplayMessage` to use an ordered `contentBlocks` array:

```typescript
type ContentBlock =
  | { type: 'text'; text: string }
  | { type: 'tool_use'; tool: string; id: string; input?: unknown; output?: string; isComplete?: boolean };

interface DisplayMessage {
  id: string;
  role: 'user' | 'assistant';
  contentBlocks: ContentBlock[];
  usage?: ApiTokenUsage;
  cost?: number | null;
  isStreaming?: boolean;
}
```

In `handleStreamEvent`: append blocks in order -- `text_delta` appends to last text block (or creates new one), `tool_use_start` pushes new tool_use block.

In `ChatMessage`: render `contentBlocks` in order, dispatching to markdown or `ToolUseIndicator`.

**8b. Elapsed time indicator**

New `ElapsedTimer` component: shows "12s", "1m 23s" while `isStreaming`. `useEffect` with `setInterval`.

**8c. Better agent activity visibility**

Enhance `ToolUseIndicator`:
- File operations: show the file path
- Command execution: show the command
- Spinner while tool is in progress (no output yet)
- Extract meaningful info from `tool.input` JSON

**Files to create:**
- `apps/devable-frontend/src/components/ChatPanel/ElapsedTimer/ElapsedTimer.tsx`
- `apps/devable-frontend/src/components/ChatPanel/ElapsedTimer/ElapsedTimer.css`

**Files to modify:**
- `apps/devable-frontend/src/components/ChatPanel/ChatPanel.tsx` -- content blocks model
- `apps/devable-frontend/src/components/ChatPanel/ChatMessage/ChatMessage.tsx` -- render blocks in order
- `apps/devable-frontend/src/components/ChatPanel/ChatMessage/ChatMessage.css`
- `apps/devable-frontend/src/components/ChatPanel/ToolUseIndicator/ToolUseIndicator.tsx` -- better context
- `apps/devable-frontend/src/components/ChatPanel/ToolUseIndicator/ToolUseIndicator.css`

---

### Step 9: Preview Panel -- Auto-refresh

The toggle button already exists in the PreviewPanel from Phase 3 but is not wired up. Implement:

- When `autoRefresh` is ON and `lastAgentFileChange` updates (from context), reload the iframe
- Also auto-reload when any agent turn completes (result event)
- When `autoRefresh` is OFF, the user must click the manual refresh button
- Default state: OFF (user opts in to auto-refresh)

**Files to modify:**
- `apps/devable-frontend/src/components/PreviewPanel/PreviewPanel.tsx`

---

### Step 10: Integration Testing & Verification

**Layout & navigation:**

1. Start infrastructure (`dev-start.sh`), backend (`bun dev`), frontend (`npm run dev`)
2. Create a project, open it
3. Verify 2-pane layout renders: chat (left) + main area (right) with tab bar
4. Switch between Code, Preview, Logs, Split tabs -- verify each view renders
5. Resize chat/main divider -- verify drag handle works
6. Verify EditorHeader: project name, container status indicator (colored dot), start/stop/restart/rebuild buttons
7. Verify EditorFooter: connection status, agent mode indicator

**File tree:**

8. In Code view: browse file tree -- verify expand/collapse, icons
9. Toggle file tree sidebar closed and open -- verify it collapses and expands
10. Create a new file via context menu -- verify it appears in tree and can be opened
11. Create a new folder -- verify it appears and files can be created inside it
12. Delete a file -- verify confirmation dialog, file removed from tree and any open tab closed
13. Rename a file -- verify inline rename, tree updates, open tab updates
14. Move a file via drag-and-drop to another folder -- verify tree updates and file path changes
15. If drag-and-drop not feasible via testing tools, move a file via context menu rename (change path)

**Code editor:**

16. Click a file -- verify it opens in Monaco editor with correct syntax highlighting
17. Open multiple files -- verify multi-tab support, switching between tabs
18. Edit a file without saving -- verify dirty indicator (dot) appears on tab
19. Save with Ctrl+S -- verify dirty indicator clears, file saved to disk
20. Close a tab -- verify it's removed, editor switches to another open tab
21. Try opening a binary file (e.g., an image) -- verify placeholder shown instead of editor
22. Try opening a large file (>1MB, e.g., a lockfile) -- verify placeholder or truncation

**Infrastructure file warnings:**

23. Edit `docker-compose.yml` -- verify infrastructure warning dialog appears
24. Try to delete `Dockerfile` -- verify warning dialog about breaking container rebuilds
25. Try to rename/move `.env` -- verify warning dialog

**Chat improvements:**

26. Chat with agent -- verify chronological ordering of text and tool uses
27. Verify elapsed timer shows while agent is responding
28. Verify tool use indicators show file paths for file operations and commands for exec

**File tree + agent integration:**

29. Have agent create/modify files -- verify file tree auto-refreshes during streaming
30. Have agent modify an open file -- verify notification banner ("File modified by agent. [Reload] [Keep my changes]")

**Logs view:**

31. Switch to Logs tab -- verify container logs appear
32. Use service filter dropdown -- verify logs filter by selected container
33. Click clear button -- verify log display clears
34. Toggle follow mode on -- verify new log lines stream in real-time

**Preview & auto-refresh:**

35. Switch to Preview tab -- verify iframe loads project
36. Switch to Split tab -- verify code + preview side-by-side
37. Toggle auto-refresh on, have agent make changes -- verify preview reloads
38. Toggle auto-refresh off -- verify preview does NOT reload on agent changes

**Container rebuild:**

39. Click rebuild button -- verify spinner appears, status shows "rebuilding", polling works, returns to "running"
40. Edit `Dockerfile` to introduce an error, click rebuild -- verify status becomes "error" with error indicator
41. Fix the Dockerfile, rebuild again -- verify recovery back to "running"

**Header controls:**

42. Stop the project via EditorHeader button -- verify containers stop, status updates
43. Start the project via EditorHeader button -- verify containers start, status updates

**Persistence:**

44. Reload page -- verify state recovery (sessions, messages, active view)

---

## Implementation Order

```text
Step 1  (Backend file APIs)       \
Step 1b (Backend rebuild endpoint) } -- parallel, no dependencies between them
Step 2  (Backend logs API)        /
  |
Step 3 (Frontend deps + context)  -- needs steps 1+1b+2 done for API types
  |
Step 4 (Layout shell)             -- needs step 3 for context
  |
Step 5 (File tree)    \
Step 6 (Code editor)   } -- can be somewhat parallel once layout exists
Step 7 (Logs view)    /
Step 8 (Chat fixes)  /            -- independent, parallel with 5-7
  |
Step 9 (Preview auto-refresh)     -- needs context from step 3
  |
Step 10 (Integration testing)     -- everything must be done
```

---

## Automated Tests

Tests are written alongside each step (TDD per project rules).

### Backend tests (`apps/devable-backend/tests/`)

**`services/project-file-browsing-service/ProjectFileBrowsingService.test.ts`** (Step 1):

- Path traversal prevention: `../`, `../../`, absolute paths, URL-encoded dots, symlinks
- List directory tree: correct structure, respects depth, excludes ignored dirs (`node_modules`, `.git`)
- Read file: returns content + modifiedAt, rejects binary files, rejects files >1MB
- Write file: writes content, returns modifiedAt, rejects paths outside project
- Create file: creates file with content, creates empty directory, rejects duplicate paths
- Delete file: deletes file, deletes directory recursively, rejects paths outside project
- Rename/move: renames file, moves to different directory, rejects if target exists, rejects paths outside project

**`routes/file-routes.test.ts`** (Step 1):

- All endpoints verify project ownership (401/403 for wrong user)
- GET /files returns tree structure
- GET /files/* returns file content
- PUT /files/* saves content
- POST /files creates file/folder
- DELETE /files/* removes file/folder
- PATCH /files/* renames/moves

**`routes/log-routes.test.ts`** (Step 2):

- GET /logs with follow=false returns JSON
- GET /logs with follow=true returns SSE stream
- Service filter parameter works
- Project ownership verified

**`routes/project-routes.test.ts`** (Step 1b — add to existing):

- POST /rebuild returns 202, sets status to "rebuilding"
- Status becomes "running" on success
- Status becomes "error" on failure

### Frontend tests (`apps/devable-frontend/`)

**`src/components/MainArea/ViewTabBar/ViewTabBar.test.tsx`** (Step 4):

- Renders all four tabs (Code, Preview, Logs, Split)
- Active tab is highlighted
- Clicking a tab calls setActiveView

**`src/components/MainArea/MainArea.test.tsx`** (Step 4):

- Renders correct view based on activeView state
- Code view shows file tree + editor
- Preview view shows PreviewPanel
- Logs view shows LogsPanel
- Split view shows code + preview side-by-side

**`src/components/FileTreePanel/FileTreePanel.test.tsx`** (Step 5):

- Renders tree from API response
- Expand/collapse directories
- Click file triggers selectFile
- Context menu: new file, new folder, rename, delete actions
- Infrastructure file warnings shown for docker-compose.yml, Dockerfile*, .env
- Collapsible sidebar toggle

**`src/components/FileTreePanel/FileTreeNode/FileTreeNode.test.tsx`** (Step 5):

- Renders file with correct icon
- Renders directory with expand chevron
- Inline rename input
- Drag-and-drop events

**`src/components/CodeEditorPanel/CodeEditorPanel.test.tsx`** (Step 6):

- Opens file in editor when selected
- Multi-tab: open multiple files, switch between them
- Dirty indicator when content changes
- Save clears dirty indicator
- Close tab removes it
- Agent modification notification banner
- Binary file placeholder

**`src/components/CodeEditorPanel/EditorTabs/EditorTabs.test.tsx`** (Step 6):

- Renders tab per open file
- Active tab highlighted
- Close button on each tab
- Dirty dot indicator
- Filename displayed, full path in tooltip

**`src/components/LogsPanel/LogsPanel.test.tsx`** (Step 7):

- Renders log output
- Service filter dropdown changes displayed logs
- Clear button empties display
- Follow toggle starts/stops streaming

**`src/components/ChatPanel/ElapsedTimer/ElapsedTimer.test.tsx`** (Step 8):

- Shows elapsed time while streaming
- Resets when streaming stops
- Formats correctly (seconds, minutes)

**`src/components/ChatPanel/ChatMessage/ChatMessage.test.tsx`** (Step 8 — extend existing):

- Renders contentBlocks in chronological order
- Text blocks render as markdown
- Tool use blocks render as ToolUseIndicator
- Mixed text + tool blocks maintain order

**`src/components/EditorHeader/EditorHeader.test.tsx`** (Step 4):

- Renders project name, status indicator
- Start/stop/restart/rebuild buttons
- Rebuild shows spinner while status is "rebuilding"
- Error indicator when status is "error"

**`src/components/PreviewPanel/PreviewPanel.test.tsx`** (Step 9 — extend existing):

- Auto-refresh reloads iframe when lastAgentFileChange updates and toggle is ON
- No reload when toggle is OFF

---

## Security Considerations

1. **Path traversal**: `resolveAndValidatePath()` is the single security gate. Must use `path.resolve()` and verify result stays within project directory. Unit tests must cover: `../`, `../../`, absolute paths, URL-encoded dots, symlinks.

2. **Project ownership**: Every file/log endpoint must verify `project.userId === requestingUserId`.

3. **File size limits**: Cap reads at 1MB. PUT body size should also be capped.

4. **Directory exclusion**: Never serve `.git` contents. Exclude `node_modules` for performance.

5. **Write safety**: Only accept text content writes. Binary uploads deferred.

---

## What to Defer

- Binary file preview (images in editor) -- show placeholder
- Editor settings (font size, theme, keybindings) -- sensible defaults
- File search (Ctrl+P fuzzy finder) -- nice to have, not MVP
- Diff view for agent modifications -- notification only
- Persistent panel sizes (localStorage) -- add after basics work
- Mobile layout -- IDE is desktop; mobile shows chat-only later
- Migrate Phase 1 proxy routes -- tech debt, not blocking
