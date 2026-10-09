# Domain Event Patterns

## Rules
- Past-tense naming: something that already happened
- `final readonly class`, immutable after creation
- Carry IDs and scalar data, not entity references (events are serialized when routed async)
- Include an `occurredOn` timestamp passed in by the entity
- Created inside entities on state changes
- Dispatched by infrastructure (repository adapter) after persistence, delayed until the command succeeded

## Event Naming Convention

| Action | Event Name |
|--------|-----------|
| User registers | `UserRegistered` |
| Order is placed | `OrderPlaced` |
| Payment fails | `PaymentFailed` |
| Product price changes | `ProductPriceChanged` |
| Account is suspended | `AccountSuspended` |

## Base Event Interface (Shared Kernel)

```php
namespace App\Domain\Shared\Event;

interface DomainEvent
{
    public function aggregateId(): string;

    public function occurredOn(): \DateTimeImmutable;
}
```

## Event Template

```php
namespace App\Domain\User\Event;

use App\Domain\Shared\Event\DomainEvent;

final readonly class UserRegistered implements DomainEvent
{
    public function __construct(
        public string $userId,
        public string $email,
        public \DateTimeImmutable $occurredOn,
    ) {
    }

    public function aggregateId(): string
    {
        return $this->userId;
    }

    public function occurredOn(): \DateTimeImmutable
    {
        return $this->occurredOn;
    }
}
```

## Event Handler (Application Layer)

Event handlers live in `Application/{Module}/EventHandler/` and handle side-effects:

```php
namespace App\Application\User\EventHandler;

use App\Domain\Notification\Port\NotificationServiceInterface;
use App\Domain\User\Event\UserRegistered;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;

#[AsMessageHandler(bus: 'event.bus')]
final readonly class WhenUserRegisteredSendWelcomeEmail
{
    public function __construct(
        private NotificationServiceInterface $notificationService,
    ) {
    }

    public function __invoke(UserRegistered $event): void
    {
        $this->notificationService->sendWelcomeEmail($event->userId, $event->email);
    }
}
```

## Event Handler Naming Convention

Use `When{Event}{Action}` pattern:
- `WhenUserRegisteredSendWelcomeEmail`
- `WhenOrderPlacedReserveInventory`
- `WhenPaymentFailedNotifyCustomer`
- `WhenProductPriceChangedUpdateCatalog`

## Event Dispatch Flow

```
1. Command handler calls Entity.doAction()  → entity records event internally
2. Repository.save(entity)                   → persist + flush (inside doctrine_transaction)
3. Repository pulls events                   → eventBus->dispatch($event, [new DispatchAfterCurrentBusStamp()])
4. Command bus finishes, transaction commits → delayed events are released to event.bus
5. event.bus routes them (sync handlers, or async transport via messenger.yaml routing)
```

Why `DispatchAfterCurrentBusStamp`: without it, a sync event handler sends the welcome email even when the command's transaction later rolls back. The stamp is only valid while a bus is handling a message, so call `save()` from handlers (as the architecture requires anyway). For guaranteed delivery across process crashes, route events to an async **Doctrine** transport in the same database (transactional outbox behavior).

## Multiple Handlers per Event

One event can trigger multiple handlers. Each handler should be independent:

```php
// Handler 1: Send email
#[AsMessageHandler(bus: 'event.bus')]
final readonly class WhenOrderPlacedSendConfirmation { /* ... */ }

// Handler 2: Reserve inventory
#[AsMessageHandler(bus: 'event.bus')]
final readonly class WhenOrderPlacedReserveInventory { /* ... */ }

// Handler 3: Update analytics
#[AsMessageHandler(bus: 'event.bus')]
final readonly class WhenOrderPlacedTrackAnalytics { /* ... */ }
```

When an event is routed async and has several handlers, a failure in one handler is retried for that handler only (Messenger tracks handled handlers per envelope), so handlers must still be idempotent.

## Cross-Module Events

When Module A needs to react to Module B's events, the handler lives in Module A's Application layer:

```php
// Order module reacts to Payment module's event
namespace App\Application\Order\EventHandler;

use App\Domain\Order\Port\OrderRepositoryInterface;
use App\Domain\Order\ValueObject\OrderId;
use App\Domain\Payment\Event\PaymentReceived;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;

#[AsMessageHandler(bus: 'event.bus')]
final readonly class WhenPaymentReceivedConfirmOrder
{
    public function __construct(
        private OrderRepositoryInterface $orderRepository,
    ) {
    }

    public function __invoke(PaymentReceived $event): void
    {
        $order = $this->orderRepository->findById(new OrderId($event->orderId));
        if ($order === null || !$order->isPending()) {
            return; // idempotent: already confirmed or unknown
        }

        $order->confirm();
        $this->orderRepository->save($order);
    }
}
```

## Messenger Bus Configuration for Events

```yaml
# config/packages/messenger.yaml
framework:
    messenger:
        default_bus: command.bus
        buses:
            command.bus:
                middleware:
                    - validation
                    - doctrine_transaction
            query.bus:
                middleware:
                    - validation
            event.bus:
                default_middleware:
                    enabled: true
                    allow_no_handlers: true
        routing:
            # Domain events stay attribute-free, so route them here
            'App\Domain\User\Event\UserRegistered': async
```

`default_middleware: allow_no_handlers` (shorthand) is still accepted; the expanded form above is the documented one.
