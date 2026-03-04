# Domain Event Patterns

## Rules
- Past-tense naming: something that already happened
- `final readonly class` — immutable after creation
- Carry IDs and scalar data, not entity references
- Include `occurredAt` timestamp
- Created inside entities on state changes
- Dispatched by infrastructure (repository adapter) after persistence

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
    public function occurredAt(): \DateTimeImmutable;
    public function aggregateId(): string;
}
```

## Event Template

```php
namespace App\Domain\{Module}\Event;

use App\Domain\Shared\Event\DomainEvent;

final readonly class {EntityAction} implements DomainEvent
{
    public function __construct(
        private string $entityId,
        // additional data relevant to the event
        private \DateTimeImmutable $occurredAt = new \DateTimeImmutable(),
    ) {
    }

    public function aggregateId(): string
    {
        return $this->entityId;
    }

    public function occurredAt(): \DateTimeImmutable
    {
        return $this->occurredAt;
    }
}
```

## Event Handler (Application Layer)

Event handlers live in `Application/{Module}/EventHandler/` and handle side-effects:

```php
namespace App\Application\User\EventHandler;

use App\Domain\User\Event\UserRegistered;
use App\Domain\Notification\Port\NotificationServiceInterface;
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
1. Entity.doAction() → records event internally
2. Repository.save(entity) → persists to DB
3. Repository pulls events from entity → dispatches to event bus
4. Event bus → routes to registered handlers
5. Handlers execute side-effects
```

## Multiple Handlers per Event

One event can trigger multiple handlers. Each handler should be independent:

```php
// Handler 1: Send email
#[AsMessageHandler(bus: 'event.bus')]
final readonly class WhenOrderPlacedSendConfirmation { ... }

// Handler 2: Reserve inventory
#[AsMessageHandler(bus: 'event.bus')]
final readonly class WhenOrderPlacedReserveInventory { ... }

// Handler 3: Update analytics
#[AsMessageHandler(bus: 'event.bus')]
final readonly class WhenOrderPlacedTrackAnalytics { ... }
```

## Cross-Module Events

When Module A needs to react to Module B's events, the handler lives in Module A's Application layer:

```php
// Order module reacts to Payment module's event
namespace App\Application\Order\EventHandler;

use App\Domain\Payment\Event\PaymentReceived;
use App\Domain\Order\Port\OrderRepositoryInterface;
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
        $order = $this->orderRepository->findById($event->orderId);
        $order?->confirm();
        if ($order !== null) {
            $this->orderRepository->save($order);
        }
    }
}
```

## Messenger Bus Configuration for Events

```yaml
# config/packages/messenger.yaml
framework:
    messenger:
        buses:
            command.bus:
                middleware:
                    - doctrine_transaction
            query.bus: ~
            event.bus:
                default_middleware: allow_no_handlers
```
