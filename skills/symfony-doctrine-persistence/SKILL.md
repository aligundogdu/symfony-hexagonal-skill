---
name: symfony-doctrine-persistence
description: "Doctrine persistence for Symfony hexagonal architecture (ORM 2.x/3.x, DBAL 3/4, DoctrineBundle 2/3): repository adapters, XML mapping in Infrastructure, embeddables, enums, custom DBAL types, native lazy objects, migrations, transactions, read models with DBAL QueryBuilder, strict no-native-SQL rule. Use when: doctrine, repository, persistence, database, mapping, migration, ORM, entity manager, DBAL, transaction, query builder, pagination"
---

# Symfony Doctrine Persistence

You are an expert in Doctrine ORM within Symfony hexagonal architecture.

## When to Activate

- User needs a repository implementation
- User asks about entity mapping
- User needs migration management
- User discusses transactions or database access

## Version Notes

| Topic | Doctrine ORM 2.x (Symfony 6.4) | Doctrine ORM 3.x (Symfony 7.4 / 8.x) |
|---|---|---|
| Mapping drivers | XML, attributes, annotations, YAML | XML and attributes only (annotations + YAML removed) |
| XML mapping | XSD validation optional | XSD validation always on: invalid XML fails at boot |
| DBAL | 3.x | 4.x (`Type::getName()` removed, register types by name) |
| Lazy loading | proxy classes | PHP 8.4 + ORM 3.4+: native lazy objects (`enable_native_lazy_objects: true`, DoctrineBundle 2.16+; always on in DoctrineBundle 3.1) |
| Pagination | `Tools\Pagination\Paginator` | ORM 3.7+: `OffsetPaginator` + `Window` (`Paginator` deprecated) |
| Readonly properties / `private(set)` / hooks | readonly since 2.13 | readonly; asymmetric visibility + property hooks since 3.4 |

XML entity mapping is unaffected by Symfony 8 removing XML *service/route* configuration.

## Core Rules

1. **Mapping NEVER in Domain**: No `#[ORM\Entity]` or annotations on domain entities
2. **Mapping in Infrastructure**: Use XML or separate mapping files in `Infrastructure/{Module}/Persistence/Mapping/`
3. **Repository = Adapter**: Implements domain port interface
4. **Event dispatch after persist**: Repository dispatches domain events after flush, with `DispatchAfterCurrentBusStamp`
5. **NEVER use native/raw SQL**: No `$connection->executeQuery()`, `$connection->executeStatement()`, `NativeQuery`, `$connection->prepare()`, or raw SQL strings anywhere in application code. Always use Doctrine QueryBuilder (ORM or DBAL), DQL, finder methods, or Criteria API. The only exception is Doctrine Migrations (`$this->addSql()`) which requires raw SQL by design.

## Repository Adapter Pattern

```php
namespace App\Infrastructure\{Module}\Persistence;

use App\Domain\{Module}\Entity\{Entity};
use App\Domain\{Module}\Port\{Entity}RepositoryInterface;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Component\Messenger\MessageBusInterface;
use Symfony\Component\Messenger\Stamp\DispatchAfterCurrentBusStamp;

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
            // released after the current command (and its transaction) succeeds
            $this->eventBus->dispatch($event, [new DispatchAfterCurrentBusStamp()]);
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

### XML Mapping (required for Domain entities)

File: `src/Infrastructure/User/Persistence/Mapping/Entity.User.orm.xml` (name = class relative to the mapping `prefix`, see `references/mapping-patterns.md`)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<doctrine-mapping xmlns="http://doctrine-project.org/schemas/orm/doctrine-mapping"
                  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                  xsi:schemaLocation="http://doctrine-project.org/schemas/orm/doctrine-mapping
                  https://www.doctrine-project.org/schemas/orm/doctrine-mapping.xsd">
    <entity name="App\Domain\User\Entity\User" table="users">
        <id name="id" type="user_id" column="id" />
        <embedded name="email" class="App\Domain\User\ValueObject\Email" use-column-prefix="false" />
        <field name="name" type="string" />
        <field name="createdAt" type="datetime_immutable" column="created_at" />
    </entity>
</doctrine-mapping>
```

### Why not attributes?
`#[ORM\Entity]` attributes must sit on the entity class itself, which lives in Domain. XML is the supported driver that keeps the mapping in Infrastructure. Legacy modules may keep attributes until they are refactored.

## Migration Workflow

**Always ask the user** which strategy they prefer:
1. **Auto-diff**: `php bin/console doctrine:migrations:diff` (generates from mapping)
2. **Manual**: Write migrations by hand for full control

## Why No Native SQL?

Native/raw SQL bypasses Doctrine's abstraction layers and creates several problems:
- **Database portability lost** - Raw SQL ties code to a specific database engine (MySQL, PostgreSQL, etc.)
- **No type safety** - QueryBuilder provides parameter binding with type inference, raw SQL doesn't
- **Mapping bypass** - Entities, value objects, and custom types are ignored when using raw SQL
- **Harder to maintain** - SQL strings scattered in code are harder to refactor than QueryBuilder chains
- **Security risk** - Raw SQL increases the surface for SQL injection if parameters are not properly bound

### Detecting Native SQL (for code review)

Flag these patterns as CRITICAL violations:
```php
// FORBIDDEN - native SQL patterns
$connection->executeQuery('SELECT ...');
$connection->executeStatement('INSERT ...');
$connection->prepare('SELECT ...');
$connection->exec('DROP ...');
$entityManager->getConnection()->executeQuery(...);
$entityManager->createNativeQuery(...);
$rsm = new ResultSetMapping();

// ALLOWED - Doctrine abstractions
$queryBuilder->select(...)->from(...)->where(...);    // DBAL QueryBuilder
$entityManager->createQueryBuilder()->select('u')...;  // ORM QueryBuilder
$entityManager->createQuery('SELECT u FROM User u');    // DQL
$repository->findBy([...]);                             // Finder methods
$repository->matching($criteria);                       // Criteria API
```

## References

See `references/` for detailed guides:
- `repository-patterns.md` - Repository patterns and transaction management
- `mapping-patterns.md` - XML mapping, embeddables, relations
- `migration-workflow.md` - Migration strategies and best practices
- `no-native-sql.md` - Why native SQL is forbidden and how to use QueryBuilder instead
