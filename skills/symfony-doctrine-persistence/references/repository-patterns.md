# Repository Patterns

## Basic Repository Adapter

```php
namespace App\Infrastructure\User\Persistence;

use App\Domain\User\Entity\User;
use App\Domain\User\Port\UserRepositoryInterface;
use App\Domain\User\ValueObject\Email;
use App\Domain\User\ValueObject\UserId;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Component\Messenger\MessageBusInterface;
use Symfony\Component\Messenger\Stamp\DispatchAfterCurrentBusStamp;

final readonly class DoctrineUserRepository implements UserRepositoryInterface
{
    public function __construct(
        private EntityManagerInterface $entityManager,
        private MessageBusInterface $eventBus,
    ) {
    }

    public function save(User $user): void
    {
        $this->entityManager->persist($user);
        $this->entityManager->flush();

        foreach ($user->pullDomainEvents() as $event) {
            $this->eventBus->dispatch($event, [new DispatchAfterCurrentBusStamp()]);
        }
    }

    public function findById(UserId $id): ?User
    {
        return $this->entityManager->find(User::class, $id->value);
    }

    public function findByEmail(Email $email): ?User
    {
        return $this->entityManager->getRepository(User::class)
            ->findOneBy(['email.value' => $email->value]);
    }

    public function existsByEmail(Email $email): bool
    {
        $qb = $this->entityManager->createQueryBuilder();
        $count = (int) $qb->select('COUNT(u.id)')
            ->from(User::class, 'u')
            ->where('u.email.value = :email')
            ->setParameter('email', $email->value)
            ->getQuery()
            ->getSingleScalarResult();

        return $count > 0;
    }

    public function remove(User $user): void
    {
        $this->entityManager->remove($user);
        $this->entityManager->flush();
    }
}
```

## Read-Optimized Repository (DBAL QueryBuilder)

Read ports return Domain read models (`Domain/{Module}/ReadModel/*View`) wrapped in the shared `Page<T>`; the adapter must not import Application DTOs (Infrastructure → Application is forbidden). Full example: cqrs-handlers `query-patterns.md` (`DbalUserReadRepository`).

## ORM Pagination with Fetch Joins

When a page must hydrate entities with joined collections, use Doctrine's paginator so LIMIT applies to root entities:

```php
use Doctrine\ORM\Tools\Pagination\Paginator; // ORM 2.x and 3.0-3.6

$query = $this->entityManager->createQueryBuilder()
    ->select('o', 'i')
    ->from(Order::class, 'o')
    ->leftJoin('o.items', 'i')
    ->orderBy('o.placedAt', 'DESC')
    ->setFirstResult(($page - 1) * $limit)
    ->setMaxResults($limit)
    ->getQuery();

$paginator = new Paginator($query, fetchJoinCollection: true);
$total = count($paginator);
$orders = iterator_to_array($paginator);
```

Doctrine ORM 3.7+ deprecates `Paginator`: use `Doctrine\ORM\Tools\Pagination\OffsetPaginator` with a `Window` value object (offset + limit passed to `paginate()`, which returns an immutable, iterable page). Check the installed ORM version before choosing.

## Transaction Management

### Via Middleware (Recommended)

The `doctrine_transaction` middleware wraps the entire handler in a transaction:

```yaml
framework:
    messenger:
        buses:
            command.bus:
                middleware:
                    - doctrine_transaction
```

### Manual Transaction (When Needed)

```php
namespace App\Infrastructure\Shared\Persistence;

use Doctrine\ORM\EntityManagerInterface;

final readonly class TransactionManager
{
    public function __construct(
        private EntityManagerInterface $entityManager,
    ) {
    }

    /**
     * @template T
     * @param callable(): T $callback
     * @return T
     */
    public function transactional(callable $callback): mixed
    {
        return $this->entityManager->wrapInTransaction($callback);
    }
}
```

## Specification Pattern

For reusable query criteria:

```php
namespace App\Domain\User\Port;

interface UserRepositoryInterface
{
    public function save(User $user): void;
    public function findById(UserId $id): ?User;
    /** @return list<User> */
    public function findMatching(UserSpecification $specification): array;
}
```

```php
namespace App\Infrastructure\User\Persistence;

use Doctrine\ORM\QueryBuilder;

// UserSpecification is a Domain interface/value object describing the criteria;
// the adapter translates it into QueryBuilder conditions.
final readonly class DoctrineActiveUsersSpecification
{
    public function apply(QueryBuilder $qb): void
    {
        $qb->andWhere('u.status = :status')
            ->setParameter('status', 'active');
    }
}
```

## Soft Delete Pattern

```php
// In domain entity
public function softDelete(\DateTimeImmutable $now): void
{
    $this->deletedAt = $now;
    $this->recordEvent(new UserDeleted($this->id->value, $now));
}

// In repository - filter out soft-deleted by default
public function findById(UserId $id): ?User
{
    return $this->entityManager->createQueryBuilder()
        ->select('u')
        ->from(User::class, 'u')
        ->where('u.id = :id')
        ->andWhere('u.deletedAt IS NULL')
        ->setParameter('id', $id->value)
        ->getQuery()
        ->getOneOrNullResult();
}
```
