# Symfony Hexagonal Architecture - Claude Code Plugin

A Claude Code plugin that enforces hexagonal architecture (ports & adapters) in Symfony projects. Works with both **new projects** (full scaffolding) and **existing projects** (progressive, module-by-module refactoring).

- **Version-aware**: supports Symfony **6.4 LTS, 7.4 LTS and 8.x**. The plugin detects your installed Symfony / PHP / Doctrine / PHPUnit versions and generates code that runs on them, with fallbacks for older versions.
- **Zero commands to learn**: skills and agents activate automatically from the conversation.

---

## Table of Contents

- [Compatibility](#compatibility)
- [Installation](#installation)
- [Getting Started with a New Project](#getting-started-with-a-new-project)
- [Adding to an Existing Project](#adding-to-an-existing-project)
- [Progressive Refactoring](#progressive-refactoring)
- [Core Rules](#core-rules)
- [Directory Structure](#directory-structure)
- [Skills Reference](#skills-reference)
- [Agents](#agents)
- [Examples](#examples)
- [License](#license)

---

## Compatibility

| | Symfony 6.4 LTS | Symfony 7.4 LTS | Symfony 8.x |
|---|---|---|---|
| PHP | 8.1+ (8.2+ for `readonly` classes) | 8.2+ | 8.4+ |
| Doctrine ORM / DBAL | 2.x-3.x / 3.x-4.x | 3.x / 4.x | 3.4+ / 4.x |
| PHPUnit | 10-11 | 11-12 | 12-13 |
| Status | supported (bugfix support ends Nov 2026) | recommended | supported |

How it works:

1. On session start (plugin install), a hook prints a **Detected Stack** block read from `composer.lock`. Non-Symfony projects get nothing, so the plugin never affects other repositories.
2. Generated code defaults to APIs available on **all** supported versions (PHP 8.2 + Symfony 6.4).
3. Newer features (`DeduplicateStamp` 7.3+, `#[ExtendsValidationFor]` 7.4+, PHP 8.4 `private(set)`, Doctrine ORM 3.7 `OffsetPaginator`, ...) are used only when your versions allow them, with the fallback documented next to each one.
4. APIs removed in Symfony 8 (`Request::get()`, constraint option arrays, XML service config, Doctrine annotations) are never generated, and the agents flag them in existing code.

The full matrix lives in [`skills/symfony-hexagonal-architecture/references/version-compatibility.md`](skills/symfony-hexagonal-architecture/references/version-compatibility.md).

---

## Installation

Requires [Claude Code](https://code.claude.com). Pick one option.

### Option 1: Plugin (recommended, 2 commands)

Inside Claude Code:

```
/plugin marketplace add aligundogdu/symfony-hexagonal-skill
/plugin install symfony-hexagonal@symfony-hexagonal-skill
```

Or from your shell:

```bash
claude plugin marketplace add aligundogdu/symfony-hexagonal-skill
claude plugin install symfony-hexagonal@symfony-hexagonal-skill            # --scope user (default) | project | local
```

This installs all skills, both agents and the SessionStart hook that loads the architecture rules (only in Symfony projects). Restart the session afterwards.

Update later with `/plugin marketplace update symfony-hexagonal-skill` (or `claude plugin update symfony-hexagonal@symfony-hexagonal-skill`).

### Option 2: Plugin for the whole team (auto-enabled per project)

Commit this to your Symfony project's `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "symfony-hexagonal-skill": {
      "source": { "source": "github", "repo": "aligundogdu/symfony-hexagonal-skill" }
    }
  },
  "enabledPlugins": {
    "symfony-hexagonal@symfony-hexagonal-skill": true
  }
}
```

When teammates open the project and trust the folder, Claude Code offers to install the marketplace and plugin. If a teammate sees "enabled in project settings but isn't installed", they run the two commands from Option 1 once.

### Option 3: Copy into a project (no plugin system)

```bash
git clone https://github.com/aligundogdu/symfony-hexagonal-skill.git /tmp/hex-skill

mkdir -p your-project/.claude/skills your-project/.claude/agents
cp -r /tmp/hex-skill/skills/* your-project/.claude/skills/
cp -r /tmp/hex-skill/agents/* your-project/.claude/agents/

# The rules are normally injected by the plugin hook; without the plugin, append them to CLAUDE.md
cat /tmp/hex-skill/rules/hexagonal-rules.md >> your-project/CLAUDE.md

rm -rf /tmp/hex-skill
```

Commit `.claude/skills/` and `.claude/agents/` to share them with the team.

### Option 4: Symlink (develop the plugin / multi-project)

```bash
git clone https://github.com/aligundogdu/symfony-hexagonal-skill.git ~/symfony-hexagonal-skill

# In each Symfony project
mkdir -p .claude
ln -s ~/symfony-hexagonal-skill/skills .claude/skills
ln -s ~/symfony-hexagonal-skill/agents .claude/agents
echo '@~/symfony-hexagonal-skill/rules/hexagonal-rules.md' >> CLAUDE.md   # CLAUDE.md import

# Or load the checkout as a plugin for one session (includes the hook):
claude --plugin-dir ~/symfony-hexagonal-skill
```

### Verify Installation

In your Symfony project, start Claude Code and ask:

```
> Analyze the project structure for hexagonal architecture compliance
```

The **hexagonal-architect** agent reports your detected stack (Symfony / PHP / Doctrine versions) and a compliance score. With the plugin install, `/plugin` lists `symfony-hexagonal` as enabled and skills appear as `symfony-hexagonal:<skill>`.

Plugin authors can validate the manifest with `claude plugin validate .` in this repository.

---

## Getting Started with a New Project

When starting a Symfony project from scratch, the plugin will set up the full hexagonal structure for you.

### 1. Scaffold the project

```
> Create a new Symfony project with hexagonal architecture for an e-commerce platform
```

The plugin will generate the base directory structure across all four layers (Domain, Application, Infrastructure, Presentation) and configure `services.yaml` with proper port-to-adapter bindings.

### 2. Add your first module

```
> Create a Product module with name, price, and category
```

This generates:
- Domain entities and value objects
- Port interfaces (repository, external services)
- Command/Query classes with handlers
- Doctrine mapping in Infrastructure
- REST controller in Presentation
- Service bindings in `services.yaml`

### 3. Keep building

Every new module, feature, and endpoint follows the same hexagonal rules automatically. The plugin validates each piece of code it generates against the [Core Rules](#core-rules) before outputting it.

---

## Adding to an Existing Project

This is where the plugin truly shines. Most Symfony projects already have code - traditional MVC controllers, Doctrine entities with annotations, services calling repositories directly. **You don't have to rewrite everything.**

### How it works

1. **Install the plugin** - nothing in your codebase changes
2. **Keep working as usual** - ask Claude to add features, fix bugs, modify endpoints
3. **The plugin detects non-hexagonal code** - when your request touches a module that doesn't follow hexagonal patterns, it will ask you what to do
4. **You choose the pace** - refactor now, later, or not at all

### What it looks like in practice

```
> Add a "featured" flag to the Product entity with an API endpoint to toggle it

The Product module is currently using traditional Symfony structure
(Entity/ with Doctrine annotations, a ProductRepository extending
ServiceEntityRepository, and a ProductController with business logic).

I can proceed in one of three ways:

1. Refactor first - Migrate the Product module to hexagonal architecture,
   then add the featured flag
2. Hexagonal for new code only - Add the featured flag using hexagonal
   patterns (Command/Handler, port interface) while leaving existing
   Product code as-is
3. Keep current structure - Add the featured flag in the existing
   traditional style

Which do you prefer?
```

You pick the option that fits your timeline and risk tolerance. The plugin respects your choice and remembers it for the session.

---

## Progressive Refactoring

Progressive refactoring is the plugin's strategy for migrating existing projects to hexagonal architecture **without big-bang rewrites**.

### Why Progressive?

| Big-Bang Rewrite | Progressive Refactoring |
|---|---|
| Weeks of work before any value | Value from day one |
| High risk - everything changes at once | Low risk - one module at a time |
| Blocks feature development | Happens alongside feature development |
| Merge conflicts across the team | Minimal disruption to other developers |
| All-or-nothing commitment | Try it on one module, expand if you like it |

### How It Works

The plugin follows a simple principle: **refactor what you touch, leave the rest alone.**

When you choose to refactor a module, the migration happens in a specific order:

```
Step 1: Domain Layer
  └─ Extract entities (remove Doctrine annotations)
  └─ Create value objects (replace primitive types)
  └─ Define port interfaces (repository, external services)
  └─ Add domain events

Step 2: Application Layer
  └─ Create Commands and Queries (from controller logic)
  └─ Create Handlers (move business logic here)
  └─ Create DTOs (for input/output boundaries)

Step 3: Infrastructure Layer
  └─ Move Doctrine mapping to XML (unblocks Doctrine ORM 3)
  └─ Create repository adapters (implement port interfaces)
  └─ Bind ports to adapters in services.yaml

Step 4: Presentation Layer
  └─ Thin out controllers (dispatch commands/queries only)
  └─ Map input with #[MapRequestPayload] DTOs
  └─ Apply standard JSON response format
  └─ Add #[IsGranted] to every endpoint
```

Each step results in working code. You can stop after any step and continue later.

### What Doesn't Get Touched

- **Modules you're not working on** - The plugin never suggests refactoring code outside your current scope
- **Configuration files** - Unless directly related to the module being refactored
- **Tests** - Existing tests continue to work; new tests follow the hexagonal test structure
- **Third-party bundles** - No changes to vendor code or bundle configuration

### Living with Mixed Architecture

It's perfectly fine to have some modules in hexagonal architecture and others in traditional Symfony. The plugin handles this gracefully:

- New modules are always created in hexagonal style
- Legacy modules work as-is until you decide to migrate them
- Cross-module communication works through Symfony's service container regardless of architecture style
- No special bridge code is needed between hexagonal and non-hexagonal modules

---

## Core Rules

The plugin enforces 4 non-negotiable rules for all hexagonal code:

### 1. Dependency Rule
The Domain layer has **zero external dependencies**. No Symfony imports, no Doctrine imports, no third-party libraries. Only pure PHP.

```
Allowed direction: Presentation → Application → Domain ← Infrastructure
```

### 2. Port/Adapter Enforcement
Every external interaction (database, API, filesystem, email) goes through a **port interface** defined in `Domain/{Module}/Port/`. Concrete implementations live in `Infrastructure/`.

### 3. CQRS Separation
Write operations use **Commands** (return void or ID). Read operations use **Queries** (return DTOs). Each has a dedicated handler. Two separate buses: `command.bus` and `query.bus`.

### 4. Event-Driven Side-Effects
Side-effects (sending emails, updating caches, notifying systems) are triggered through **domain events**, never called directly from command handlers.

### Additional Standards

- **API responses**: Standardized JSON payload `{result, error, extra, status}` with debug mode, Messenger exceptions unwrapped to proper 4xx codes
- **No cron jobs**: Symfony Messenger async + Scheduler component
- **Security**: Every endpoint requires `#[IsGranted]` or a Voter
- **Quality**: PHPStan level 8+ (PHPStan 2.x), deptrac layer rules, DTOs at every boundary, 3-layer validation
- **Async resilience**: Idempotency keys, retry with backoff, failure transport, domain events released only after the transaction commits
- **No native SQL**: Raw/native SQL is forbidden in application code. Use Doctrine QueryBuilder (ORM or DBAL), DQL, or Criteria API. Only Doctrine Migrations may use `$this->addSql()`

---

## Directory Structure

Each module follows this layout under `src/`:

```
src/
├── Domain/{Module}/
│   ├── Entity/            # Aggregate roots, entities (pure PHP)
│   ├── ValueObject/       # Immutable, self-validating value objects
│   ├── Event/             # Domain events (past-tense naming)
│   ├── Exception/         # Domain-specific exceptions
│   ├── Port/              # Interfaces for external dependencies
│   └── ReadModel/         # (optional) views returned by read ports
│
├── Application/{Module}/
│   ├── Command/           # Write operation DTOs + Handlers
│   ├── Query/             # Read operation DTOs + Handlers
│   ├── DTO/               # Data transfer objects
│   └── EventHandler/      # Domain event side-effect handlers
│
├── Infrastructure/{Module}/
│   ├── Persistence/       # Doctrine repositories + XML mappings
│   ├── Security/          # Voters, user provider
│   ├── Messaging/         # Message transport adapters
│   └── ExternalService/   # HTTP clients, third-party APIs
│
└── Presentation/{Module}/
    ├── API/               # REST controllers
    ├── CLI/               # Console commands
    └── GraphQL/           # Resolvers and type definitions
```

Tests mirror this structure:

```
tests/
├── Unit/Domain/           # Pure PHP tests, no framework
├── Integration/Application/ # Handler tests with mocked ports
└── Functional/Presentation/ # Full HTTP stack tests
```

---

## Skills Reference

Skills activate automatically based on your conversation context. With the plugin they are namespaced, e.g. `/symfony-hexagonal:symfony-cqrs-handlers`.

| Skill | Triggers On | What It Does |
|-------|-------------|--------------|
| **symfony-hexagonal-architecture** | architecture, module, layer, scaffold, version, upgrade | Project setup, module scaffolding, layer rules, deptrac, **version compatibility matrix** |
| **symfony-domain-modeling** | entity, value object, domain event, aggregate | Entities, value objects, domain events, ID generator port, PHP 8.2-8.5 modeling |
| **symfony-cqrs-handlers** | command, query, handler, CQRS, use case | Commands/queries, handlers, three buses, typed bus wrappers, read ports + pagination |
| **symfony-ports-adapters** | port, adapter, interface, DI, autowiring | Port interfaces, adapters, `services.yaml` / `#[AsAlias]`, decorators, test adapters |
| **symfony-api-response** | API, endpoint, controller, response, REST | JSON payload standard, `#[MapRequestPayload]`, exception subscriber |
| **symfony-messenger-async** | messenger, async, queue, retry, scheduler, cron | Async processing, idempotency, `DeduplicateStamp`, Symfony Scheduler |
| **symfony-security-voters** | security, voter, role, authorization | `#[IsGranted]`, voters with read ports, role hierarchy, security user adapter |
| **symfony-doctrine-persistence** | doctrine, repository, database, mapping, migration | Repository adapters, XML mapping, custom types, native lazy objects, no native SQL |
| **symfony-validation** | validation, validator, constraint | 3-layer validation, named-argument constraints, `#[ExtendsValidationFor]` |
| **symfony-testing** | test, PHPUnit, TDD, mock, PHPStan | PHPUnit 10-13, in-memory adapters, stubs vs mocks, Foundry 2, PHPStan 2 |

Each skill includes reference files with complete code examples, configuration snippets, and patterns ready to use.

---

## Agents

| Agent | Model | Purpose |
|-------|-------|---------|
| **hexagonal-architect** | Sonnet | Detects the stack, analyzes structure, designs modules, produces compliance scores (0-100) and upgrade notes. Read-only. |
| **hexagonal-reviewer** | Sonnet | Reviews changes against all rules plus version hygiene. Reports CRITICAL / WARNING / INFO with a verdict. Read-only. |

With the plugin they appear as `symfony-hexagonal:hexagonal-architect` and `symfony-hexagonal:hexagonal-reviewer`.

### Usage

```
> Review my recent changes for hexagonal compliance
> Analyze the project structure and give me a compliance score
> Design the architecture for a Notification module
> What breaks if we upgrade this project from Symfony 7.4 to 8.1?
```

Both agents are **read-only**: they analyze and report but never modify your code.

---

## Examples

### Create a module from scratch

```
> Create a User module with registration, login, and profile management
```

### Add a feature to an existing module

```
> Add a password reset flow to the User module
```

### Refactor a legacy module

```
> I want to refactor the Order module to hexagonal architecture
```

### Get an architecture review

```
> Review the project for hexagonal architecture compliance
```

### Check specific patterns

```
> Show me how to create a value object for Money with currency support
> How should I configure Symfony Messenger for async order processing?
> Create a Voter for order authorization: owner can edit, admin can delete
> We are on Symfony 6.4: how do I deduplicate queued messages?
```

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

MIT
