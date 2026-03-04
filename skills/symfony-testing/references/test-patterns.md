# Test Patterns

## In-Memory Adapters for Testing

Replace infrastructure adapters with in-memory versions for fast, isolated tests.

### In-Memory Repository

```php
namespace Tests\Support\Adapter;

use App\Domain\User\Entity\User;
use App\Domain\User\Port\UserRepositoryInterface;
use App\Domain\User\ValueObject\Email;
use App\Domain\User\ValueObject\UserId;

final class InMemoryUserRepository implements UserRepositoryInterface
{
    /** @var array<string, User> */
    private array $users = [];

    public function save(User $user): void
    {
        $this->users[(string) $user->id()] = $user;
    }

    public function findById(UserId $id): ?User
    {
        return $this->users[$id->value] ?? null;
    }

    public function findByEmail(Email $email): ?User
    {
        foreach ($this->users as $user) {
            if ((string) $user->email() === $email->value) {
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
        unset($this->users[(string) $user->id()]);
    }

    /** @return User[] */
    public function all(): array
    {
        return array_values($this->users);
    }
}
```

## Entity Test Patterns

### Testing Entity Creation

```php
final class UserTest extends TestCase
{
    public function test_user_is_registered(): void
    {
        $userId = new UserId('550e8400-e29b-41d4-a716-446655440000');
        $email = new Email('john@example.com');

        $user = User::register($userId, $email, 'John Doe');

        $this->assertTrue($userId->equals($user->id()));
        $this->assertSame('John Doe', $user->name());
    }

    public function test_user_registration_records_event(): void
    {
        $user = User::register(
            UserId::generate(),
            new Email('john@example.com'),
            'John Doe',
        );

        $events = $user->pullDomainEvents();
        $this->assertCount(1, $events);
        $this->assertInstanceOf(UserRegistered::class, $events[0]);
    }

    public function test_domain_events_are_cleared_after_pull(): void
    {
        $user = User::register(UserId::generate(), new Email('test@test.com'), 'Test');

        $user->pullDomainEvents();
        $events = $user->pullDomainEvents();

        $this->assertEmpty($events);
    }
}
```

### Testing Entity Business Rules

```php
final class OrderTest extends TestCase
{
    public function test_cannot_cancel_delivered_order(): void
    {
        $order = $this->createDeliveredOrder();

        $this->expectException(OrderAlreadyCancelledException::class);
        $order->cancel('Changed my mind');
    }

    public function test_adding_item_to_pending_order(): void
    {
        $order = Order::place(OrderId::generate(), 'customer-1');

        $order->addItem('product-1', 2, Money::fromFloat(9.99, 'EUR'));

        $events = $order->pullDomainEvents();
        $this->assertCount(2, $events); // OrderPlaced + OrderItemAdded
    }
}
```

## Handler Test Patterns

### Command Handler with Mock

```php
final class RegisterUserHandlerTest extends TestCase
{
    private UserRepositoryInterface&MockObject $repository;
    private RegisterUserHandler $handler;

    protected function setUp(): void
    {
        $this->repository = $this->createMock(UserRepositoryInterface::class);
        $this->handler = new RegisterUserHandler($this->repository);
    }

    public function test_registers_new_user(): void
    {
        $this->repository->method('existsByEmail')->willReturn(false);
        $this->repository->expects($this->once())->method('save');

        $result = ($this->handler)(new RegisterUser('test@example.com', 'Test', 'password'));

        $this->assertNotEmpty($result);
    }

    public function test_rejects_duplicate_email(): void
    {
        $this->repository->method('existsByEmail')->willReturn(true);

        $this->expectException(UserAlreadyExistsException::class);
        ($this->handler)(new RegisterUser('existing@example.com', 'Test', 'password'));
    }
}
```

### Command Handler with In-Memory Adapter

```php
final class RegisterUserHandlerTest extends TestCase
{
    public function test_registers_and_persists_user(): void
    {
        $repository = new InMemoryUserRepository();
        $handler = new RegisterUserHandler($repository);

        $userId = ($handler)(new RegisterUser('test@example.com', 'Test', 'password'));

        $user = $repository->findById(new UserId($userId));
        $this->assertNotNull($user);
        $this->assertSame('Test', $user->name());
    }
}
```

## Functional Test Patterns

### API Endpoint Test

```php
final class UserControllerTest extends WebTestCase
{
    public function test_create_user_returns_201(): void
    {
        $client = static::createClient();
        $client->request('POST', '/api/users', [], [], [
            'CONTENT_TYPE' => 'application/json',
            'HTTP_AUTHORIZATION' => 'Bearer ' . $this->getToken('admin'),
        ], json_encode([
            'email' => 'new@example.com',
            'name' => 'New User',
            'password' => 'SecurePass123',
        ]));

        $this->assertResponseStatusCodeSame(201);

        $data = json_decode($client->getResponse()->getContent(), true);
        $this->assertArrayHasKey('result', $data);
        $this->assertArrayHasKey('id', $data['result']);
        $this->assertNull($data['error']);
        $this->assertSame(201, $data['status']);
    }

    public function test_create_user_with_invalid_email_returns_422(): void
    {
        $client = static::createClient();
        $client->request('POST', '/api/users', [], [], [
            'CONTENT_TYPE' => 'application/json',
            'HTTP_AUTHORIZATION' => 'Bearer ' . $this->getToken('admin'),
        ], json_encode([
            'email' => 'not-an-email',
            'name' => 'Test',
            'password' => 'SecurePass123',
        ]));

        $this->assertResponseStatusCodeSame(422);

        $data = json_decode($client->getResponse()->getContent(), true);
        $this->assertNull($data['result']);
        $this->assertNotNull($data['error']);
    }

    public function test_unauthorized_access_returns_403(): void
    {
        $client = static::createClient();
        $client->request('GET', '/api/users');

        $this->assertResponseStatusCodeSame(401);
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
    private UserId $id;
    private Email $email;
    private string $name = 'Test User';

    public function __construct()
    {
        $this->id = UserId::generate();
        $this->email = new Email('test@example.com');
    }

    public static function aUser(): self
    {
        return new self();
    }

    public function withEmail(string $email): self
    {
        $this->email = new Email($email);
        return $this;
    }

    public function withName(string $name): self
    {
        $this->name = $name;
        return $this;
    }

    public function build(): User
    {
        return User::register($this->id, $this->email, $this->name);
    }
}

// Usage:
$user = UserBuilder::aUser()
    ->withEmail('custom@test.com')
    ->withName('Custom Name')
    ->build();
```
