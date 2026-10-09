# Idempotency Patterns

## Why Idempotency Matters

Async messages can be delivered more than once (network retries, worker restarts, retry strategy). Every handler must be safe to execute multiple times with the same input.

## Pattern 1: Idempotency Key in Command

```php
final readonly class ProcessPayment
{
    public function __construct(
        public string $orderId,
        public string $customerId,
        public string $idempotencyKey, // unique per business operation
        public int $amount,            // minor units
        public string $currency,
    ) {
    }
}

#[AsMessageHandler(bus: 'command.bus')]
final readonly class ProcessPaymentHandler
{
    public function __construct(
        private PaymentRepositoryInterface $payments,
        private PaymentGatewayInterface $gateway,
    ) {
    }

    public function __invoke(ProcessPayment $command): void
    {
        if ($this->payments->existsByIdempotencyKey($command->idempotencyKey)) {
            return; // Skip, already done
        }

        $result = $this->gateway->charge(
            $command->customerId,
            new Money($command->amount, $command->currency),
            sprintf('Order %s', $command->orderId),
            $command->idempotencyKey,
        );
        $this->payments->record($command->orderId, $result, $command->idempotencyKey);
    }
}
```

## Pattern 2: Status Check Before Action

```php
#[AsMessageHandler(bus: 'command.bus')]
final readonly class ConfirmOrderHandler
{
    public function __construct(
        private OrderRepositoryInterface $orders,
    ) {
    }

    public function __invoke(ConfirmOrder $command): void
    {
        $order = $this->orders->findById(new OrderId($command->orderId));

        // Guard: only process if in correct state
        if ($order === null || !$order->isPending()) {
            return; // Already confirmed/cancelled, skip
        }

        $order->confirm(new \DateTimeImmutable());
        $this->orders->save($order);
    }
}
```

## Pattern 3: Database Unique Constraint (processed-messages table)

The table is created by a migration (raw SQL is allowed only there). The guard itself uses DBAL's `insert()` API, not SQL strings:

```php
namespace App\Infrastructure\Shared\Messaging;

use App\Domain\Shared\Exception\AlreadyProcessedException;
use App\Domain\Shared\Port\IdempotencyGuardInterface;
use Doctrine\DBAL\Connection;
use Doctrine\DBAL\Exception\UniqueConstraintViolationException;

final readonly class DbalIdempotencyGuard implements IdempotencyGuardInterface
{
    public function __construct(
        private Connection $connection,
    ) {
    }

    public function claim(string $key): void
    {
        try {
            $this->connection->insert('processed_messages', [
                'idempotency_key' => $key,
                'processed_at' => (new \DateTimeImmutable())->format('Y-m-d H:i:s'),
            ]);
        } catch (UniqueConstraintViolationException) {
            throw AlreadyProcessedException::forKey($key);
        }
    }
}
```

Call `claim()` inside the command's `doctrine_transaction`: if the handler fails, the claim rolls back with it and the retry can run again.

## Pattern 4: DeduplicateStamp (Symfony 7.3+)

Prevents queueing a message while an identical one (same lock key) is still pending. Requires `symfony/lock` with a store that supports serialization (Redis, PDO/Doctrine DBAL, ...); the middleware then enables itself.

```php
use Symfony\Component\Messenger\Stamp\DeduplicateStamp;

$this->commandBus->dispatch(
    new RebuildSearchIndex($productId),
    [new DeduplicateStamp('rebuild-index-' . $productId)],
);
```

Use it for "collapse repeated triggers" cases (re-index, cache warmup, sync jobs). It does **not** make a handler idempotent: once the first message is consumed, an identical one can be queued again. Keep Patterns 1-3 for operations with real side effects (payments, emails).

On Symfony < 7.3, implement the same with a custom stamp + middleware that checks a lock/claim table before sending.

## Generating Idempotency Keys

The key must be **stable across client retries**, so it comes from the client or from the business operation. Never use `uniqid()` or random fallbacks: a random key makes every retry look new.

```php
// App\Presentation\Payment\API\PaymentController (action excerpt)
#[Route('/api/orders/{orderId}/payments', methods: ['POST'])]
#[IsGranted('ORDER_PAY', subject: 'orderId')]
public function pay(string $orderId, Request $request, #[MapRequestPayload] PayOrderRequest $body): JsonResponse
{
    $clientKey = $request->headers->get('Idempotency-Key');
    if ($clientKey === null || $clientKey === '') {
        return $this->error('Idempotency-Key header is required', 400, 'IDEMPOTENCY_KEY_REQUIRED');
    }

    $this->commandBus->dispatch(new ProcessPayment(
        orderId: $orderId,
        customerId: $body->customerId,
        idempotencyKey: sprintf('payment:%s:%s', $orderId, $clientKey),
        amount: $body->amount,
        currency: $body->currency,
    ));

    return $this->accepted(['orderId' => $orderId]);
}
```

Symfony 8.1+: `#[MapRequestHeader(name: 'Idempotency-Key')] string $clientKey` replaces the manual header read (missing header → 400).

For internally triggered commands, derive the key from the business fact: `sprintf('welcome-email:%s', $event->userId)`.
