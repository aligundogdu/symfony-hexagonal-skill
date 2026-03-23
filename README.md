# Symfony Hexagonal Architecture — Claude Code Plugin

A Claude Code plugin that enforces hexagonal architecture (ports & adapters) in Symfony projects. Works with both **new projects** (full scaffolding) and **existing projects** (progressive, module-by-module refactoring).

No slash commands needed — skills and agents activate automatically based on conversation context.

---

## Table of Contents

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

## Installation

### Option 1: Install from GitHub (Recommended)

Clone the plugin repository and install it globally so it's available across all your Symfony projects:

```bash
# Clone the repository
git clone https://github.com/aligundogdu/symfony-hexagonal-skill.git

# Install the plugin globally
claude plugin add /path/to/symfony-hexagonal-skill
```

Once installed globally, the plugin activates automatically whenever you open Claude Code in any Symfony project directory.

### Option 2: Add Directly to a Project

If you prefer to bundle the plugin with a specific project (useful for teams where everyone should use the same architectural rules):

```bash
# Clone into your project root
git clone https://github.com/aligundogdu/symfony-hexagonal-skill.git .claude-plugin

# Or copy from an existing clone
cp -r /path/to/symfony-hexagonal-skill .claude-plugin
```

Then add `.claude-plugin/` to your project's `.gitignore` — or commit it if you want the entire team to share the same rules:

```bash
# Option A: Keep it local (add to .gitignore)
echo ".claude-plugin/" >> .gitignore

# Option B: Commit it (shared across the team)
git add .claude-plugin/
git commit -m "Add hexagonal architecture Claude Code plugin"
```

### Option 3: Local Development / Testing

If you're contributing to the plugin or want to try it before committing:

```bash
# Run Claude Code with the plugin loaded from a local directory
claude --plugin-dir /path/to/symfony-hexagonal-skill
```

### Verify Installation

After installation, start Claude Code in your project directory and ask:

```
> Analyze the project structure for hexagonal architecture compliance
```

If the plugin is loaded correctly, the **hexagonal-architect** agent will scan your project and return a compliance report. No additional setup required — skills activate automatically based on conversation context.

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

This is where the plugin truly shines. Most Symfony projects already have code — traditional MVC controllers, Doctrine entities with annotations, services calling repositories directly. **You don't have to rewrite everything.**

### How it works

1. **Install the plugin** — nothing in your codebase changes
2. **Keep working as usual** — ask Claude to add features, fix bugs, modify endpoints
3. **The plugin detects non-hexagonal code** — when your request touches a module that doesn't follow hexagonal patterns, it will ask you what to do
4. **You choose the pace** — refactor now, later, or not at all

### What it looks like in practice

```
> Add a "featured" flag to the Product entity with an API endpoint to toggle it

The Product module is currently using traditional Symfony structure
(Entity/ with Doctrine annotations, a ProductRepository extending
ServiceEntityRepository, and a ProductController with business logic).

I can proceed in one of three ways:

1. Refactor first — Migrate the Product module to hexagonal architecture,
   then add the featured flag
2. Hexagonal for new code only — Add the featured flag using hexagonal
   patterns (Command/Handler, port interface) while leaving existing
   Product code as-is
3. Keep current structure — Add the featured flag in the existing
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
| High risk — everything changes at once | Low risk — one module at a time |
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
  └─ Move Doctrine mapping to XML/separate config
  └─ Create repository adapters (implement port interfaces)
  └─ Bind ports to adapters in services.yaml

Step 4: Presentation Layer
  └─ Thin out controllers (dispatch commands/queries only)
  └─ Apply standard JSON response format
  └─ Add #[IsGranted] to every endpoint
```

Each step results in working code. You can stop after any step and continue later.

### What Doesn't Get Touched

- **Modules you're not working on** — The plugin never suggests refactoring code outside your current scope
- **Configuration files** — Unless directly related to the module being refactored
- **Tests** — Existing tests continue to work; new tests follow the hexagonal test structure
- **Third-party bundles** — No changes to vendor code or bundle configuration

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

- **API responses**: Standardized JSON payload `{result, error, extra, status}` with debug mode
- **No cron jobs**: Symfony Messenger async + Scheduler component
- **Security**: Every endpoint requires `#[IsGranted]` or a Voter
- **Quality**: PHPStan level 8+, DTOs at every boundary, 3-layer validation
- **Async resilience**: Idempotency keys, retry with backoff, failure transport
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
│   └── Port/              # Interfaces for external dependencies
│
├── Application/{Module}/
│   ├── Command/           # Write operation DTOs + Handlers
│   ├── Query/             # Read operation DTOs + Handlers
│   ├── DTO/               # Data transfer objects
│   └── EventHandler/      # Domain event side-effect handlers
│
├── Infrastructure/{Module}/
│   ├── Persistence/       # Doctrine repositories + ORM mappings
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

Skills activate automatically based on your conversation context. No slash commands needed.

| Skill | Triggers On | What It Does |
|-------|-------------|--------------|
| **hexagonal-architecture** | architecture, module, layer, scaffold, project structure | Project setup, module scaffolding, layer rules |
| **domain-modeling** | entity, value object, domain event, aggregate | Entity patterns, value objects, domain events |
| **cqrs-handlers** | command, query, handler, CQRS, use case | Command/Query creation, handler patterns, bus config |
| **ports-adapters** | port, adapter, interface, DI, autowiring | Port interfaces, adapter implementations, DI binding |
| **api-response** | API, endpoint, controller, response, REST | JSON payload standard, exception handling |
| **messenger-async** | messenger, async, queue, retry, scheduler | Async processing, idempotency, Symfony Scheduler |
| **security-voters** | security, voter, role, authorization | Voter patterns, role hierarchy, access control |
| **doctrine-persistence** | doctrine, repository, database, mapping, migration | Repository adapters, XML mapping, migration workflow |
| **validation** | validation, validator, constraint | 3-layer validation (presentation, application, domain) |
| **testing** | test, PHPUnit, TDD, unit test, mock | Test organization, TDD workflow, in-memory adapters |

Each skill includes reference files with complete code examples, configuration snippets, and patterns ready to use.

---

## Agents

| Agent | Model | Purpose |
|-------|-------|---------|
| **hexagonal-architect** | Sonnet | Analyzes project structure, designs module architecture, produces compliance scores (0-100). Read-only. |
| **hexagonal-reviewer** | Sonnet | Reviews code changes against all rules. Reports violations as CRITICAL / WARNING / INFO. Read-only. |

### Usage

Agents are invoked through natural conversation:

```
> Review my recent changes for hexagonal compliance
> Analyze the project structure and give me a compliance score
> Design the architecture for a Notification module
```

Both agents are **read-only** — they analyze and report but never modify your code.

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
> Create a Voter for order authorization — owner can edit, admin can delete
```

---

## License

MIT
