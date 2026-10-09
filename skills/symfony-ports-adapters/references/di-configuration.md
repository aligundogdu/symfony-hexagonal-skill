# Dependency Injection Configuration

All YAML below works on Symfony 6.4, 7.x and 8.x. Symfony 8 removed XML service configuration: use YAML (recommended) or the 7.4+ PHP array format.

## Basic Port-to-Adapter Binding

```yaml
# config/services.yaml
services:
    _defaults:
        autowire: true
        autoconfigure: true
        bind:
            $eventBus: '@event.bus'

    # Auto-register all services
    App\:
        resource: '../src/'
        exclude:
            - '../src/Kernel.php'
            - '../src/Domain/*/Entity/'
            - '../src/Domain/*/ValueObject/'
            - '../src/Domain/*/Event/'
            - '../src/Domain/*/Exception/'
            - '../src/Domain/*/ReadModel/'
            - '../src/Application/*/DTO/'

    # Port → Adapter bindings
    App\Domain\User\Port\UserRepositoryInterface:
        alias: App\Infrastructure\User\Persistence\DoctrineUserRepository

    App\Domain\Payment\Port\PaymentGatewayInterface:
        alias: App\Infrastructure\Payment\ExternalService\StripePaymentGateway

    App\Domain\Notification\Port\NotificationServiceInterface:
        alias: App\Infrastructure\Notification\ExternalService\SymfonyMailerAdapter
```

## Environment-Specific Adapters

Use `when@{env}` blocks in the same file (Symfony 5.3+):

```yaml
# config/services.yaml
services:
    App\Domain\Notification\Port\NotificationServiceInterface:
        alias: App\Infrastructure\Notification\ExternalService\SymfonyMailerAdapter

when@dev:
    services:
        App\Domain\Notification\Port\NotificationServiceInterface:
            alias: App\Infrastructure\Notification\ExternalService\NullNotificationService

when@test:
    services:
        Tests\Support\Adapter\InMemoryUserRepository: ~
        App\Domain\User\Port\UserRepositoryInterface:
            alias: Tests\Support\Adapter\InMemoryUserRepository
            public: true   # lets functional tests fetch and inspect it
```

Symfony 7.3+ attribute alternative on the test adapter: `#[AsAlias(UserRepositoryInterface::class, when: 'test')]`.

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

Attribute alternative (6.1+): `#[Autowire(env: 'MAILER_FROM')] private string $fromEmail` in the adapter constructor.

## Tagged Services (Multiple Adapters)

When you need multiple implementations of the same port:

```php
use Symfony\Component\DependencyInjection\Attribute\AutoconfigureTag;
use Symfony\Component\DependencyInjection\Attribute\AutowireIterator;

#[AutoconfigureTag('app.notification_channel')]
interface NotificationChannelInterface { /* Infrastructure-internal, so attributes are fine here */ }

final readonly class CompositeNotificationService implements NotificationServiceInterface
{
    /** @param iterable<NotificationChannelInterface> $channels */
    public function __construct(
        #[AutowireIterator('app.notification_channel')] // Symfony 6.4+ (TaggedIterator before)
        private iterable $channels,
    ) {
    }
}
```

YAML equivalent for any version: `$channels: !tagged_iterator 'app.notification_channel'`.

## Decorator Pattern (caching a read port)

Cache **read models**, not Doctrine-managed entities (cached entities come back detached and break the unit of work).

```php
namespace App\Infrastructure\User\Persistence;

use App\Domain\Shared\ReadModel\Page;
use App\Domain\User\Port\UserReadRepositoryInterface;
use Symfony\Component\DependencyInjection\Attribute\AsDecorator;
use Symfony\Component\DependencyInjection\Attribute\AutowireDecorated;
use Symfony\Contracts\Cache\ItemInterface;
use Symfony\Contracts\Cache\TagAwareCacheInterface;

#[AsDecorator(decorates: DbalUserReadRepository::class)]
final readonly class CachedUserReadRepository implements UserReadRepositoryInterface
{
    public function __construct(
        #[AutowireDecorated]
        private UserReadRepositoryInterface $inner,
        private TagAwareCacheInterface $cache,
    ) {
    }

    public function search(int $page, int $limit, ?string $status, ?string $search): Page
    {
        $key = 'users_' . md5(serialize([$page, $limit, $status, $search]));

        return $this->cache->get($key, function (ItemInterface $item) use ($page, $limit, $status, $search): Page {
            $item->expiresAfter(300);
            $item->tag(['users']);

            return $this->inner->search($page, $limit, $status, $search);
        });
    }
}
```

Invalidate with an event handler (`WhenUserRegisteredInvalidateUserCache` → `$cache->invalidateTags(['users'])`). `TagAwareCacheInterface` needs a tag-aware pool (`cache.app.taggable`).

## Autowiring Interfaces

If exactly one service implements an interface, Symfony autowires it automatically. Still declare the alias explicitly: it documents the binding and fails loudly when a second implementation appears.

## Module-Scoped Service Files

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
