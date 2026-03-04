# Bus Configuration

## Messenger Configuration

```yaml
# config/packages/messenger.yaml
framework:
    messenger:
        # Default bus
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
                default_middleware: allow_no_handlers
                middleware:
                    - validation

        transports:
            async:
                dsn: '%env(MESSENGER_TRANSPORT_DSN)%'
                retry_strategy:
                    max_retries: 3
                    delay: 1000
                    multiplier: 2
                    max_delay: 60000
            failed:
                dsn: 'doctrine://default?queue_name=failed'

        failure_transport: failed

        routing:
            # Route specific commands/events to async
            # 'App\Application\Report\Command\GenerateReport': async
```

## services.yaml Bus Binding

```yaml
# config/services.yaml
services:
    _defaults:
        autowire: true
        autoconfigure: true
        bind:
            $commandBus: '@command.bus'
            $queryBus: '@query.bus'
            $eventBus: '@event.bus'
```

## Controller Usage

```php
namespace App\Presentation\User\API;

use Symfony\Component\Messenger\MessageBusInterface;
use Symfony\Component\Messenger\Stamp\HandledStamp;

final class UserController
{
    public function __construct(
        private readonly MessageBusInterface $commandBus,
        private readonly MessageBusInterface $queryBus,
    ) {
    }

    public function register(Request $request): JsonResponse
    {
        $command = new RegisterUser(/* ... */);
        $envelope = $this->commandBus->dispatch($command);
        $userId = $envelope->last(HandledStamp::class)?->getResult();

        return $this->success(['id' => $userId], 201);
    }

    public function show(string $id): JsonResponse
    {
        $query = new GetUserById($id);
        $envelope = $this->queryBus->dispatch($query);
        $user = $envelope->last(HandledStamp::class)?->getResult();

        if ($user === null) {
            return $this->error('User not found', 404);
        }

        return $this->success($user);
    }
}
```

## Middleware Order

The order of middleware matters:

1. **validation** — Validates the message (command/query) before handling
2. **doctrine_transaction** — Wraps handler in a database transaction (command bus only)
3. Custom middleware (logging, authorization, etc.)

```yaml
command.bus:
    middleware:
        - validation                # 1st: validate input
        - doctrine_transaction      # 2nd: wrap in transaction
        # - App\Infrastructure\Shared\Middleware\LoggingMiddleware  # optional
```

## Custom Middleware Example

```php
namespace App\Infrastructure\Shared\Middleware;

use Psr\Log\LoggerInterface;
use Symfony\Component\Messenger\Envelope;
use Symfony\Component\Messenger\Middleware\MiddlewareInterface;
use Symfony\Component\Messenger\Middleware\StackInterface;

final readonly class LoggingMiddleware implements MiddlewareInterface
{
    public function __construct(
        private LoggerInterface $logger,
    ) {
    }

    public function handle(Envelope $envelope, StackInterface $stack): Envelope
    {
        $message = $envelope->getMessage();
        $this->logger->info('Handling message', ['class' => get_class($message)]);

        try {
            $envelope = $stack->next()->handle($envelope, $stack);
            $this->logger->info('Message handled successfully', ['class' => get_class($message)]);
            return $envelope;
        } catch (\Throwable $e) {
            $this->logger->error('Message handling failed', [
                'class' => get_class($message),
                'error' => $e->getMessage(),
            ]);
            throw $e;
        }
    }
}
```

## Testing Handlers Directly

Since handlers use `__invoke`, they can be tested without the bus:

```php
final class RegisterUserHandlerTest extends TestCase
{
    public function test_it_registers_a_user(): void
    {
        $repository = $this->createMock(UserRepositoryInterface::class);
        $repository->expects($this->once())->method('save');

        $handler = new RegisterUserHandler($repository);
        $result = $handler(new RegisterUser('test@example.com', 'Test User', 'password123'));

        $this->assertNotEmpty($result);
    }
}
```
