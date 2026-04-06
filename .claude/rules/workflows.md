# Workflows

## Plan Files

- Always write plans to a file immediately, even if they are not finished or approved yet.
- Unfinished/unapproved plans should have `-unfinished` appended to the filename (before `.md`).
- Once the plan is approved, rename the file to remove the `-unfinished` suffix.
- This ensures plans are never lost due to rejected file writes or context issues.

## File Deletion

- To remove files that have been committed or checked into git, always use `git rm` instead of `rm`. This ensures the deletion is tracked by git and avoids sandbox permission issues.

## Future Considerations

- When you discover future considerations, known limitations, deferred features, or technical debt during development, add them to `FUTURE_CONSIDERATIONS.md` in the repo root.
- Each entry should include:
  - A clear heading describing the item.
  - Enough context to understand the problem and why it matters, without needing to re-read the original plan.
  - A `*Source: ...*` line indicating where the item was discovered (e.g., "Phase 3 plan").
- Place entries under the appropriate section: "Known Limitations", "Infrastructure", "AI Agent", "Features", or "Technical Debt".
- Check for existing entries before adding -- update rather than duplicate.
- When a feature or limitation is resolved, remove or update the corresponding entry so the file stays current.

## README Writing

When adapting or creating README files from reference material:

- Include all useful tips and notes from the source material (e.g. debugger tips, common pitfalls, workarounds).
- Do not make up new content that isn't in the source or the actual project.
- Adapt specifics (port numbers, DB names, commands) to match the actual project.
- Keep the human-friendly tone from the source.
