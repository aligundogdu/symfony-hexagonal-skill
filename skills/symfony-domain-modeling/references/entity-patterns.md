# Entity Patterns

## Aggregate Root Pattern

An aggregate root is the entry point to a cluster of domain objects. All modifications go through the root.

```php
namespace App\Domain\Order\Entity;

use App\Domain\Order\Event\OrderPlaced;
use App\Domain\Order\Event\OrderItemAdded;
use App\Domain\Order\Event\OrderCancelled;
use App\Domain\Order\Exception\OrderAlreadyCancelledException;
use App\Domain\Order\Exception\EmptyOrderException;
use App\Domain\Order\ValueObject\OrderId;
use App\Domain\Order\ValueObject\OrderStatus;
use App\Domain\Shared\ValueObject\Money;

final class Order
{
    private array $domainEvents = [];
    /** @var OrderItem[] */
    private array $items = [];

    private function __construct(
        private OrderId $id,
        private string $customerId,
        private OrderStatus $status,
        private \DateTimeImmutable $createdAt,
    ) {
    }

    public static function place(OrderId $id, string $customerId): self
    {
        $order = new self($id, $customerId, OrderStatus::PENDING, new \DateTimeImmutable());
        $order->recordEvent(new OrderPlaced($id->value, $customerId));
        return $order;
    }

    public function addItem(string $productId, int $quantity, Money $price): void
    {
        $this->guardNotCancelled();
        $item = new OrderItem($productId, $quantity, $price);
        $this->items[] = $item;
        $this->recordEvent(new OrderItemAdded($this->id->value, $productId, $quantity));
    }

    public function cancel(string $reason): void
    {
        $this->guardNotCancelled();
        $this->status = OrderStatus::CANCELLED;
        $this->recordEvent(new OrderCancelled($this->id->value, $reason));
    }

    public function totalAmount(): Money
    {
        if (empty($this->items)) {
            throw EmptyOrderException::becauseNoItems($this->id->value);
        }

        return array_reduce(
            $this->items,
            fn (Money $total, OrderItem $item) => $total->add($item->subtotal()),
            Money::zero('EUR'),
        );
    }

    public function id(): OrderId
    {
        return $this->id;
    }

    public function status(): OrderStatus
    {
        return $this->status;
    }

    private function guardNotCancelled(): void
    {
        if ($this->status === OrderStatus::CANCELLED) {
            throw OrderAlreadyCancelledException::forOrder($this->id->value);
        }
    }

    public function pullDomainEvents(): array
    {
        $events = $this->domainEvents;
        $this->domainEvents = [];
        return $events;
    }

    private function recordEvent(object $event): void
    {
        $this->domainEvents[] = $event;
    }
}
```

## Child Entity (Part of Aggregate)

```php
namespace App\Domain\Order\Entity;

use App\Domain\Shared\ValueObject\Money;

final class OrderItem
{
    public function __construct(
        private readonly string $productId,
        private readonly int $quantity,
        private readonly Money $unitPrice,
    ) {
        if ($quantity <= 0) {
            throw new \InvalidArgumentException('Quantity must be positive');
        }
    }

    public function subtotal(): Money
    {
        return $this->unitPrice->multiply($this->quantity);
    }

    public function productId(): string
    {
        return $this->productId;
    }

    public function quantity(): int
    {
        return $this->quantity;
    }
}
```

## Status Enum (Part of Domain)

```php
namespace App\Domain\Order\ValueObject;

enum OrderStatus: string
{
    case PENDING = 'pending';
    case CONFIRMED = 'confirmed';
    case SHIPPED = 'shipped';
    case DELIVERED = 'delivered';
    case CANCELLED = 'cancelled';

    public function canTransitionTo(self $target): bool
    {
        return match ($this) {
            self::PENDING => in_array($target, [self::CONFIRMED, self::CANCELLED]),
            self::CONFIRMED => in_array($target, [self::SHIPPED, self::CANCELLED]),
            self::SHIPPED => $target === self::DELIVERED,
            self::DELIVERED, self::CANCELLED => false,
        };
    }
}
```

## Domain Event Dispatching via Repository

The repository adapter is responsible for dispatching domain events after persistence:

```php
// In Infrastructure - NOT in Domain
namespace App\Infrastructure\Order\Persistence;

use App\Domain\Order\Entity\Order;
use App\Domain\Order\Port\OrderRepositoryInterface;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Component\Messenger\MessageBusInterface;

final readonly class DoctrineOrderRepository implements OrderRepositoryInterface
{
    public function __construct(
        private EntityManagerInterface $entityManager,
        private MessageBusInterface $eventBus,
    ) {
    }

    public function save(Order $order): void
    {
        $this->entityManager->persist($order);
        $this->entityManager->flush();

        foreach ($order->pullDomainEvents() as $event) {
            $this->eventBus->dispatch($event);
        }
    }
}
```
