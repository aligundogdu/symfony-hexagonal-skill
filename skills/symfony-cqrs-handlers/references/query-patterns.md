# Query Patterns

## Simple Query

```php
namespace App\Application\User\Query;

use App\Application\User\DTO\UserDTO;
use App\Domain\User\Port\UserRepositoryInterface;
use App\Domain\User\ValueObject\UserId;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;

final readonly class GetUserById
{
    public function __construct(
        public string $userId,
    ) {
    }
}

#[AsMessageHandler(bus: 'query.bus')]
final readonly class GetUserByIdHandler
{
    public function __construct(
        private UserRepositoryInterface $userRepository,
    ) {
    }

    public function __invoke(GetUserById $query): ?UserDTO
    {
        $user = $this->userRepository->findById(new UserId($query->userId));

        return $user === null ? null : UserDTO::fromEntity($user);
    }
}
```

## Read Side: Port, Read Model, Page

List and search screens should not hydrate aggregates. Define a **read port** in Domain that returns plain read models. Everything stays inside the dependency rule: Domain defines the shapes, Infrastructure fills them, Application maps them to DTOs.

### Generic page (Shared Kernel, pure PHP)

```php
namespace App\Domain\Shared\ReadModel;

/**
 * @template T
 */
final readonly class Page
{
    /**
     * @param list<T> $items
     */
    public function __construct(
        public array $items,
        public int $total,
        public int $page,
        public int $limit,
    ) {
    }

    public function totalPages(): int
    {
        return $this->limit > 0 ? (int) ceil($this->total / $this->limit) : 0;
    }

    /**
     * @template R
     * @param callable(T): R $mapper
     * @return self<R>
     */
    public function map(callable $mapper): self
    {
        return new self(array_map($mapper, $this->items), $this->total, $this->page, $this->limit);
    }
}
```

### Read model and read port

```php
namespace App\Domain\User\ReadModel;

final readonly class UserView
{
    public function __construct(
        public string $id,
        public string $email,
        public string $name,
        public string $status,
        public \DateTimeImmutable $createdAt,
    ) {
    }
}
```

```php
namespace App\Domain\User\Port;

use App\Domain\Shared\ReadModel\Page;
use App\Domain\User\ReadModel\UserView;

interface UserReadRepositoryInterface
{
    /** @return Page<UserView> */
    public function search(int $page, int $limit, ?string $status, ?string $search): Page;
}
```

## List Query with Pagination

```php
namespace App\Application\User\Query;

use Symfony\Component\Validator\Constraints as Assert;

final readonly class ListUsers
{
    public function __construct(
        #[Assert\Positive]
        public int $page = 1,
        #[Assert\Range(min: 1, max: 100)]
        public int $limit = 20,
        public ?string $status = null,
        public ?string $search = null,
    ) {
    }
}
```

```php
namespace App\Application\User\Query;

use App\Application\User\DTO\UserListItemDTO;
use App\Domain\Shared\ReadModel\Page;
use App\Domain\User\Port\UserReadRepositoryInterface;
use App\Domain\User\ReadModel\UserView;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;

#[AsMessageHandler(bus: 'query.bus')]
final readonly class ListUsersHandler
{
    public function __construct(
        private UserReadRepositoryInterface $users,
    ) {
    }

    /** @return Page<UserListItemDTO> */
    public function __invoke(ListUsers $query): Page
    {
        return $this->users
            ->search($query->page, $query->limit, $query->status, $query->search)
            ->map(static fn (UserView $view): UserListItemDTO => UserListItemDTO::fromView($view));
    }
}
```

## Read Adapter with DBAL QueryBuilder (no native SQL)

```php
namespace App\Infrastructure\User\Persistence;

use App\Domain\Shared\ReadModel\Page;
use App\Domain\User\Port\UserReadRepositoryInterface;
use App\Domain\User\ReadModel\UserView;
use Doctrine\DBAL\Connection;

final readonly class DbalUserReadRepository implements UserReadRepositoryInterface
{
    public function __construct(
        private Connection $connection,
    ) {
    }

    public function search(int $page, int $limit, ?string $status, ?string $search): Page
    {
        $qb = $this->connection->createQueryBuilder()
            ->from('users', 'u');

        if ($status !== null) {
            $qb->andWhere('u.status = :status')->setParameter('status', $status);
        }
        if ($search !== null) {
            $qb->andWhere('u.name LIKE :search OR u.email LIKE :search')
                ->setParameter('search', '%' . addcslashes($search, '%_') . '%');
        }

        $total = (int) (clone $qb)->select('COUNT(u.id)')->fetchOne();

        /** @var list<array{id: string, email: string, name: string, status: string, created_at: string}> $rows */
        $rows = $qb
            ->select('u.id', 'u.email', 'u.name', 'u.status', 'u.created_at')
            ->orderBy('u.created_at', 'DESC')
            ->setFirstResult(($page - 1) * $limit)
            ->setMaxResults($limit)
            ->fetchAllAssociative();

        return new Page(
            items: array_map(static fn (array $row): UserView => new UserView(
                id: $row['id'],
                email: $row['email'],
                name: $row['name'],
                status: $row['status'],
                createdAt: new \DateTimeImmutable($row['created_at']),
            ), $rows),
            total: $total,
            page: $page,
            limit: $limit,
        );
    }
}
```

`andWhere('a OR b')` is wrapped in parentheses by DBAL's QueryBuilder, so the OR does not leak into other conditions.

For ORM-based pagination with fetch-joined collections: Doctrine ORM 3.7+ deprecates `Tools\Pagination\Paginator` in favor of `OffsetPaginator` + `Window`; on ORM 2.x / 3.0-3.6 keep `Paginator`.

## Controller: Query Parameters

```php
use Symfony\Component\HttpKernel\Attribute\MapQueryString;

#[Route('', methods: ['GET'])]
#[IsGranted('ROLE_USER_LIST')]
public function list(#[MapQueryString] ListUsersRequest $request = new ListUsersRequest()): JsonResponse
{
    /** @var Page<UserListItemDTO> $page */
    $page = $this->queryBus->ask(new ListUsers($request->page, $request->limit, $request->status, $request->search));

    return $this->paginated($page->items, $page->total, $page->page, $page->limit);
}
```

`#[MapQueryString]` (Symfony 6.3+) returns 404 on validation failure by default; pass `validationFailedStatusCode: 422` to keep errors consistent with the JSON API format. Never use `$request->get()`: deprecated in 7.4 and removed in 8.0.
