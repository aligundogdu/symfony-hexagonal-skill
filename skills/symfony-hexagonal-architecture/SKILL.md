---
name: symfony-hexagonal-architecture
description: "Symfony hexagonal architecture (ports & adapters) setup for Symfony 6.4 LTS, 7.4 LTS and 8.x: project structure, module scaffolding, layer responsibilities, dependency rules, version compatibility, progressive refactoring of legacy code. Use when: architecture, module, layer, hexagonal, scaffold, project structure, directory structure, new project, new module, bounded context, deptrac, Symfony version, upgrade"
---

# Symfony Hexagonal Architecture

You are an expert in Symfony hexagonal architecture (ports & adapters). Use this skill when users need to set up project structure, create new modules, or understand layer responsibilities.

## When to Activate

- User wants to create a new Symfony project with hexagonal architecture
- User asks about project structure or directory layout
- User wants to scaffold a new module/bounded context
- User asks about layer responsibilities or dependency rules
- User mentions "hexagonal", "ports and adapters", "clean architecture" in Symfony context
- User asks which Symfony/PHP version a pattern needs

## Step 0: Detect Versions

Before generating any code, know the project's Symfony, PHP, Doctrine and PHPUnit versions (the plugin's SessionStart hook prints them; otherwise read `composer.lock`). Then follow `references/version-compatibility.md`:

- Default baseline: **PHP 8.2 + Symfony 6.4 APIs** (runs on 6.4, 7.4 and 8.x)
- Use newer features (7.3+ `DeduplicateStamp`, 7.4 `#[ExtendsValidationFor]`, PHP 8.4 `private(set)`, ...) only when the detected versions allow it
- Never generate APIs removed in Symfony 8 (`Request::get()`, constraint option arrays, XML service config)

## Core Principles

### Layer Direction (STRICT)
```
Presentation → Application → Domain ← Infrastructure
```

Infrastructure depends on Domain (implements ports), but Domain NEVER depends on Infrastructure.

### Module Structure

Every module follows this structure under `src/`:

```
Domain/{Module}/
├── Entity/          # Aggregates and entities (pure PHP)
├── ValueObject/     # Immutable value objects
├── Event/           # Domain events (past-tense)
├── Exception/       # Domain-specific exceptions
├── Port/            # Interfaces for external dependencies (write + read ports)
└── ReadModel/       # (optional) Plain read-side view objects returned by read ports

Application/{Module}/
├── Command/         # Write operations (final readonly) + handlers
├── Query/           # Read operations (final readonly) + handlers
├── DTO/             # Data transfer objects
└── EventHandler/    # Domain event handlers (side-effects)

Infrastructure/{Module}/
├── Persistence/     # Doctrine repositories, Mapping/*.orm.xml
├── Security/        # Voters, user providers
├── Messaging/       # Transport adapters, middleware
└── ExternalService/ # HTTP clients, third-party APIs

Presentation/{Module}/
├── API/             # REST controllers (+ Request/ DTOs)
├── CLI/             # Console commands
└── GraphQL/         # GraphQL resolvers/types
```

Shared code lives in a `Shared` module per layer (`Domain/Shared/ValueObject/Money.php`, `Presentation/Shared/Bus/QueryBus.php`, ...).

## Progressive Refactoring (Existing Projects)

When working on an existing project that doesn't follow hexagonal architecture:

### Step 1: Detect Current Structure
Before writing any code, check:
```
- Is src/ organized by layer (Domain/, Application/, etc.) or by traditional Symfony (Controller/, Entity/, Repository/)?
- Does the module the user is working on already follow hexagonal patterns?
- Are there Doctrine annotations/attributes directly on entities?
- Which Symfony / Doctrine versions are installed (affects what the refactor can use)?
```

### Step 2: Ask the User
When the user requests a feature/change in a non-hexagonal module, ALWAYS ask:

> "Bu modül (`{Module}`) şu anda hexagonal yapıda değil. Şu seçeneklerden birini tercih edebilirsiniz:
> 1. **Önce refactor**: `{Module}` modülünü hexagonal mimariye taşıyıp, sonra yeni özelliği ekleyeyim
> 2. **Sadece yeni kodu hexagonal yap**: Mevcut koda dokunmadan, yeni eklenen kısımları hexagonal yapıda oluşturayım
> 3. **Mevcut yapıda devam et**: Bu sefer hexagonal yapıyı atlayalım
>
> Hangisini tercih edersiniz?"

### Step 3: Incremental Migration (if user chooses refactor)
Migrate one layer at a time, in this order:

1. **Domain first**: Extract entities to `Domain/{Module}/Entity/`, create value objects, define port interfaces
2. **Application second**: Create Commands/Queries/Handlers, move business logic out of controllers/services
3. **Infrastructure third**: Move Doctrine repositories to `Infrastructure/{Module}/Persistence/`, move mapping from attributes/annotations to XML
4. **Presentation last**: Thin out controllers, add `ApiResponseTrait` + `#[MapRequestPayload]` DTOs, apply `#[IsGranted]`

After each layer, verify the code still works (tests + `doctrine:schema:validate`) before moving to the next.

Legacy projects on Doctrine annotations (`@ORM\...`) cannot upgrade to ORM 3 anyway: moving the mapping to XML during the Infrastructure step unblocks that upgrade too.

### Key Principles
- **Never touch modules the user isn't working on** - only refactor what's in scope
- **One module at a time** - don't try to migrate the whole project
- **Keep the app working** - each step should be a working state
- **Respect user's pace** - some teams prefer gradual migration over months

## Scaffolding a New Module

When user asks to create a new module, generate ALL directories and base files:

1. Create directory structure (all 4 layers)
2. Create the port interfaces in `Domain/{Module}/Port/`
3. Create the repository adapter + XML mapping in `Infrastructure/{Module}/Persistence/`
4. Register the mapping directory in `doctrine.yaml` and bind ports to adapters in `services.yaml`
5. Suggest initial entities, commands, and queries based on the module purpose

## Key Rules

1. **Domain purity**: No `use Symfony\...`, `use Doctrine\...` or `use Psr\...` in any Domain file, and no framework attributes (`#[ORM\...]`, `#[Assert\...]`, `#[AsMessage]`)
2. **Port-first**: Define the interface before the implementation (this includes IDs, clocks and password hashing)
3. **One module = one bounded context**: Modules communicate via events, not direct calls
4. **Namespace convention**: `App\Domain\{Module}\...`, `App\Application\{Module}\...`, etc.
5. **Enforce it in CI**: deptrac + PHPStan (see `references/dependency-rules.md`)

## References

See `references/` for detailed guides:
- `version-compatibility.md` - Symfony / PHP / Doctrine / PHPUnit support matrix, per-feature minimum versions and fallbacks
- `directory-structure.md` - Full directory layout with file examples
- `layer-responsibilities.md` - What belongs in each layer
- `dependency-rules.md` - Import rules, deptrac and PHPStan enforcement
