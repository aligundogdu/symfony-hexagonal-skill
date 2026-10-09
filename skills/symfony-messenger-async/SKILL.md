---
name: symfony-messenger-async
description: "Symfony Messenger async processing and Symfony Scheduler instead of cron: transports, routing (#[AsMessage] 7.2+), retry with backoff and jitter, failure transport, idempotency keys, DeduplicateStamp (7.3+), workers, supervisor, scheduled commands with stateful/locked schedules. Use when: messenger, async, queue, retry, scheduler, background job, worker, transport, message queue, cron, scheduled task, idempotency, deduplication"
---

# Symfony Messenger & Async Processing

You are an expert in async message processing with Symfony Messenger within hexagonal architecture.

## When to Activate

- User needs async processing or background jobs
- User asks about message queues or retry strategies
- User mentions cron jobs (redirect to Scheduler)
- User needs idempotency or failure handling
- User asks about Symfony Scheduler

## Core Principle: No Cron Jobs

**Never use raw cron.** Always use:
- **Symfony Messenger** for async message processing
- **Symfony Scheduler** for recurring tasks (dispatching regular CQRS commands)

## Version Notes

| Feature | Requires | Fallback |
|---|---|---|
| Scheduler component, `RecurringMessage` | Symfony 6.3 | - (no cron) |
| `#[AsCronTask]`, `#[AsPeriodicTask]` | Symfony 6.4 | `ScheduleProviderInterface` |
| `retry_strategy.jitter` | Symfony 7.1 | omit |
| `#[AsMessage('async')]` routing attribute | Symfony 7.2 | YAML `routing:` |
| `DeduplicateStamp` (+ symfony/lock) | Symfony 7.3 | idempotency key + unique constraint |
| `messenger:consume --keepalive` | Symfony 7.2/7.3 (transport dependent) | shorter `--time-limit` |
| `#[AsMessageHandler(sign: true)]` message signing | Symfony 7.4 | trusted transport |
| `messenger:consume --all --exclude-receivers=failed` | Symfony 7.4 | list receivers explicitly |
| `#[AsMessage(serializedTypeName: ...)]`, `PriorityStamp`, regex receiver names | Symfony 8.1 | FQCN type names, separate priority transports |

## Async Command Pattern

```php
// The command is the same: async is a routing concern, not a code concern
namespace App\Application\Report\Command;

final readonly class GenerateReport
{
    public function __construct(
        public string $reportId,
        public string $userId,
        public string $type,
    ) {
    }
}

// Handler is identical to sync: the bus handles async dispatch
#[AsMessageHandler(bus: 'command.bus')]
final readonly class GenerateReportHandler
{
    public function __invoke(GenerateReport $command): void
    {
        // Long-running operation
    }
}
```

```yaml
# Route to async transport (all versions)
framework:
    messenger:
        routing:
            'App\Application\Report\Command\GenerateReport': async
```

Symfony 7.2+: `#[AsMessage('async')]` on the command class works too. Never put it on **domain events**: Domain must stay free of Symfony attributes, so events are always routed in YAML.

## Idempotency

Every async handler MUST be idempotent: messages can be delivered more than once (retries, worker crashes, redeliveries).

```php
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
            return; // Already processed, skip
        }

        $result = $this->gateway->charge(
            $command->customerId,
            new Money($command->amount, $command->currency),
            sprintf('Order %s', $command->orderId),
            $command->idempotencyKey, // the provider deduplicates too
        );
        $this->payments->record($command->orderId, $result, $command->idempotencyKey);
    }
}
```

Symfony 7.3+ adds `DeduplicateStamp`, which prevents the **same message from being queued twice** while one is pending. It complements, but does not replace, handler idempotency (see `references/idempotency-patterns.md`).

## References

See `references/` for detailed guides:
- `messenger-config.md` - Full Messenger YAML configuration, workers, failure transport
- `idempotency-patterns.md` - Idempotency key strategies, DeduplicateStamp
- `scheduler-patterns.md` - Symfony Scheduler setup and patterns
