# Devable

This is a project to create a more developer friendly version of Lovable.
Where you can create apps by chatting with the AI, which will manage resources, create code for web, apis, and more. A big difference is that it gives developers means to monitor resources better, give full transparency as to what services are used, and give more control over which services are used.

## Overall structure

This is a meta-repo (`devable-master`). App repositories live under `apps/` and are git-ignored — each has its own repo and git history. Run `./src/scripts/setup.sh` to clone or update them.

- `apps/devable-backend` — Backend API
- `apps/devable-frontend` — Frontend app
- `apps.json` — Registry of app repos (used by `src/scripts/setup.sh`)
- `src/scripts/` — Dev lifecycle scripts (setup, start, stop)
- `src/caddy/` — Caddy reverse proxy config
- `src/templates/` — Project scaffold templates
- `src/design-themes/` — CSS design theme files

You will work across all apps in `apps/` to create features that span multiple repos.

## Rules

- Follow claude-.md in each of the project and make sure you follow those instructions when coding in each repo and follow whatever settings are in each project's .claude folder.
- Always create plans before coding. Name the plan-files in the format YYYY-MM-DD-hh-mm-feature-name.md and put them in the .claude/plans folder.
- Always create tests before coding.
- Always try to verify that your changes work by running the code and checking the results.
- Always follow good coding practices and clean up after yourself. Leaving deprecated code is strictly forbidden.
- If you need clarification, ask one extra question rather than making assumptions.
- Always ask whether to install new dependecies. Always question yourself if you really need it or if there are other alternative dependencies that are more suited. Only install dependecies in the project folder unless asked otherwise. Always ask the user if you are unsure about which project to install the dependency in.
- Always lint and typecheck your code.
- After writing code, always review it against the project rules (`.claude/rules/`) before presenting it. Check for: correct Async naming, focused try-catch, types in types files, no `for...of`, proper error handling around throwable operations, and all other applicable rules.
- Use LSP plugins to help with searching and navigating your code.
- Come with suggestions about how to improve overall architecture.
- When the user gives feedback you should see if you can extract rules from the feedback that you can put into a suitable file under .claude/rules so that you can follow those rules in the future and also so that you can use those rules to improve your performance in the future. Always ask if the user wants to save the extracted rules.
- If extracted rules are general coding practices, put them in the .claude-folder here. Otherwise put them in the .claude-folder of the repo that is most relevant to the rule. If you are unsure, ask the user where to put the rule.
- When writing rule files, follow the conventions in the "Writing Rule Files" section below.
- In all projects, prefer using typescript as the programming language, unless it really makes sense to use something else. Always ask the user if you are unsure about which programming language to use.
- Always simplify code wen possible and be brief, but clear in your code. If a piece of code becomes too complex, try to break it down into smaller functions or components. And write comments about complex logic.
- When starting out with a new task, and after you've created a plan and you have approval to start implementing, start by creating a new branch for the task. Name the branch in the format feat/feature-name in all affected repositories.

## Writing Rule Files

Rules live in `.claude/rules/` directories. Follow these conventions:

- **Frontmatter**: The only supported frontmatter field is `paths` — a glob pattern (or list of patterns) that scopes when the rule is loaded. Rules without `paths` are loaded unconditionally at session start.
- **Organize by topic**: Group related rules into one file (e.g. `database.md` for all DB/Prisma rules, `code-style.md` for general coding conventions). Don't create one file per rule.
- **Keep files under 200 lines**: If a file grows beyond that, split it into subtopics.
- **Use path scoping** when rules only apply to specific file types (e.g. Prisma rules scoped to `prisma/**`, CSS rules scoped to `*.css`). This saves context by not loading irrelevant rules.
- **Be specific and verifiable**: Write rules concrete enough to verify. "Use 2-space indentation" instead of "Format code properly".
- **Use markdown structure**: Headers, bullets, and code examples make rules easier to follow than dense paragraphs.

Example rule file with path scoping:

```markdown
---
paths:
  - "src/**/*.ts"
  - "src/**/*.tsx"
---

# Code Style

- Do not use `for...of` loops. Use `forEach` or a regular `for` loop.
- Each component must live in its own folder with its CSS file.
```

Example rule file without scoping (always loaded):

```markdown
# Workflows

- Always create plans before coding.
- Name plan files in the format YYYY-MM-DD-hh-mm-feature-name.md.
```

## Test user

There is user that can be used for testing purposes with the following credentials:

```text
Email: teroqim@gmail.com
Password: f^Ghx]d3(zb9qHiGYX
```

## Git Workflow

You may do all read only commands freely, but you must always ask for permission before doing any write commands. This includes creating branches, making commits, pushing to remote, and merging branches.

### Branch Naming

Use conventional prefixes: `feat/`, `fix/`, `chore/`, `docs/`, `refactor/`, `test/`

### Commit Messages

Follow Conventional Commits (enforced by commitlint).
