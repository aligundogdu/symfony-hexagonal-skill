---
name: symfony-domain-modeling
description: "Symfony DDD domain modeling in pure PHP: entities, aggregates, value objects, domain events, domain exceptions, ID generation ports, PHP 8.2-8.5 modeling features (readonly, private(set), clone with). Use when: entity, value object, domain event, aggregate, domain exception, domain model, domain logic, business rule, invariant, enum status"
---

# Symfony Domain Modeling

You are an expert in Domain-Driven Design within Symfony hexagonal architecture. Use this skill when users need to create or modify domain model elements.

## When to Activate

- User wants to create an entity or aggregate root
- User asks about value objects
- User needs domain events
- User mentions domain exceptions or business rules
- User discusses aggregates or invariants

## Version Notes

| Feature | Requires | Fallback |
|---|---|---|
| `final readonly class` | PHP 8.2 | PHP 8.1: `final class` + `public readonly` properties |
| `public private(set)` properties, property hooks | PHP 8.4 + Doctrine ORM 3.4 | private property + getter |
| `clone($this, ['amount' => $x])` | PHP 8.5 | `new self(...)` |
| `array_find()`, `array_any()`, `array_all()` | PHP 8.4 | `foreach` loop |

Generate the fallback form unless the detected PHP constraint allows the newer syntax.

## Entity Patterns

### Rules
- Private constructor + static factory method(s)
- No Doctrine annotations/attributes, mapping is XML in Infrastructure
- Record domain events on state changes
- Protect invariants in methods, not in external validators
- Use value objects for typed properties (no primitive obsession)
- Receive IDs and "now" from the caller (generated via ports), never call UUID libraries or `time()` inside the entity
- Type the event list for PHPStan: `/** @var list<DomainEvent> */`

### Template
```php
namespace App\Domain\{Module}\Entity;

use App\Domain\Shared\Event\DomainEvent;

final class {Entity}
{
    /** @var list<DomainEvent> */
    private array $domainEvents = [];

    private function __construct(
        private {Entity}Id $id,
        // typed properties using value objects
    ) {
    }

    public static function create({Entity}Id $id /*, params */): self
    {
        // validate invariants
        $entity = new self($id /*, params */);
        $entity->recordEvent(new {Entity}Created($id->value));

        return $entity;
    }

    // Business methods that protect invariants
    public function doAction(/* params */): void
    {
        // guard clause / invariant check
        // state change
        $this->recordEvent(new {ActionDone}($this->id->value));
    }

    /** @return list<DomainEvent> */
    public function pullDomainEvents(): array
    {
        $events = $this->domainEvents;
        $this->domainEvents = [];

        return $events;
    }

    private function recordEvent(DomainEvent $event): void
    {
        $this->domainEvents[] = $event;
    }
}
```

## Value Object Patterns

### Rules
- Always `final readonly class` (PHP 8.2+)
- Self-validating in constructor (throw domain exception if invalid)
- Immutable, no setters; transformations return new instances
- Implement `equals()` for comparison
- Use for: IDs, email, money, dates, status enums

### Template
```php
namespace App\Domain\{Module}\ValueObject;

use App\Domain\{Module}\Exception\Invalid{ValueObject}Exception;

final readonly class {ValueObject}
{
    public function __construct(
        public string $value,
    ) {
        if (/* validation fails */) {
            throw Invalid{ValueObject}Exception::forValue($value);
        }
    }

    public function equals(self $other): bool
    {
        return $this->value === $other->value;
    }

    public function __toString(): string
    {
        return $this->value;
    }
}
```

## Domain Event Patterns

### Rules
- Past-tense naming: `UserRegistered`, `OrderPlaced`, `PaymentFailed`
- Immutable (`final readonly class`) implementing `App\Domain\Shared\Event\DomainEvent`
- Carry only the data needed by handlers (IDs and scalars, not entities), they get serialized on async transports
- Created inside entities on state changes
- No `#[AsMessage]` on domain events (it is a Symfony attribute): route them in `messenger.yaml`

### Template
```php
namespace App\Domain\{Module}\Event;

use App\Domain\Shared\Event\DomainEvent;

final readonly class {PastTenseEvent} implements DomainEvent
{
    public function __construct(
        public string $aggregateId,
        public \DateTimeImmutable $occurredOn,
        // additional event-specific data
    ) {
    }

    public function aggregateId(): string
    {
        return $this->aggregateId;
    }

    public function occurredOn(): \DateTimeImmutable
    {
        return $this->occurredOn;
    }
}
```

## Domain Exception Patterns

```php
namespace App\Domain\{Module}\Exception;

final class {DomainException} extends \DomainException
{
    public static function because{Reason}(string $context): self
    {
        return new self(sprintf('Descriptive message: %s', $context));
    }
}
```

## References

See `references/` for detailed patterns:
- `entity-patterns.md` - Full entity examples with aggregates
- `value-object-patterns.md` - Common value object implementations, ID generation port
- `domain-event-patterns.md` - Event design and dispatch patterns
