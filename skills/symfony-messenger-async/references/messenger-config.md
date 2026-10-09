# Messenger Configuration

## Full messenger.yaml

```yaml
# config/packages/messenger.yaml
framework:
    messenger:
        # Default bus for dispatching
        default_bus: command.bus

        # Bus definitions
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

        # Transport definitions
        transports:
            async:
                dsn: '%env(MESSENGER_TRANSPORT_DSN)%'
                options:
                    queue_name: default
                retry_strategy:
                    max_retries: 3
                    delay: 1000        # 1 second initial delay
                    multiplier: 2      # exponential backoff
                    max_delay: 60000   # max 60 seconds
                    # jitter: 0.1      # Symfony 7.1+: randomize delays to avoid thundering herds

            async_priority_high:
                dsn: '%env(MESSENGER_TRANSPORT_DSN)%'
                options:
                    queue_name: high_priority
                retry_strategy:
                    max_retries: 5
                    delay: 500
                    multiplier: 2
                    max_delay: 30000

            async_priority_low:
                dsn: '%env(MESSENGER_TRANSPORT_DSN)%'
                options:
                    queue_name: low_priority
                retry_strategy:
                    max_retries: 2
                    delay: 5000
                    multiplier: 3
                    max_delay: 120000

            failed:
                dsn: 'doctrine://default?queue_name=failed'

        # Failure transport
        failure_transport: failed

        # Message routing
        routing:
            # High priority
            'App\Application\Payment\Command\ProcessPayment': async_priority_high
            'App\Application\Order\Command\ConfirmOrder': async_priority_high

            # Normal priority
            'App\Application\Report\Command\GenerateReport': async
            'App\Application\Email\Command\SendEmail': async

            # Low priority
            'App\Application\Analytics\Command\TrackEvent': async_priority_low
            'App\Application\Cleanup\Command\PurgeExpiredSessions': async_priority_low

            # Domain events (always YAML: no Symfony attributes in Domain)
            'App\Domain\User\Event\UserRegistered': async

when@test:
    framework:
        messenger:
            transports:
                async: 'in-memory://'
                async_priority_high: 'in-memory://'
                async_priority_low: 'in-memory://'
```

Symfony 7.2+ alternative for Application commands: `#[AsMessage('async_priority_high')]` on the class. YAML wins when both exist. Symfony 8.1 adds `PriorityStamp` (AMQP/Beanstalkd) as an alternative to separate priority transports.

## Transport DSN Options

```bash
# RabbitMQ
MESSENGER_TRANSPORT_DSN=amqp://guest:guest@localhost:5672/%2f/messages

# Doctrine (database)
MESSENGER_TRANSPORT_DSN=doctrine://default

# Redis
MESSENGER_TRANSPORT_DSN=redis://localhost:6379/messages

# Amazon SQS
MESSENGER_TRANSPORT_DSN=sqs://ACCESS_KEY:SECRET@default/messages
```

## Running Workers

```bash
# Single worker
php bin/console messenger:consume async --limit=100 --time-limit=3600

# Multiple transports with priority
php bin/console messenger:consume async_priority_high async async_priority_low --limit=100

# All receivers except "failed" (Symfony 7.4+)
php bin/console messenger:consume --all --exclude-receivers=failed --time-limit=3600

# Queue sizes
php bin/console messenger:stats

# Graceful restart after deploy (workers finish the current message)
php bin/console messenger:stop-workers
```

```ini
# Supervisor configuration
# /etc/supervisor/conf.d/messenger-worker.conf
[program:messenger-worker]
command=php /var/www/app/bin/console messenger:consume async --limit=100 --time-limit=3600 --memory-limit=256M
numprocs=2
autostart=true
autorestart=true
process_name=%(program_name)s_%(process_num)02d
stopwaitsecs=20
```

Always run `messenger:stop-workers` on deploy, otherwise workers keep executing the old code.

## Failed Message Management

```bash
# View failed messages
php bin/console messenger:failed:show

# Retry a specific message
php bin/console messenger:failed:retry 123

# Retry all failed messages
php bin/console messenger:failed:retry

# Remove a failed message
php bin/console messenger:failed:remove 123
```

Monitor the `failed` transport (e.g. alert when `messenger:stats` shows it non-empty). Make sure retries are only spent on transient errors: throw `Symfony\Component\Messenger\Exception\UnrecoverableMessageHandlingException` for errors that can never succeed (invalid data), so the message goes straight to `failed`.

## Custom Middleware

### Logging Middleware

```php
namespace App\Infrastructure\Shared\Middleware;

use Psr\Log\LoggerInterface;
use Symfony\Component\Messenger\Envelope;
use Symfony\Component\Messenger\Middleware\MiddlewareInterface;
use Symfony\Component\Messenger\Middleware\StackInterface;

final readonly class AuditLogMiddleware implements MiddlewareInterface
{
    public function __construct(
        private LoggerInterface $logger,
    ) {
    }

    public function handle(Envelope $envelope, StackInterface $stack): Envelope
    {
        $message = $envelope->getMessage();
        $this->logger->info('Processing message', [
            'type' => get_class($message),
            'timestamp' => (new \DateTimeImmutable())->format('c'),
        ]);

        return $stack->next()->handle($envelope, $stack);
    }
}
```

### Register middleware:
```yaml
framework:
    messenger:
        buses:
            command.bus:
                middleware:
                    - validation
                    - App\Infrastructure\Shared\Middleware\AuditLogMiddleware
                    - doctrine_transaction
```
