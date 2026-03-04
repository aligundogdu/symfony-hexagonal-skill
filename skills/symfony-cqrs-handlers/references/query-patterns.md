# Query Patterns

## Simple Query

```php
namespace App\Application\User\Query;

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
        if ($user === null) {
            return null;
        }

        return UserDTO::fromEntity($user);
    }
}
```

## List Query with Pagination

```php
final readonly class ListUsers
{
    public function __construct(
        public int $page = 1,
        public int $limit = 20,
        public ?string $status = null,
        public ?string $search = null,
    ) {
    }
}

#[AsMessageHandler(bus: 'query.bus')]
final readonly class ListUsersHandler
{
    public function __construct(
        private UserRepositoryInterface $userRepository,
    ) {
    }

    public function __invoke(ListUsers $query): PaginatedResult
    {
        return $this->userRepository->findPaginated(
            page: $query->page,
            limit: $query->limit,
            status: $query->status,
            search: $query->search,
        );
    }
}
```

## Paginated Result DTO

```php
namespace App\Application\Shared\DTO;

final readonly class PaginatedResult
{
    public function __construct(
        public array $items,
        public int $total,
        public int $page,
        public int $limit,
    ) {
    }

    public function totalPages(): int
    {
        return (int) ceil($this->total / $this->limit);
    }

    public function hasNextPage(): bool
    {
        return $this->page < $this->totalPages();
    }
}
```

## Read-Optimized Port

For complex queries, define a separate read port that may use raw SQL or read-model:

```php
namespace App\Domain\Order\Port;

use App\Application\Shared\DTO\PaginatedResult;

interface OrderReadRepositoryInterface
{
    public function findOrderSummaries(
        string $customerId,
        int $page,
        int $limit,
    ): PaginatedResult;

    public function findDashboardStats(string $customerId): OrderStatsDTO;
}
```

The adapter can use Doctrine DBAL directly for optimized reads:

```php
namespace App\Infrastructure\Order\Persistence;

use App\Domain\Order\Port\OrderReadRepositoryInterface;
use Doctrine\DBAL\Connection;

final readonly class DbalOrderReadRepository implements OrderReadRepositoryInterface
{
    public function __construct(
        private Connection $connection,
    ) {
    }

    public function findOrderSummaries(string $customerId, int $page, int $limit): PaginatedResult
    {
        $offset = ($page - 1) * $limit;

        $sql = 'SELECT id, status, total_amount, created_at FROM orders WHERE customer_id = :customerId ORDER BY created_at DESC LIMIT :limit OFFSET :offset';

        $rows = $this->connection->fetchAllAssociative($sql, [
            'customerId' => $customerId,
            'limit' => $limit,
            'offset' => $offset,
        ]);

        $total = $this->connection->fetchOne(
            'SELECT COUNT(*) FROM orders WHERE customer_id = :customerId',
            ['customerId' => $customerId]
        );

        return new PaginatedResult(
            items: array_map(fn (array $row) => OrderSummaryDTO::fromRow($row), $rows),
            total: (int) $total,
            page: $page,
            limit: $limit,
        );
    }
}
```

## Dispatching Queries

```php
// In controller:
$envelope = $this->queryBus->dispatch(new GetUserById($id));
$handledStamp = $envelope->last(HandledStamp::class);
$userDTO = $handledStamp->getResult();
```

## Query Bus Helper Trait

```php
namespace App\Presentation\Shared;

use Symfony\Component\Messenger\MessageBusInterface;
use Symfony\Component\Messenger\Stamp\HandledStamp;

trait QueryBusTrait
{
    private readonly MessageBusInterface $queryBus;

    protected function query(object $query): mixed
    {
        $envelope = $this->queryBus->dispatch($query);
        $handledStamp = $envelope->last(HandledStamp::class);
        return $handledStamp?->getResult();
    }
}
```
