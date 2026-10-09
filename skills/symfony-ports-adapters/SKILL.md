---
name: symfony-ports-adapters
description: "Symfony ports and adapters: port interfaces in Domain, adapter implementations in Infrastructure, dependency injection, autowiring, services.yaml aliases, #[AsAlias], environment-specific and decorated adapters, in-memory test adapters. Use when: port, adapter, interface, repository interface, DI, autowiring, dependency injection, services.yaml, binding, decorator, AsAlias"
---

# Symfony Ports & Adapters

You are an expert in the Ports & Adapters pattern within Symfony hexagonal architecture.

## When to Activate

- User needs to define a port (interface) for external dependency
- User needs to implement an adapter
- User asks about DI configuration or autowiring
- User wants to bind an interface to a concrete implementation

## Version Notes

| Feature | Requires | Fallback |
|---|---|---|
| `alias:` in `services.yaml` | all versions | - |
| `when@test:` / `when@dev:` blocks | Symfony 5.3 | `services_test.yaml` |
| `#[AsAlias(PortInterface::class)]` on the adapter | Symfony 6.3 | YAML alias |
| `#[AsAlias(..., when: 'test')]` | Symfony 7.3 | `when@test:` YAML block |
| `#[AsDecorator(decorates: ...)]` | Symfony 6.1 | `decorates:` in YAML |
| Repeatable `#[AsDecorator]` | Symfony 7.4 | one decorator per class |

Default to YAML aliases: they work on every version and keep all bindings visible in one file.

## Port = Interface in Domain

Ports are interfaces that define contracts for external dependencies. They live in `Domain/{Module}/Port/` (shared ones in `Domain/Shared/Port/`).

### Rules
- One interface per concern (Single Responsibility)
- Domain-centric naming (not tech-centric): `UserRepositoryInterface`, not `DoctrineUserRepository`
- Only domain types in signatures (value objects, entities, read models, scalars)
- No framework types in port signatures (`Request`, `Collection`, `UploadedFile`, `Uuid`, ...)
- IDs, clocks and password hashing are ports too

### Common Port Types

| Port Type | Example |
|-----------|---------|
| Repository (write) | `UserRepositoryInterface` |
| Read repository | `UserReadRepositoryInterface` |
| External Service | `PaymentGatewayInterface` |
| Notification | `NotificationServiceInterface` |
| File Storage | `FileStorageInterface` |
| Identity | `IdGeneratorInterface` |
| Security | `PasswordHasherInterface` |

### Template
```php
namespace App\Domain\{Module}\Port;

use App\Domain\{Module}\Entity\{Entity};
use App\Domain\{Module}\ValueObject\{Entity}Id;

interface {Entity}RepositoryInterface
{
    public function save({Entity} $entity): void;

    public function findById({Entity}Id $id): ?{Entity};
}
```

## Adapter = Implementation in Infrastructure

Adapters implement ports using specific technologies. They live in `Infrastructure/{Module}/`.

### Rules
- Implements exactly one port interface
- Contains ALL technology-specific code
- Named with technology prefix: `Doctrine{Entity}Repository`, `Stripe{Payment}Gateway`
- `final readonly class` when possible
- Translates technology exceptions into domain exceptions where callers need to react

### Template
```php
namespace App\Infrastructure\{Module}\Persistence;

use App\Domain\{Module}\Port\{Entity}RepositoryInterface;
use Doctrine\ORM\EntityManagerInterface;

final readonly class Doctrine{Entity}Repository implements {Entity}RepositoryInterface
{
    public function __construct(
        private EntityManagerInterface $entityManager,
    ) {
    }

    // implement all port methods
}
```

## DI Configuration

```yaml
# config/services.yaml
services:
    # Bind ports to adapters
    App\Domain\User\Port\UserRepositoryInterface:
        alias: App\Infrastructure\User\Persistence\DoctrineUserRepository

    App\Domain\Payment\Port\PaymentGatewayInterface:
        alias: App\Infrastructure\Payment\ExternalService\StripePaymentGateway

    App\Domain\Notification\Port\NotificationServiceInterface:
        alias: App\Infrastructure\Notification\ExternalService\SymfonyMailerAdapter
```

Attribute alternative (Symfony 6.3+), on the adapter:

```php
use Symfony\Component\DependencyInjection\Attribute\AsAlias;

#[AsAlias(UserRepositoryInterface::class)]
final readonly class DoctrineUserRepository implements UserRepositoryInterface { /* ... */ }
```

## References

See `references/` for detailed guides:
- `port-adapter-examples.md` - Full examples for various port types
- `di-configuration.md` - Advanced DI configuration patterns
