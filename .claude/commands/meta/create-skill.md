# Create Skill

You are tasked with creating a new skill for the Cortex Framework, following the Anthropic Agent Skills specification (agentskills.io/specification). Skills are passive knowledge packages stored in `.claude/skills/` that agents can reference for domain-specific expertise.

## User Requirements

<requirements>
$ARGUMENTS
</requirements>

## Process

### 1. Analyze Requirements

Before writing anything, determine:
- **Purpose**: What knowledge does this skill encode?
- **Domain**: What area of expertise does it cover?
- **Trigger keywords**: What phrases should cause this skill to be loaded?
- **Agent binding**: Which agents should reference this skill?

Validate that the skill does not overlap with an existing skill in `.claude/skills/`. If it does, suggest extending the existing skill instead.

### 2. Validate Skill Name

The skill name must follow these rules (Anthropic Agent Skills spec):

| Rule | Requirement |
|------|-------------|
| Characters | Lowercase letters, digits, hyphens only |
| Length | 1-64 characters |
| Hyphens | No consecutive hyphens (`--`) |
| Start/End | Must start and end with letter or digit |
| Reserved words | Cannot contain `anthropic` or `claude` |
| Uniqueness | Must NOT already exist in `.claude/skills/` |
| Directory match | Name in frontmatter MUST equal directory name |

Check if `.claude/skills/{name}/` already exists. If it does, stop and inform the user.

### 3. Choose Skill Configuration

Guide the user through these decisions:

**Description**: Write in 3rd person with trigger keywords. This is how Claude Code decides when to load the skill.

Format: `"[What the skill provides]. Use this skill when [trigger conditions with keywords]."`

Examples of good descriptions:
- `"Manage persistent memory layers in .claude/memory/. Use this skill for organizing, pruning, or restructuring project memory files."`
- `"Orchestrate multi-agent workflows for commands. Use this skill when designing new commands that invoke multiple agents."`

**References needed?** Ask if the skill needs a `references/` directory for extended content (details, schemas, examples).

### 4. Create the Directory Structure

```bash
mkdir -p .claude/skills/{name}/references
```

Structure:
```
.claude/skills/{name}/
├── SKILL.md          # Main skill file (max 500 lines)
└── references/       # Optional — detailed content on-demand
    └── {topic}.md    # Extended documentation
```

### 5. Write SKILL.md

Generate the SKILL.md with this structure:

```markdown
---
name: {skill-name}
description: "{description in 3rd person with trigger keywords}"
---

# {Skill Title}

## Visão Geral
[1-2 paragraphs explaining what this skill provides and when to use it]

## [Core Content Sections]
[Domain-specific knowledge organized by topic]
[Include concrete templates, patterns, rules, examples]
[Reference `references/*.md` for extended content]

## Anti-Patterns
[Things to avoid when using this skill]

## Referências
- **[Topic]**: `references/{topic}.md`
```

**Critical rules for SKILL.md**:
- Maximum 500 lines (count after writing, extract to `references/` if over)
- Portuguese with correct accents (á, é, í, ó, ú, ã, õ, ç, â, ê, ô, à)
- Frontmatter `name` MUST exactly match directory name
- Description in 3rd person with trigger keywords
- Progressive disclosure: summary in SKILL.md, details in references/

### 6. Write References (if needed)

For each reference file:
- Add a header with `>` blockquote explaining when this file is loaded
- Include detailed schemas, examples, templates
- No line limit for reference files
- Maintain accent quality

### 7. Bind to Agents

Ask the user which agents should reference this skill, then update their frontmatter.

**Update process** for each agent:

1. Read the agent file at `.claude/agents/{agent-name}.md`
2. Find the `skills:` field in the YAML frontmatter
3. Add the new skill name to the array:
   - `skills: []` → `skills: [{skill-name}]`
   - `skills: [existing]` → `skills: [existing, {skill-name}]`
4. Save the file

**Important**: Do NOT modify anything else in the agent file — only the `skills:` array.

### 8. Verify

After creating all files, perform these checks:

- [ ] Directory `.claude/skills/{name}/` exists
- [ ] `SKILL.md` exists with correct frontmatter (`name` = directory name)
- [ ] `SKILL.md` is under 500 lines
- [ ] `description` is in 3rd person with trigger keywords
- [ ] Portuguese accents are present throughout the file
- [ ] All `references/` files exist and have headers
- [ ] Linked agents have `skills: [{name}]` in their frontmatter
- [ ] No existing skills were accidentally modified

Report the results of these checks to the user, including:
- Files created (with line counts)
- Agents updated (list which ones)
- Any warnings

## Progressive Disclosure Reference

Skills follow 3-level progressive disclosure:

| Level | Content | When Loaded |
|-------|---------|-------------|
| Level 1 | Frontmatter (`name`, `description`) ~100 tokens | ALWAYS — used for routing |
| Level 2 | SKILL.md body (<500 lines) | When skill is invoked by agent |
| Level 3 | `references/*.md` (unlimited) | On-demand when agent needs detail |

## Design Principles

1. **Skills are passive knowledge** — they encode WHAT to know, not WHAT to do. Actions belong in commands.
2. **Progressive disclosure** — keep SKILL.md concise. Push details to `references/`.
3. **Trigger keywords matter** — the `description` determines when Claude loads the skill. Include action verbs and domain terms.
4. **One skill per domain** — don't create overlapping skills. Extend existing ones instead.
5. **Agents consume skills** — skills are useless without at least one agent referencing them.
6. **Max 500 lines** — this is a hard limit from the Anthropic spec. Extract to references if over.
7. **Accents are mandatory** — all Portuguese text must have correct diacritical marks.
8. **Name = directory** — the `name` field in frontmatter MUST exactly match the directory name. This is enforced by the spec.

Now, analyze the user's requirements and begin creating the skill following this process.
