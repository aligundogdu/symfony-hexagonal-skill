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
            $this->eventBus->dispatch($event);
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
        $count = $qb->select('COUNT(u.id)')
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

## Read-Optimized Repository (DBAL)

For complex queries, use DBAL directly:

```php
namespace App\Infrastructure\User\Persistence;

use App\Application\Shared\DTO\PaginatedResult;
use App\Application\User\DTO\UserDTO;
use App\Domain\User\Port\UserReadRepositoryInterface;
use Doctrine\DBAL\Connection;

final readonly class DbalUserReadRepository implements UserReadRepositoryInterface
{
    public function __construct(
        private Connection $connection,
    ) {
    }

    public function findPaginated(int $page, int $limit, ?string $status, ?string $search): PaginatedResult
    {
        $qb = $this->connection->createQueryBuilder()
            ->select('id', 'email', 'name', 'status', 'created_at')
            ->from('users');

        if ($status !== null) {
            $qb->andWhere('status = :status')->setParameter('status', $status);
        }

        if ($search !== null) {
            $qb->andWhere('(name LIKE :search OR email LIKE :search)')
                ->setParameter('search', '%' . $search . '%');
        }

        // Count total
        $countQb = clone $qb;
        $total = (int) $countQb->select('COUNT(*)')->fetchOne();

        // Fetch page
        $rows = $qb
            ->orderBy('created_at', 'DESC')
            ->setFirstResult(($page - 1) * $limit)
            ->setMaxResults($limit)
            ->fetchAllAssociative();

        return new PaginatedResult(
            items: array_map(fn (array $row) => UserDTO::fromRow($row), $rows),
            total: $total,
            page: $page,
            limit: $limit,
        );
    }
}
```

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
    public function findMatching(UserSpecification $specification): array;
}
```

```php
namespace App\Infrastructure\User\Persistence;

use Doctrine\ORM\QueryBuilder;

final readonly class ActiveUsersSpecification
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
public function softDelete(): void
{
    $this->deletedAt = new \DateTimeImmutable();
    $this->recordEvent(new UserDeleted($this->id->value));
}

// In repository — filter out soft-deleted by default
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
