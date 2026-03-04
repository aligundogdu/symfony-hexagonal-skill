# Symfony Hexagonal Architecture Rules

This plugin enforces hexagonal architecture in Symfony projects. These rules apply to ALL code generation and review.

## Progressive Refactoring Strategy

**This plugin does NOT require rewriting an entire project at once.** When added to an existing Symfony project that doesn't follow hexagonal architecture:

1. **Detect existing structure first**: Before any code generation, scan the project to understand current conventions (traditional Symfony, MVC, etc.)
2. **New code follows hexagonal rules**: All newly created modules/features use the hexagonal structure
3. **Ask before refactoring existing code**: When the user requests a change that touches non-hexagonal code, ASK:
   - "Bu modül henüz hexagonal yapıda değil. İsterseniz önce `{Module}` modülünü hexagonal mimariye taşıyıp sonra yeni özelliği ekleyeyim. Ya da mevcut yapıda devam edebilirim. Hangisini tercih edersiniz?"
   - Offer clear options: (a) refactor to hexagonal first, then add feature, (b) add feature in current structure, (c) add feature in hexagonal but leave existing code as-is
4. **Refactor only the touched module**: Never refactor unrelated modules. Only the module the user is actively working on is a candidate.
5. **Incremental migration path**: When user chooses refactoring, migrate one layer at a time — Domain first, then Application, then Infrastructure, finally Presentation.

### When to Ask
- User wants to modify an existing controller/service/repository that isn't in hexagonal structure
- User wants to add a feature to a module that has mixed architecture
- User asks to create something that interacts with legacy (non-hexagonal) code

### When NOT to Ask
- User explicitly says "just do it" or "mevcut yapıda devam et"
- Project is already fully hexagonal
- User is creating a brand-new module with no legacy dependencies
- Trivial changes (config, env, docs) that don't involve architecture

## 4 Core Rules (NEVER violate)

### 1. Dependency Rule
- `Domain/` has ZERO external dependencies — no Symfony, Doctrine, or third-party imports
- Domain contains only pure PHP: entities, value objects, events, exceptions, port interfaces
- Only `Application/` may depend on `Domain/`. Only `Infrastructure/` implements ports. Only `Presentation/` calls application services.
- Direction: Presentation → Application → Domain ← Infrastructure

### 2. Port/Adapter Enforcement
- Every external interaction (DB, API, filesystem, email) MUST go through a port interface in `Domain/{Module}/Port/`
- Adapters implementing ports live in `Infrastructure/{Module}/`
- Bind adapters to ports via `services.yaml` — never inject concrete adapters directly

### 3. CQRS Separation
- Commands: `final readonly class` in `Application/{Module}/Command/`, return void or ID
- Queries: `final readonly class` in `Application/{Module}/Query/`, return DTO
- Handlers: one `__invoke` method, annotated with `#[AsMessageHandler]`
- Two buses: `command.bus` and `query.bus` in messenger config

### 4. Event-Driven Side-Effects
- Domain events: past-tense named, immutable, created within entities
- Event handlers in `Application/{Module}/EventHandler/`
- Side-effects (email, notifications, cache) triggered ONLY via events — never in command handlers

## Additional Standards

### API Response Format
All API endpoints return: `{"result": mixed, "error": ?object, "extra": ?object, "status": int}`
Debug details included only when `APP_DEBUG=true`.

### No Cron Jobs
Use Symfony Messenger async transport + Symfony Scheduler component. Never raw cron.

### Security
Every endpoint MUST have a ROLE via `#[IsGranted]` or Voter. Use role hierarchy in `security.yaml`. Complex authorization → Symfony Voter.

### Quality
- PHPStan level 8+ mandatory
- DTOs at every boundary (controller input, handler output, API response)
- Validation at 3 layers: Presentation (input), Application (DTO), Domain (invariants)

### Async Resilience
- Messages must be idempotent (use idempotency keys)
- Configure retry with backoff in `messenger.yaml`
- Failed messages → `failed` transport with monitoring

### Doctrine
- Repository adapters in `Infrastructure/{Module}/Persistence/`
- Entity mapping via XML or attribute in Infrastructure — NEVER annotations in Domain entities
- Ask user preference for migration strategy (manual vs auto-diff)

## Directory Structure (per module)

```
src/
├── Domain/{Module}/Entity/, ValueObject/, Event/, Exception/, Port/
├── Application/{Module}/Command/, Query/, DTO/, EventHandler/
├── Infrastructure/{Module}/Persistence/, Messaging/, ExternalService/
└── Presentation/{Module}/API/, CLI/, GraphQL/
```

## Code Generation Checklist
When generating code, verify:
- [ ] No Symfony/Doctrine imports in Domain/
- [ ] External calls go through port interfaces
- [ ] Commands and Queries are separate with dedicated handlers
- [ ] Side-effects use domain events, not direct calls
- [ ] API responses use standard payload format
- [ ] Endpoints have ROLE authorization
- [ ] DTOs used at boundaries
- [ ] Tests follow src/ mirror structure
