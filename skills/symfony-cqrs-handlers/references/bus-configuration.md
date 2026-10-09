# Bus Configuration

## Messenger Configuration (Symfony 6.4, 7.x, 8.x)

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
                    # jitter: 0.1   # Symfony 7.1+
            failed:
                dsn: 'doctrine://default?queue_name=failed'

        failure_transport: failed

        routing:
            # Route specific commands/events to async
            # 'App\Application\Report\Command\GenerateReport': async
            # 'App\Domain\User\Event\UserRegistered': async

when@test:
    framework:
        messenger:
            transports:
                async: 'in-memory://'
```

## Bus Wrappers (Presentation helpers)

Raw `MessageBusInterface::dispatch()` returns an `Envelope`, not the handler result, and wraps every handler exception in `HandlerFailedException`. Two tiny wrappers fix both, and live in Presentation (which may use Symfony), so no layer rule is bent.

```php
namespace App\Presentation\Shared\Bus;

use Symfony\Component\DependencyInjection\Attribute\Autowire;
use Symfony\Component\Messenger\Exception\HandlerFailedException;
use Symfony\Component\Messenger\MessageBusInterface;
use Symfony\Component\Messenger\Stamp\HandledStamp;
use Symfony\Component\Messenger\Stamp\StampInterface;

final readonly class CommandBus
{
    public function __construct(
        #[Autowire(service: 'command.bus')]
        private MessageBusInterface $commandBus,
    ) {
    }

    /**
     * Returns the handler result for sync commands (e.g. a new ID), null when routed async.
     *
     * @param list<StampInterface> $stamps
     */
    public function dispatch(object $command, array $stamps = []): mixed
    {
        try {
            $envelope = $this->commandBus->dispatch($command, $stamps);
        } catch (HandlerFailedException $e) {
            throw $e->getPrevious() ?? $e; // the original domain exception
        }

        return $envelope->last(HandledStamp::class)?->getResult();
    }
}
```

```php
namespace App\Presentation\Shared\Bus;

use Symfony\Component\DependencyInjection\Attribute\Autowire;
use Symfony\Component\Messenger\Exception\HandlerFailedException;
use Symfony\Component\Messenger\HandleTrait;
use Symfony\Component\Messenger\MessageBusInterface;

final class QueryBus
{
    use HandleTrait;

    public function __construct(
        #[Autowire(service: 'query.bus')]
        MessageBusInterface $queryBus,
    ) {
        $this->messageBus = $queryBus;
    }

    /**
     * Exactly one handler must handle the query (HandleTrait enforces it).
     */
    public function ask(object $query): mixed
    {
        try {
            return $this->handle($query);
        } catch (HandlerFailedException $e) {
            throw $e->getPrevious() ?? $e;
        }
    }
}
```

`#[Autowire(service: ...)]` works on Symfony 6.1+. Alternative: `bind: { $commandBus: '@command.bus' }` in `services.yaml`.

## Controller Usage

```php
namespace App\Presentation\User\API;

use App\Application\User\Command\RegisterUser;
use App\Application\User\DTO\UserDTO;
use App\Application\User\Query\GetUserById;
use App\Presentation\Shared\ApiResponseTrait;
use App\Presentation\Shared\Bus\CommandBus;
use App\Presentation\Shared\Bus\QueryBus;
use App\Presentation\User\API\Request\RegisterUserRequest;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpKernel\Attribute\MapRequestPayload;
use Symfony\Component\Routing\Attribute\Route;
use Symfony\Component\Security\Http\Attribute\IsGranted;

#[Route('/api/users')]
final class UserController
{
    use ApiResponseTrait;

    public function __construct(
        private readonly CommandBus $commandBus,
        private readonly QueryBus $queryBus,
    ) {
    }

    #[Route('', methods: ['POST'])]
    #[IsGranted('ROLE_USER_CREATE')]
    public function register(#[MapRequestPayload] RegisterUserRequest $request): JsonResponse
    {
        $userId = $this->commandBus->dispatch(
            new RegisterUser($request->email, $request->name, $request->password),
        );

        return $this->created(['id' => $userId]);
    }

    #[Route('/{id}', methods: ['GET'])]
    #[IsGranted('ROLE_USER_VIEW')]
    public function show(string $id): JsonResponse
    {
        /** @var UserDTO|null $user */
        $user = $this->queryBus->ask(new GetUserById($id));

        if ($user === null) {
            return $this->error('User not found', 404, 'USER_NOT_FOUND');
        }

        return $this->success($user);
    }
}
```

## Middleware Order

The order of middleware matters:

1. **validation** - Validates the message (command/query) before handling
2. **doctrine_transaction** - Wraps handler in a database transaction (command bus only)
3. Custom middleware (logging, authorization, etc.)

Default middleware (including `dispatch_after_current_bus`, which releases `DispatchAfterCurrentBusStamp` events after the transaction commits, and the deduplication middleware on 7.3+ when symfony/lock is installed) is added automatically around this list.

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
        $class = $envelope->getMessage()::class;
        $this->logger->info('Handling message', ['class' => $class]);

        try {
            $envelope = $stack->next()->handle($envelope, $stack);
            $this->logger->info('Message handled successfully', ['class' => $class]);

            return $envelope;
        } catch (\Throwable $e) {
            $this->logger->error('Message handling failed', [
                'class' => $class,
                'error' => $e->getMessage(),
            ]);

            throw $e;
        }
    }
}
```

## Testing Handlers Directly

Since handlers use `__invoke`, they can be tested without the bus (see the testing skill for in-memory adapters):

```php
final class RegisterUserHandlerTest extends TestCase
{
    public function test_it_registers_a_user(): void
    {
        $users = new InMemoryUserRepository();
        $handler = new RegisterUserHandler($users, new FakePasswordHasher(), new SequentialIdGenerator());

        $id = $handler(new RegisterUser('test@example.com', 'Test User', 'password123'));

        self::assertNotNull($users->findById(new UserId($id)));
    }
}
```
