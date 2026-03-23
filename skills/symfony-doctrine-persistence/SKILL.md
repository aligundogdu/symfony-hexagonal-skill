---
description: "Symfony Doctrine persistence — repository adapters, entity mapping, migrations, transactions, database patterns. Triggers on: doctrine, repository, persistence, database, mapping, migration, ORM, entity manager, DBAL, transaction"
---

# Symfony Doctrine Persistence

You are an expert in Doctrine ORM within Symfony hexagonal architecture.

## When to Activate

- User needs a repository implementation
- User asks about entity mapping
- User needs migration management
- User discusses transactions or database access

## Core Rules

1. **Mapping NEVER in Domain**: No `#[ORM\Entity]` or annotations on domain entities
2. **Mapping in Infrastructure**: Use XML or separate mapping files in `Infrastructure/{Module}/Persistence/Mapping/`
3. **Repository = Adapter**: Implements domain port interface
4. **Event dispatch after persist**: Repository dispatches domain events after flush
5. **NEVER use native/raw SQL**: No `$connection->executeQuery()`, `$connection->executeStatement()`, `NativeQuery`, `$connection->prepare()`, or raw SQL strings anywhere in application code. Always use Doctrine QueryBuilder (ORM or DBAL), DQL, finder methods, or Criteria API. The only exception is Doctrine Migrations (`$this->addSql()`) which requires raw SQL by design.

## Repository Adapter Pattern

```php
namespace App\Infrastructure\{Module}\Persistence;

use App\Domain\{Module}\Entity\{Entity};
use App\Domain\{Module}\Port\{Entity}RepositoryInterface;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Component\Messenger\MessageBusInterface;

final readonly class Doctrine{Entity}Repository implements {Entity}RepositoryInterface
{
    public function __construct(
        private EntityManagerInterface $entityManager,
        private MessageBusInterface $eventBus,
    ) {
    }

    public function save({Entity} $entity): void
    {
        $this->entityManager->persist($entity);
        $this->entityManager->flush();

        foreach ($entity->pullDomainEvents() as $event) {
            $this->eventBus->dispatch($event);
        }
    }

    public function findById({Entity}Id $id): ?{Entity}
    {
        return $this->entityManager->find({Entity}::class, $id->value);
    }

    public function remove({Entity} $entity): void
    {
        $this->entityManager->remove($entity);
        $this->entityManager->flush();
    }
}
```

## Mapping Strategies

### Option A: XML Mapping (Recommended for strict separation)
```xml
<!-- src/Infrastructure/User/Persistence/Mapping/User.orm.xml -->
<doctrine-mapping>
    <entity name="App\Domain\User\Entity\User" table="users">
        <id name="id" type="string" column="id" />
        <embedded name="email" class="App\Domain\User\ValueObject\Email" />
        <field name="name" type="string" />
        <field name="createdAt" type="datetime_immutable" column="created_at" />
    </entity>
</doctrine-mapping>
```

### Option B: PHP Attributes in Infrastructure
```php
// Separate mapping class that maps to domain entity
// Configure in doctrine.yaml with mapping paths
```

## Migration Workflow

**Always ask the user** which strategy they prefer:
1. **Auto-diff**: `php bin/console doctrine:migrations:diff` (generates from mapping)
2. **Manual**: Write migrations by hand for full control

## Why No Native SQL?

Native/raw SQL bypasses Doctrine's abstraction layers and creates several problems:
- **Database portability lost** — Raw SQL ties code to a specific database engine (MySQL, PostgreSQL, etc.)
- **No type safety** — QueryBuilder provides parameter binding with type inference, raw SQL doesn't
- **Mapping bypass** — Entities, value objects, and custom types are ignored when using raw SQL
- **Harder to maintain** — SQL strings scattered in code are harder to refactor than QueryBuilder chains
- **Security risk** — Raw SQL increases the surface for SQL injection if parameters are not properly bound

### Detecting Native SQL (for code review)

Flag these patterns as CRITICAL violations:
```php
// FORBIDDEN — native SQL patterns
$connection->executeQuery('SELECT ...');
$connection->executeStatement('INSERT ...');
$connection->prepare('SELECT ...');
$connection->exec('DROP ...');
$entityManager->getConnection()->executeQuery(...);
$entityManager->createNativeQuery(...);
$rsm = new ResultSetMapping();

// ALLOWED — Doctrine abstractions
$queryBuilder->select(...)->from(...)->where(...);    // DBAL QueryBuilder
$entityManager->createQueryBuilder()->select('u')...;  // ORM QueryBuilder
$entityManager->createQuery('SELECT u FROM User u');    // DQL
$repository->findBy([...]);                             // Finder methods
$repository->matching($criteria);                       // Criteria API
```

## References

See `references/` for detailed guides:
- `repository-patterns.md` — Repository patterns and transaction management
- `mapping-patterns.md` — XML mapping, embeddables, relations
- `migration-workflow.md` — Migration strategies and best practices
- `no-native-sql.md` — Why native SQL is forbidden and how to use QueryBuilder instead
