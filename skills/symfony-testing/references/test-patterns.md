# Test Patterns

## In-Memory Adapters for Testing

Replace infrastructure adapters with in-memory versions for fast, isolated tests.

### In-Memory Repository

```php
namespace Tests\Support\Adapter;

use App\Domain\Shared\Event\DomainEvent;
use App\Domain\User\Entity\User;
use App\Domain\User\Port\UserRepositoryInterface;
use App\Domain\User\ValueObject\Email;
use App\Domain\User\ValueObject\UserId;

final class InMemoryUserRepository implements UserRepositoryInterface
{
    /** @var array<string, User> */
    private array $users = [];

    /** @var list<DomainEvent> events "dispatched" by save(), for assertions */
    public array $releasedEvents = [];

    public function save(User $user): void
    {
        $this->users[$user->id()->value] = $user;
        array_push($this->releasedEvents, ...$user->pullDomainEvents());
    }

    public function findById(UserId $id): ?User
    {
        return $this->users[$id->value] ?? null;
    }

    public function findByEmail(Email $email): ?User
    {
        foreach ($this->users as $user) {
            if ($user->email()->equals($email)) {
                return $user;
            }
        }

        return null;
    }

    public function existsByEmail(Email $email): bool
    {
        return $this->findByEmail($email) !== null;
    }

    public function remove(User $user): void
    {
        unset($this->users[$user->id()->value]);
    }

    /** @return list<User> */
    public function all(): array
    {
        return array_values($this->users);
    }
}
```

### Other fakes

```php
namespace Tests\Support\Adapter;

use App\Domain\User\Port\PasswordHasherInterface;

final class FakePasswordHasher implements PasswordHasherInterface
{
    public function hash(string $plainPassword): string
    {
        return 'hashed:' . $plainPassword;
    }

    public function verify(string $hash, string $plainPassword): bool
    {
        return $hash === 'hashed:' . $plainPassword;
    }
}
```

`SequentialIdGenerator` is shown in the domain-modeling skill (`value-object-patterns.md`).

## Entity Test Patterns

### Testing Entity Creation

```php
final class UserTest extends TestCase
{
    private const USER_ID = '0199a3c2-7b1e-7c3a-9f00-000000000001';

    public function test_user_is_registered(): void
    {
        $userId = new UserId(self::USER_ID);

        $user = User::register($userId, new Email('john@example.com'), 'John Doe', 'hash', new \DateTimeImmutable());

        self::assertTrue($userId->equals($user->id()));
        self::assertSame('John Doe', $user->name());
    }

    public function test_user_registration_records_event(): void
    {
        $user = User::register(new UserId(self::USER_ID), new Email('john@example.com'), 'John Doe', 'hash', new \DateTimeImmutable());

        $events = $user->pullDomainEvents();

        self::assertCount(1, $events);
        self::assertInstanceOf(UserRegistered::class, $events[0]);
    }

    public function test_domain_events_are_cleared_after_pull(): void
    {
        $user = User::register(new UserId(self::USER_ID), new Email('test@test.com'), 'Test', 'hash', new \DateTimeImmutable());

        $user->pullDomainEvents();

        self::assertSame([], $user->pullDomainEvents());
    }
}
```

### Testing Entity Business Rules

```php
final class OrderTest extends TestCase
{
    public function test_cannot_cancel_delivered_order(): void
    {
        $order = $this->deliveredOrder();

        $this->expectException(InvalidOrderTransitionException::class);
        $order->cancel('Changed my mind', new \DateTimeImmutable());
    }

    public function test_adding_item_to_pending_order(): void
    {
        $now = new \DateTimeImmutable();
        $order = Order::place(new OrderId('0199a3c2-7b1e-7c3a-9f00-000000000002'), 'customer-1', 'EUR', $now);

        $order->addItem('product-1', 2, new Money(999, 'EUR'), $now);

        self::assertCount(2, $order->pullDomainEvents()); // OrderPlaced + OrderItemAdded
        self::assertEquals(new Money(1998, 'EUR'), $order->totalAmount());
    }
}
```

## Handler Test Patterns

### Command Handler with Stubs (PHPUnit 10-13)

Use `createStub()` when you only configure return values, `createMock()` only when you assert calls with `expects()`. PHPUnit 13 reports a notice for mocks that never get an expectation.

```php
final class RegisterUserHandlerTest extends TestCase
{
    public function test_rejects_duplicate_email(): void
    {
        $users = $this->createStub(UserRepositoryInterface::class);
        $users->method('existsByEmail')->willReturn(true);

        $handler = new RegisterUserHandler($users, new FakePasswordHasher(), new SequentialIdGenerator());

        $this->expectException(UserAlreadyExistsException::class);
        $handler(new RegisterUser('existing@example.com', 'Test', 'password'));
    }

    public function test_saves_exactly_once(): void
    {
        $users = $this->createMock(UserRepositoryInterface::class);
        $users->method('existsByEmail')->willReturn(false);
        $users->expects($this->once())->method('save');

        $handler = new RegisterUserHandler($users, new FakePasswordHasher(), new SequentialIdGenerator());
        $handler(new RegisterUser('new@example.com', 'Test', 'password'));
    }
}
```

### Command Handler with In-Memory Adapter (preferred)

```php
final class RegisterUserHandlerTest extends TestCase
{
    public function test_registers_and_persists_user(): void
    {
        $users = new InMemoryUserRepository();
        $handler = new RegisterUserHandler($users, new FakePasswordHasher(), new SequentialIdGenerator());

        $userId = $handler(new RegisterUser('test@example.com', 'Test', 'password'));

        $user = $users->findById(new UserId($userId));
        self::assertNotNull($user);
        self::assertSame('Test', $user->name());
        self::assertInstanceOf(UserRegistered::class, $users->releasedEvents[0]);
    }
}
```

## Asserting Async Messages

With `async: 'in-memory://'` under `when@test` (see messenger config), messages routed async are captured instead of sent:

```php
use Symfony\Component\Messenger\Transport\InMemory\InMemoryTransport;

final class RegisterUserFlowTest extends KernelTestCase
{
    public function test_user_registered_event_is_queued(): void
    {
        self::bootKernel();
        // dispatch the command through the real bus ...

        /** @var InMemoryTransport $transport */
        $transport = self::getContainer()->get('messenger.transport.async');

        self::assertCount(1, $transport->getSent());
        self::assertInstanceOf(UserRegistered::class, $transport->getSent()[0]->getMessage());
    }
}
```

`zenstruck/messenger-test` offers a fluent alternative (`$this->transport('async')->queue()->assertContains(UserRegistered::class)`); check its compatibility with your Symfony/PHPUnit versions before adding it.

## Functional Test Patterns

### API Endpoint Test

```php
final class UserControllerTest extends WebTestCase
{
    public function test_create_user_returns_201(): void
    {
        $client = static::createClient();
        $client->jsonRequest('POST', '/api/users', [
            'email' => 'new@example.com',
            'name' => 'New User',
            'password' => 'SecurePass123',
        ], ['HTTP_AUTHORIZATION' => 'Bearer ' . $this->tokenFor('admin')]);

        self::assertResponseStatusCodeSame(201);

        $data = json_decode((string) $client->getResponse()->getContent(), true, flags: JSON_THROW_ON_ERROR);
        self::assertArrayHasKey('id', $data['result']);
        self::assertNull($data['error']);
        self::assertSame(201, $data['status']);
    }

    public function test_create_user_with_invalid_email_returns_422(): void
    {
        $client = static::createClient();
        $client->jsonRequest('POST', '/api/users', [
            'email' => 'not-an-email',
            'name' => 'Test',
            'password' => 'SecurePass123',
        ], ['HTTP_AUTHORIZATION' => 'Bearer ' . $this->tokenFor('admin')]);

        self::assertResponseStatusCodeSame(422);

        $data = json_decode((string) $client->getResponse()->getContent(), true, flags: JSON_THROW_ON_ERROR);
        self::assertNull($data['result']);
        self::assertSame('VALIDATION_ERROR', $data['error']['code']);
        self::assertArrayHasKey('email', $data['error']['details']);
    }

    public function test_unauthenticated_access_returns_401(): void
    {
        $client = static::createClient();
        $client->request('GET', '/api/users');

        self::assertResponseStatusCodeSame(401);
    }

    public function test_missing_role_returns_403(): void
    {
        $client = static::createClient();
        $client->request('GET', '/api/users', server: ['HTTP_AUTHORIZATION' => 'Bearer ' . $this->tokenFor('basic-user')]);

        self::assertResponseStatusCodeSame(403);
    }
}
```

## Test Builder Pattern

```php
namespace Tests\Support\Builder;

use App\Domain\User\Entity\User;
use App\Domain\User\ValueObject\Email;
use App\Domain\User\ValueObject\UserId;

final class UserBuilder
{
    private string $id = '0199a3c2-7b1e-7c3a-9f00-000000000001';
    private string $email = 'test@example.com';
    private string $name = 'Test User';

    public static function aUser(): self
    {
        return new self();
    }

    public function withId(string $id): self
    {
        $clone = clone $this;
        $clone->id = $id;

        return $clone;
    }

    public function withEmail(string $email): self
    {
        $clone = clone $this;
        $clone->email = $email;

        return $clone;
    }

    public function withName(string $name): self
    {
        $clone = clone $this;
        $clone->name = $name;

        return $clone;
    }

    public function build(): User
    {
        return User::register(new UserId($this->id), new Email($this->email), $this->name, 'hash', new \DateTimeImmutable());
    }
}

// Usage:
$user = UserBuilder::aUser()
    ->withEmail('custom@test.com')
    ->withName('Custom Name')
    ->build();
```
