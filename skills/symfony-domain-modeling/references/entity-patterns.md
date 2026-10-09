# Entity Patterns

## Aggregate Root Pattern

An aggregate root is the entry point to a cluster of domain objects. All modifications go through the root.

```php
namespace App\Domain\Order\Entity;

use App\Domain\Order\Event\OrderCancelled;
use App\Domain\Order\Event\OrderConfirmed;
use App\Domain\Order\Event\OrderItemAdded;
use App\Domain\Order\Event\OrderPlaced;
use App\Domain\Order\Exception\EmptyOrderException;
use App\Domain\Order\Exception\InvalidOrderTransitionException;
use App\Domain\Order\ValueObject\OrderId;
use App\Domain\Order\ValueObject\OrderStatus;
use App\Domain\Shared\Event\DomainEvent;
use App\Domain\Shared\ValueObject\Money;

final class Order
{
    /** @var list<DomainEvent> */
    private array $domainEvents = [];

    /**
     * Plain array in Domain. When Doctrine hydrates the aggregate it puts a
     * PersistentCollection here (ArrayAccess + iterable), so only use `[] =`
     * and `foreach` on it. Untyped on purpose: no Doctrine import in Domain.
     *
     * @var array<int, OrderItem>
     */
    private $items = [];

    private function __construct(
        private OrderId $id,
        private string $customerId,
        private OrderStatus $status,
        private string $currency,
        private \DateTimeImmutable $placedAt,
    ) {
    }

    public static function place(OrderId $id, string $customerId, string $currency, \DateTimeImmutable $now): self
    {
        $order = new self($id, $customerId, OrderStatus::PENDING, $currency, $now);
        $order->recordEvent(new OrderPlaced($id->value, $customerId, $now));

        return $order;
    }

    public function addItem(string $productId, int $quantity, Money $unitPrice, \DateTimeImmutable $now): void
    {
        if (!$this->isPending()) {
            throw InvalidOrderTransitionException::itemsLocked($this->id->value, $this->status);
        }

        $this->items[] = new OrderItem($this, $productId, $quantity, $unitPrice);

        $this->recordEvent(new OrderItemAdded($this->id->value, $productId, $quantity, $now));
    }

    public function confirm(\DateTimeImmutable $now): void
    {
        $this->transitionTo(OrderStatus::CONFIRMED);
        $this->recordEvent(new OrderConfirmed($this->id->value, $now));
    }

    public function cancel(string $reason, \DateTimeImmutable $now): void
    {
        $this->transitionTo(OrderStatus::CANCELLED);
        $this->recordEvent(new OrderCancelled($this->id->value, $reason, $now));
    }

    public function totalAmount(): Money
    {
        $total = Money::zero($this->currency);
        $hasItems = false;
        foreach ($this->items as $item) {
            $total = $total->add($item->subtotal());
            $hasItems = true;
        }

        if (!$hasItems) {
            throw EmptyOrderException::becauseNoItems($this->id->value);
        }

        return $total;
    }

    public function id(): OrderId
    {
        return $this->id;
    }

    public function customerId(): string
    {
        return $this->customerId;
    }

    public function status(): OrderStatus
    {
        return $this->status;
    }

    public function isPending(): bool
    {
        return $this->status === OrderStatus::PENDING;
    }

    /** @return list<DomainEvent> */
    public function pullDomainEvents(): array
    {
        $events = $this->domainEvents;
        $this->domainEvents = [];

        return $events;
    }

    private function transitionTo(OrderStatus $target): void
    {
        if (!$this->status->canTransitionTo($target)) {
            throw InvalidOrderTransitionException::from($this->id->value, $this->status, $target);
        }

        $this->status = $target;
    }

    private function recordEvent(DomainEvent $event): void
    {
        $this->domainEvents[] = $event;
    }
}
```

> Trade-off: phpstan-doctrine may report that the `items` association is not typed as `Collection`. Either accept a baseline entry for it, or (if your team allows it) permit `Doctrine\Common\Collections` in Domain as the single exception; that package has no ORM dependency.

## Child Entity (Part of Aggregate)

```php
namespace App\Domain\Order\Entity;

use App\Domain\Order\Exception\InvalidQuantityException;
use App\Domain\Shared\ValueObject\Money;

final class OrderItem
{
    private ?int $id = null; // surrogate key, assigned by the database

    public function __construct(
        private readonly Order $order,
        private readonly string $productId,
        private readonly int $quantity,
        private readonly Money $unitPrice,
    ) {
        if ($quantity <= 0) {
            throw InvalidQuantityException::mustBePositive($quantity);
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

The back-reference `$order` exists because the Doctrine `one-to-many` mapping needs an owning `many-to-one` side (see doctrine-persistence `mapping-patterns.md`).

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
            self::PENDING => in_array($target, [self::CONFIRMED, self::CANCELLED], true),
            self::CONFIRMED => in_array($target, [self::SHIPPED, self::CANCELLED], true),
            self::SHIPPED => $target === self::DELIVERED,
            self::DELIVERED, self::CANCELLED => false,
        };
    }
}
```

## PHP 8.4+ Variant (Symfony 8 projects only)

Asymmetric visibility removes getter boilerplate while keeping writes inside the aggregate. Requires PHP 8.4 and Doctrine ORM 3.4+:

```php
final class Customer
{
    public function __construct(
        public private(set) CustomerId $id,
        public private(set) Email $email,
    ) {
    }

    public function changeEmail(Email $email): void
    {
        $this->email = $email; // allowed inside the class, read-only from outside
    }
}
```

Do not generate this on PHP 8.2/8.3 projects: it is a parse error there.

## Domain Event Dispatching via Repository

The repository adapter dispatches domain events after persistence, delayed until the current command finishes:

```php
// In Infrastructure - NOT in Domain
namespace App\Infrastructure\Order\Persistence;

use App\Domain\Order\Entity\Order;
use App\Domain\Order\Port\OrderRepositoryInterface;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Component\Messenger\MessageBusInterface;
use Symfony\Component\Messenger\Stamp\DispatchAfterCurrentBusStamp;

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
            $this->eventBus->dispatch($event, [new DispatchAfterCurrentBusStamp()]);
        }
    }
}
```
