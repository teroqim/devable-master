# Devable

This is a project to create a more developer friendly version of Lovable.
Where you can create apps by chatting with the AI, which will manage resources, create code for web, apis, and more. A big difference is that it gives developers means to monitor resources better, give full transparency as to what services are used, and give more control over which services are used.

## Overall structure

This is a meta-repo (`devable-master`). App repositories live under `apps/` and are git-ignored — each has its own repo and git history. Run `./setup.sh` to clone or update them.

- `apps/devable-backend` — Backend API
- `apps/devable-frontend` — Frontend app
- `apps.json` — Registry of app repos (used by `setup.sh`)

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
- Use LSP plugins to help with searching and navigating your code.
- Come with suggestions about how to improve overall architecture.
- When the user gives feedback you should see if you can extract rules from the feedback that you can put into a suitable file under .claude/rules so that you can follow those rules in the future and also so that you can use those rules to improve your performance in the future. Always ask if the user wants to save the extracted rules.
- If extracted rules are general coding practices, put them in the .claude-folder here. Otherwise put them in the .claude-folder of the repo that is most relevant to the rule. If you are unsure, ask the user where to put the rule.
- In all projects, prefer using typescript as the programming language, unless it really makes sense to use something else. Always ask the user if you are unsure about which programming language to use.
- Always simplify code wen possible and be brief, but clear in your code. If a piece of code becomes too complex, try to break it down into smaller functions or components. And write comments about complex logic.
- When starting out with a new task, and after you've created a plan and you have approval to start implementing, start by creating a new branch for the task. Name the branch in the format feat/feature-name in all affected repositories.

## Test user

There is user that can be used for testing purposes with the following credentials:

```text
Email: teroqim@gmail.com
Password: f^Ghx]d3(zb9qHiGYX
```
