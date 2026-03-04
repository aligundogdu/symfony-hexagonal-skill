# Idempotency Patterns

## Why Idempotency Matters

Async messages can be delivered more than once (network retries, worker restarts). Every handler must be safe to execute multiple times with the same input.

## Pattern 1: Idempotency Key in Command

```php
final readonly class ProcessPayment
{
    public function __construct(
        public string $orderId,
        public string $idempotencyKey, // unique per operation
        public int $amount,
        public string $currency,
    ) {
    }
}

#[AsMessageHandler(bus: 'command.bus')]
final readonly class ProcessPaymentHandler
{
    public function __construct(
        private PaymentRepositoryInterface $paymentRepository,
        private PaymentGatewayInterface $gateway,
    ) {
    }

    public function __invoke(ProcessPayment $command): void
    {
        // Check if already processed
        if ($this->paymentRepository->existsByIdempotencyKey($command->idempotencyKey)) {
            return; // Skip — already done
        }

        $result = $this->gateway->charge($command->orderId, $command->amount);
        $this->paymentRepository->saveWithIdempotencyKey($result, $command->idempotencyKey);
    }
}
```

## Pattern 2: Status Check Before Action

```php
#[AsMessageHandler(bus: 'command.bus')]
final readonly class ConfirmOrderHandler
{
    public function __invoke(ConfirmOrder $command): void
    {
        $order = $this->orderRepository->findById($command->orderId);

        // Guard: only process if in correct state
        if ($order === null || !$order->isPending()) {
            return; // Already confirmed/cancelled, skip
        }

        $order->confirm();
        $this->orderRepository->save($order);
    }
}
```

## Pattern 3: Database Unique Constraint

Use a database unique constraint as a safeguard:

```sql
CREATE TABLE processed_messages (
    idempotency_key VARCHAR(255) PRIMARY KEY,
    processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

```php
final readonly class IdempotencyGuard
{
    public function __construct(
        private Connection $connection,
    ) {
    }

    public function ensureNotProcessed(string $key): void
    {
        try {
            $this->connection->insert('processed_messages', [
                'idempotency_key' => $key,
            ]);
        } catch (UniqueConstraintViolationException) {
            throw new MessageAlreadyProcessedException($key);
        }
    }
}
```

## Pattern 4: Stamp-Based Deduplication

```php
namespace App\Infrastructure\Shared\Stamp;

use Symfony\Component\Messenger\Stamp\StampInterface;

final readonly class IdempotencyStamp implements StampInterface
{
    public function __construct(
        public string $key,
    ) {
    }
}

// Middleware that checks the stamp
final readonly class IdempotencyMiddleware implements MiddlewareInterface
{
    public function __construct(
        private Connection $connection,
    ) {
    }

    public function handle(Envelope $envelope, StackInterface $stack): Envelope
    {
        $stamp = $envelope->last(IdempotencyStamp::class);
        if ($stamp !== null) {
            if ($this->alreadyProcessed($stamp->key)) {
                return $envelope; // Skip processing
            }
        }

        $result = $stack->next()->handle($envelope, $stack);

        if ($stamp !== null) {
            $this->markProcessed($stamp->key);
        }

        return $result;
    }
}
```

## Generating Idempotency Keys

```php
// From controller — generate before dispatch:
$idempotencyKey = sprintf('payment_%s_%s', $orderId, $request->headers->get('X-Idempotency-Key', uniqid()));

$command = new ProcessPayment(
    orderId: $orderId,
    idempotencyKey: $idempotencyKey,
    amount: $amount,
    currency: $currency,
);

$this->commandBus->dispatch($command);
```
