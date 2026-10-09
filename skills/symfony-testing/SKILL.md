---
name: symfony-testing
description: "Testing Symfony hexagonal architecture with PHPUnit 10-13 and PHPStan 2: test organization mirroring src/, pure domain unit tests, handler tests with in-memory adapters and stubs, functional API tests, Messenger in-memory transport, Foundry 2 factories, TDD workflow. Use when: test, PHPUnit, TDD, unit test, integration test, functional test, mock, stub, testing, test driven, code quality, PHPStan, deptrac, CI"
---

# Symfony Testing

You are an expert in testing within Symfony hexagonal architecture.

## When to Activate

- User needs to write tests
- User asks about test organization or TDD
- User needs mocking strategies for ports
- User asks about PHPStan or code quality
- User mentions test-driven development

## Version Notes

| Topic | Rule | Versions |
|---|---|---|
| Test methods | `test_` prefix or `#[Test]` attribute; never `@test` / `@dataProvider` doc-comments | annotations removed in PHPUnit 12 |
| Data providers | `#[DataProvider('name')]` + `public static function name(): iterable` | PHPUnit 10+ |
| Stubs vs mocks | `createStub()` for return values, `createMock()` only with `expects()` | PHPUnit 13 emits notices for mocks without expectations |
| Assertions | `self::assert*()` (static) | all |
| PHPUnit per PHP | 11 → PHP 8.2, 12 → PHP 8.3, 13 → PHP 8.4 | pick from the detected PHP version |
| PHPStan | 2.x, level 8 minimum (9-10 recommended for new code) | `checkGenericClassInNonGenericObjectType` removed in 2.0 |
| Foundry | 2.x: `PersistentObjectFactory` / `ObjectFactory`, `defaults()`, `class()` | `ModelFactory` was Foundry 1 |

## Test Directory Structure (Mirrors src/)

```
tests/
├── Unit/
│   └── Domain/
│       └── {Module}/
│           ├── Entity/
│           │   └── {Entity}Test.php
│           └── ValueObject/
│               └── {ValueObject}Test.php
├── Integration/
│   └── Application/
│       └── {Module}/
│           ├── Command/
│           │   └── {Handler}Test.php
│           └── Query/
│               └── {Handler}Test.php
├── Functional/
│   └── Presentation/
│       └── {Module}/
│           └── API/
│               └── {Controller}Test.php
└── Support/
    ├── Adapter/
    │   ├── InMemory{Entity}Repository.php
    │   ├── SequentialIdGenerator.php
    │   └── FakePasswordHasher.php
    └── Factory/
        └── {Entity}Factory.php
```

## Test Types by Layer

### Unit Tests (Domain): Pure PHP, no framework
```php
namespace Tests\Unit\Domain\User\ValueObject;

use App\Domain\User\Exception\InvalidEmailException;
use App\Domain\User\ValueObject\Email;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

final class EmailTest extends TestCase
{
    public function test_valid_email_is_created(): void
    {
        $email = new Email('user@example.com');

        self::assertSame('user@example.com', $email->value);
    }

    #[DataProvider('invalidEmails')]
    public function test_invalid_email_throws_exception(string $invalid): void
    {
        $this->expectException(InvalidEmailException::class);

        new Email($invalid);
    }

    /** @return iterable<string, array{string}> */
    public static function invalidEmails(): iterable
    {
        yield 'no at sign' => ['invalid'];
        yield 'empty' => [''];
        yield 'no domain' => ['user@'];
    }

    public function test_emails_are_equal(): void
    {
        self::assertTrue((new Email('user@example.com'))->equals(new Email('user@example.com')));
    }
}
```

### Integration Tests (Application): In-memory adapters for ports
```php
namespace Tests\Integration\Application\User\Command;

use App\Application\User\Command\RegisterUser;
use App\Application\User\Command\RegisterUserHandler;
use App\Domain\User\ValueObject\UserId;
use PHPUnit\Framework\TestCase;
use Tests\Support\Adapter\FakePasswordHasher;
use Tests\Support\Adapter\InMemoryUserRepository;
use Tests\Support\Adapter\SequentialIdGenerator;

final class RegisterUserHandlerTest extends TestCase
{
    public function test_it_registers_a_user(): void
    {
        $users = new InMemoryUserRepository();
        $handler = new RegisterUserHandler($users, new FakePasswordHasher(), new SequentialIdGenerator());

        $id = $handler(new RegisterUser('test@example.com', 'Test', 'password123'));

        self::assertNotNull($users->findById(new UserId($id)));
    }
}
```

Prefer in-memory fakes over mocks for ports: tests then assert on state, not on call sequences, and survive refactoring.

### Functional Tests (Presentation): Full HTTP stack
```php
namespace Tests\Functional\Presentation\User\API;

use Symfony\Bundle\FrameworkBundle\Test\WebTestCase;

final class UserControllerTest extends WebTestCase
{
    public function test_create_user(): void
    {
        $client = static::createClient();
        $client->loginUser(/* a SecurityUser with ROLE_USER_CREATE */);

        $client->jsonRequest('POST', '/api/users', [
            'email' => 'test@example.com',
            'name' => 'Test User',
            'password' => 'Password123',
        ]);

        self::assertResponseStatusCodeSame(201);
        $response = json_decode((string) $client->getResponse()->getContent(), true, flags: JSON_THROW_ON_ERROR);
        self::assertNotNull($response['result']['id']);
        self::assertNull($response['error']);
    }
}
```

`$client->jsonRequest()` and `$client->loginUser()` work on every supported version. `loginUser()` authenticates through the test session, so it fits session-based firewalls; for a stateless token firewall, send a real token header (e.g. `HTTP_AUTHORIZATION`) instead.

## TDD Workflow

1. Write test first (RED)
2. Write minimal code to pass (GREEN)
3. Refactor (REFACTOR)
4. Run PHPStan and deptrac
5. Repeat

## References

See `references/` for detailed guides:
- `test-organization.md` - phpunit.xml.dist (PHPUnit 10-13), suites, PHPStan, CI, Foundry 2
- `test-patterns.md` - In-memory adapters, builders, Messenger transport assertions, functional patterns
