# Dependency Injection Configuration

## Basic Port-to-Adapter Binding

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

    # Auto-register all services
    App\:
        resource: '../src/'
        exclude:
            - '../src/Domain/*/Entity/'
            - '../src/Domain/*/ValueObject/'
            - '../src/Domain/*/Event/'
            - '../src/Domain/*/Exception/'
            - '../src/Kernel.php'

    # Port → Adapter bindings
    App\Domain\User\Port\UserRepositoryInterface:
        alias: App\Infrastructure\User\Persistence\DoctrineUserRepository

    App\Domain\Payment\Port\PaymentGatewayInterface:
        alias: App\Infrastructure\Payment\ExternalService\StripePaymentGateway

    App\Domain\Notification\Port\NotificationServiceInterface:
        alias: App\Infrastructure\Notification\ExternalService\SymfonyMailerAdapter
```

## Environment-Specific Adapters

Use different adapters per environment:

```yaml
# config/services.yaml (production default)
services:
    App\Domain\Notification\Port\NotificationServiceInterface:
        alias: App\Infrastructure\Notification\ExternalService\SymfonyMailerAdapter

# config/services_dev.yaml
services:
    App\Domain\Notification\Port\NotificationServiceInterface:
        alias: App\Infrastructure\Notification\ExternalService\NullNotificationService

# config/services_test.yaml
services:
    App\Domain\User\Port\UserRepositoryInterface:
        alias: Tests\Support\Adapter\InMemoryUserRepository
```

## Adapter with Configuration

```yaml
services:
    App\Infrastructure\Payment\ExternalService\StripePaymentGateway:
        arguments:
            $stripe: '@stripe.client'

    stripe.client:
        class: Stripe\StripeClient
        arguments:
            - '%env(STRIPE_SECRET_KEY)%'

    App\Infrastructure\Notification\ExternalService\SymfonyMailerAdapter:
        arguments:
            $fromEmail: '%env(MAILER_FROM)%'

    App\Infrastructure\Document\ExternalService\S3FileStorage:
        arguments:
            $bucket: '%env(AWS_S3_BUCKET)%'
```

## Tagged Services (Multiple Adapters)

When you need multiple implementations of the same port:

```yaml
services:
    App\Infrastructure\Notification\ExternalService\EmailNotificationAdapter:
        tags: ['app.notification_channel']

    App\Infrastructure\Notification\ExternalService\SmsNotificationAdapter:
        tags: ['app.notification_channel']

    App\Infrastructure\Notification\ExternalService\CompositeNotificationService:
        arguments:
            $channels: !tagged_iterator 'app.notification_channel'
```

## Decorator Pattern

```yaml
services:
    App\Infrastructure\User\Persistence\DoctrineUserRepository: ~

    App\Infrastructure\User\Persistence\CachedUserRepository:
        decorates: App\Infrastructure\User\Persistence\DoctrineUserRepository
        arguments:
            $inner: '@.inner'
            $cache: '@cache.app'
```

```php
final readonly class CachedUserRepository implements UserRepositoryInterface
{
    public function __construct(
        private UserRepositoryInterface $inner,
        private CacheItemPoolInterface $cache,
    ) {
    }

    public function findById(UserId $id): ?User
    {
        $cacheKey = 'user_' . $id->value;
        $item = $this->cache->getItem($cacheKey);

        if ($item->isHit()) {
            return $item->get();
        }

        $user = $this->inner->findById($id);
        if ($user !== null) {
            $item->set($user)->expiresAfter(3600);
            $this->cache->save($item);
        }

        return $user;
    }

    // delegate other methods to $this->inner
}
```

## Autowiring Interfaces

For interfaces that have only one implementation, Symfony can autowire automatically:

```yaml
services:
    # If there's only one class implementing UserRepositoryInterface,
    # Symfony will autowire it automatically.
    # Explicit alias is still recommended for clarity:
    App\Domain\User\Port\UserRepositoryInterface: '@App\Infrastructure\User\Persistence\DoctrineUserRepository'
```

## Module-Scoped services.yaml

For large projects, split configuration per module:

```yaml
# config/services.yaml
imports:
    - { resource: 'services/user.yaml' }
    - { resource: 'services/order.yaml' }
    - { resource: 'services/payment.yaml' }
```

```yaml
# config/services/user.yaml
services:
    App\Domain\User\Port\UserRepositoryInterface:
        alias: App\Infrastructure\User\Persistence\DoctrineUserRepository

    App\Domain\User\Port\UserReadRepositoryInterface:
        alias: App\Infrastructure\User\Persistence\DbalUserReadRepository
```
