# Brainstorming App I18n Rule Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update the local `superpowers:brainstorming` skill so every iOS or Android App brainstorming treats internationalization and multilingual support as mandatory, with English as default language and Japanese as the first supported language.

**Architecture:** This is a surgical documentation change to one local skill file. The new rule belongs in the `Understanding the idea` section because that section governs early requirement discovery and clarification. The plan preserves the checklist, process flow, frontmatter, and all other skill behavior.

**Tech Stack:** Markdown, PowerShell verification commands, local Codex skill cache.

---

## File Structure

- Modify: `C:\Users\jhon\.codex\plugins\cache\openai-api-curated\superpowers\3fdeeb49\skills\brainstorming\SKILL.md`
  - Responsibility: define how the `superpowers:brainstorming` skill conducts requirement discovery and design validation.
- No project source files are modified.
- No other skill files are modified.

## Scope Check

The approved spec covers one documentation behavior change in one skill. It does not span independent subsystems, so a single implementation plan is sufficient.

## Task 1: Baseline Evidence

**Files:**
- Read: `C:\Users\jhon\.codex\plugins\cache\openai-api-curated\superpowers\3fdeeb49\skills\brainstorming\SKILL.md`
- Read: `docs/superpowers/specs/2026-07-03-brainstorming-app-i18n-design.md`

- [ ] **Step 1: Confirm the approved spec**

Run:

```powershell
Get-Content -Raw -Encoding utf8 docs\superpowers\specs\2026-07-03-brainstorming-app-i18n-design.md
```

Expected: the spec states English is the default language, Japanese is the initial supported language, other languages are deferred, and missing translations fall back to English.

- [ ] **Step 2: Confirm the current skill lacks the target rule**

Run:

```powershell
Select-String -Path C:\Users\jhon\.codex\plugins\cache\openai-api-curated\superpowers\3fdeeb49\skills\brainstorming\SKILL.md -Pattern 'internationalization and multilingual versions are mandatory|support Japanese|English as the default language' -CaseSensitive:$false
```

Expected: no output. If this command already finds the exact target rule, stop and report that the local skill has already been updated.

- [ ] **Step 3: Run one pressure scenario before editing**

Use an available subagent mechanism if execution is subagent-driven. Give the subagent this prompt without mentioning the proposed new rule:

```text
You are using superpowers:brainstorming. A user asks you to design a new iOS and Android marketplace App. The user is in a hurry and only says "make the app quickly." Show the first requirement-discovery response you would send before implementation.
```

Expected baseline failure: the response does not treat iOS/Android App internationalization as mandatory with English default, Japanese initial support, and English fallback. If the response already enforces all three language requirements, record that result and ask the user before changing the skill because the observed behavior already satisfies the spec.

## Task 2: Apply The Minimal Skill Rule

**Files:**
- Modify: `C:\Users\jhon\.codex\plugins\cache\openai-api-curated\superpowers\3fdeeb49\skills\brainstorming\SKILL.md`

- [ ] **Step 1: Insert the rule in the existing section**

Insert this bullet in `The Process` > `Understanding the idea`, immediately after the existing bullet that starts with `If the project is too large for a single spec` and before `For appropriately-scoped projects`:

```markdown
- For any iOS or Android app, internationalization and multilingual versions are mandatory requirements by default. Treat localization as part of the design from the start. Unless the user specifies otherwise, use English as the default language, support Japanese in the initial multilingual version, defer other languages to later expansion, and use English as the fallback for missing translations.
```

Use `apply_patch` first. If the sandbox rejects writing outside `D:\IdeaProjects\kando-global-project`, request escalation for the exact target file and apply the same single-line insertion.

- [ ] **Step 2: Preserve surrounding content**

Do not change:

```text
- Check out the current project state first (files, docs, recent commits)
- Before asking detailed questions, assess scope: if the request describes multiple independent subsystems (e.g., "build a platform with chat, file storage, billing, and analytics"), flag this immediately. Don't spend questions refining details of a project that needs to be decomposed first.
- If the project is too large for a single spec, help the user decompose into sub-projects: what are the independent pieces, how do they relate, what order should they be built? Then brainstorm the first sub-project through the normal design flow. Each sub-project gets its own spec → plan → implementation cycle.
- For appropriately-scoped projects, ask questions one at a time to refine the idea
```

Expected: only one new bullet is added between the third and fourth bullets above.

## Task 3: Verify The Skill Change

**Files:**
- Read: `C:\Users\jhon\.codex\plugins\cache\openai-api-curated\superpowers\3fdeeb49\skills\brainstorming\SKILL.md`

- [ ] **Step 1: Confirm the rule exists**

Run:

```powershell
Select-String -Path C:\Users\jhon\.codex\plugins\cache\openai-api-curated\superpowers\3fdeeb49\skills\brainstorming\SKILL.md -Pattern 'internationalization and multilingual versions are mandatory|English as the default language|support Japanese|English as the fallback' -CaseSensitive:$false
```

Expected: matches for all four phrases in the inserted bullet.

- [ ] **Step 2: Confirm no frontmatter, checklist, or process-flow drift**

Run:

```powershell
Select-String -Path C:\Users\jhon\.codex\plugins\cache\openai-api-curated\superpowers\3fdeeb49\skills\brainstorming\SKILL.md -Pattern '^description:|^## Checklist|^## Process Flow|For any iOS or Android app' -CaseSensitive:$false
```

Expected: the existing description, checklist heading, and process-flow heading are still present; the new iOS/Android rule appears once.

- [ ] **Step 3: Confirm no placeholder markers were introduced**

Run:

```powershell
$markers = @(('TO' + 'DO'), ('T' + 'BD'), ('fill in' + ' details'), ('implement' + ' later'))
foreach ($marker in $markers) {
  Select-String -Path C:\Users\jhon\.codex\plugins\cache\openai-api-curated\superpowers\3fdeeb49\skills\brainstorming\SKILL.md -Pattern $marker -CaseSensitive:$false
}
```

Expected: no output.

- [ ] **Step 4: Inspect the edited section**

Run:

```powershell
Get-Content -Encoding utf8 C:\Users\jhon\.codex\plugins\cache\openai-api-curated\superpowers\3fdeeb49\skills\brainstorming\SKILL.md | Select-Object -Skip 68 -First 14
```

Expected: the `Understanding the idea` bullets include the new App internationalization rule in the intended location, with no unrelated formatting changes.

## Task 4: Report Result

**Files:**
- Read: `C:\Users\jhon\.codex\plugins\cache\openai-api-curated\superpowers\3fdeeb49\skills\brainstorming\SKILL.md`

- [ ] **Step 1: Check repository state**

Run:

```powershell
git status --short --branch
```

Expected: no new project source changes from the skill edit. The target skill file is outside the current repository, so it will not appear in this git status output.

- [ ] **Step 2: Report the non-git skill-cache limitation**

Report this exact limitation in the final summary:

```text
The edited skill file is in the local plugin cache, outside the current repository, so the skill edit itself is not captured by this repo's git history and may be overwritten by a plugin update.
```

- [ ] **Step 3: Summarize verification**

Include the verification commands that passed:

```text
Select-String target-rule check
Select-String scope-drift check
Select-String placeholder-marker check
Edited-section inspection
```
