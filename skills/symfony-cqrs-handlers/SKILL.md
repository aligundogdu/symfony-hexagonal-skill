---
name: symfony-cqrs-handlers
description: "Symfony CQRS with Messenger: commands, queries, handlers, command.bus / query.bus / event.bus configuration, typed bus wrappers, HandlerFailedException unwrapping, read ports and pagination, use cases. Works on Symfony 6.4, 7.x, 8.x. Use when: command, query, handler, CQRS, bus, use case, command handler, query handler, message bus, HandleTrait, HandledStamp"
---

# Symfony CQRS Handlers

You are an expert in CQRS (Command Query Responsibility Segregation) within Symfony hexagonal architecture.

## When to Activate

- User wants to create a command or query
- User needs a handler for a use case
- User asks about CQRS patterns or message bus configuration
- User mentions "use case", "action", "operation" in application context

## Why Separate Buses

Symfony's docs recommend a single bus unless you need different middleware. This architecture has that need: `command.bus` wraps handlers in `doctrine_transaction`, `query.bus` must never open write transactions, and `event.bus` must allow zero handlers. Mention this when users question the extra buses.

## Version Notes

| Feature | Requires | Fallback |
|---|---|---|
| `#[AsMessageHandler(bus: '...')]` | Symfony 6.0 | - |
| `#[AsMessage('async')]` on a command | Symfony 7.2 | `framework.messenger.routing` in YAML |
| `DeduplicateStamp` | Symfony 7.3 + symfony/lock | Idempotency key check in the handler |
| `#[AsMessage(serializedTypeName: ...)]` | Symfony 8.1 | default FQCN type name |

## Command Pattern

Commands represent write operations (create, update, delete). They are messages dispatched to the command bus.

### Rules
- `final readonly class`, immutable after construction
- Named as imperative verb: `RegisterUser`, `PlaceOrder`, `CancelSubscription`
- Contains only scalars/arrays (serializable for async transports), no entities
- Handler returns `void` or a scalar identifier (string ID)
- One handler per command

### Template
```php
namespace App\Application\{Module}\Command;

use Symfony\Component\Validator\Constraints as Assert;

final readonly class {ActionVerb}{Entity}
{
    public function __construct(
        #[Assert\NotBlank]
        public string $param1,
        public string $param2,
    ) {
    }
}
```

### Handler Template
```php
namespace App\Application\{Module}\Command;

use App\Domain\{Module}\Port\{Entity}RepositoryInterface;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;

#[AsMessageHandler(bus: 'command.bus')]
final readonly class {ActionVerb}{Entity}Handler
{
    public function __construct(
        private {Entity}RepositoryInterface $repository,
    ) {
    }

    public function __invoke({ActionVerb}{Entity} $command): void
    {
        // 1. Load/create domain objects
        // 2. Execute business logic (entity methods)
        // 3. Persist via port (repository dispatches domain events)
        // NO side-effects here, use domain events
    }
}
```

## Query Pattern

Queries represent read operations. They return DTOs, never domain entities.

### Rules
- `final readonly class`, immutable
- Named descriptively: `GetUserById`, `ListActiveOrders`, `SearchProducts`
- Handler MUST return a DTO, a list of DTOs or a `Page` of DTOs
- Handler NEVER modifies state
- May use read-optimized ports (`{Entity}ReadRepositoryInterface`) backed by DBAL QueryBuilder

### Template
```php
namespace App\Application\{Module}\Query;

final readonly class Get{Entity}ById
{
    public function __construct(
        public string $id,
    ) {
    }
}
```

### Handler Template
```php
namespace App\Application\{Module}\Query;

use App\Application\{Module}\DTO\{Entity}DTO;
use App\Domain\{Module}\Port\{Entity}RepositoryInterface;
use App\Domain\{Module}\ValueObject\{Entity}Id;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;

#[AsMessageHandler(bus: 'query.bus')]
final readonly class Get{Entity}ByIdHandler
{
    public function __construct(
        private {Entity}RepositoryInterface $repository,
    ) {
    }

    public function __invoke(Get{Entity}ById $query): ?{Entity}DTO
    {
        $entity = $this->repository->findById(new {Entity}Id($query->id));

        return $entity === null ? null : {Entity}DTO::fromEntity($entity);
    }
}
```

## DTO Pattern

```php
namespace App\Application\{Module}\DTO;

use App\Domain\{Module}\Entity\{Entity};

final readonly class {Entity}DTO
{
    public function __construct(
        public string $id,
        public string $name,
    ) {
    }

    public static function fromEntity({Entity} $entity): self
    {
        return new self(
            id: $entity->id()->value,
            name: $entity->name(),
        );
    }
}
```

Symfony 7.3+ ObjectMapper (`#[Map]`) can replace hand-written `fromX()` factories for DTO-to-DTO mapping. Do not map directly into Domain entities with it: it bypasses constructors and therefore invariants.

## Dispatching From Controllers

Use the `CommandBus` / `QueryBus` wrappers from `references/bus-configuration.md`. They return the handler result and rethrow the original domain exception instead of Messenger's `HandlerFailedException`, so the API exception subscriber can map it to the right HTTP status.

## References

See `references/` for detailed guides:
- `command-patterns.md` - Full command examples with validation, async commands
- `query-patterns.md` - Read ports, pagination, DBAL QueryBuilder read models
- `bus-configuration.md` - Messenger bus setup, middleware, bus wrappers
