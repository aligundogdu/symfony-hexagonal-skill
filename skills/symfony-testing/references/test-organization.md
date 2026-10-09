# Test Organization

## phpunit.xml.dist Configuration (PHPUnit 10, 11, 12, 13)

PHPUnit 10+ uses `<source>` for coverage/deprecation scope (the old `<coverage><include>` block is invalid). `failOnNotice` turns PHPUnit 13's "mock without expectations" notices into failures. Track Symfony 8 deprecations with `phpstan-deprecation-rules` (static) and `symfony/phpunit-bridge` or `failOnDeprecation="true"` (runtime) once vendor code is clean.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<phpunit xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:noNamespaceSchemaLocation="vendor/phpunit/phpunit/phpunit.xsd"
         backupGlobals="false"
         colors="true"
         bootstrap="tests/bootstrap.php"
         cacheDirectory=".phpunit.cache"
         failOnNotice="true"
         failOnWarning="true">

    <testsuites>
        <testsuite name="Unit">
            <directory>tests/Unit</directory>
        </testsuite>
        <testsuite name="Integration">
            <directory>tests/Integration</directory>
        </testsuite>
        <testsuite name="Functional">
            <directory>tests/Functional</directory>
        </testsuite>
    </testsuites>

    <source>
        <include>
            <directory>src</directory>
        </include>
        <exclude>
            <file>src/Kernel.php</file>
        </exclude>
    </source>

    <php>
        <ini name="display_errors" value="1"/>
        <ini name="error_reporting" value="-1"/>
        <server name="APP_ENV" value="test" force="true"/>
        <server name="SHELL_VERBOSITY" value="-1"/>
        <server name="KERNEL_CLASS" value="App\Kernel"/>
    </php>
</phpunit>
```

## Running Tests

```bash
# All tests
vendor/bin/phpunit

# By suite
vendor/bin/phpunit --testsuite=Unit
vendor/bin/phpunit --testsuite=Integration
vendor/bin/phpunit --testsuite=Functional

# Specific test file
vendor/bin/phpunit tests/Unit/Domain/User/ValueObject/EmailTest.php

# Specific test method
vendor/bin/phpunit --filter=test_valid_email_is_created

# With coverage
vendor/bin/phpunit --coverage-html coverage/
```

## Test Suites by Layer

### Unit Suite (Fast, no framework)
- Tests `Domain/` classes: entities, value objects, domain events
- Pure PHP - no container, no database
- Use `PHPUnit\Framework\TestCase`
- Target: 100% coverage of Domain layer

### Integration Suite (Medium, mocked ports)
- Tests `Application/` handlers: commands, queries, event handlers
- Mock port interfaces
- Use `PHPUnit\Framework\TestCase` with in-memory adapters (or `createStub()`)
- Tests business logic orchestration

### Functional Suite (Slow, full stack)
- Tests `Presentation/` controllers: HTTP requests/responses
- Full Symfony kernel
- Uses test database
- Use `Symfony\Bundle\FrameworkBundle\Test\WebTestCase`
- Tests API contracts, authentication, authorization

## PHPStan Configuration (PHPStan 2.x)

```neon
# phpstan.neon
parameters:
    level: 8          # minimum; raise to 9/10 for new projects
    paths:
        - src/
        - tests/
    excludePaths:
        - src/Kernel.php
    tmpDir: var/phpstan
```

With `phpstan/extension-installer`, the symfony/doctrine/phpunit/strict/deprecation rule sets load automatically. Do not copy `checkGenericClassInNonGenericObjectType` from old configs: PHPStan 2 rejects it.

```bash
# Run PHPStan
vendor/bin/phpstan analyse

# Specific paths
vendor/bin/phpstan analyse src/Domain/

# Generate baseline for existing (legacy) code, then ratchet it down module by module
vendor/bin/phpstan analyse --generate-baseline
```

## CI/CD Test Pipeline

```yaml
# .github/workflows/test.yml (or similar)
steps:
    - name: PHPStan
      run: vendor/bin/phpstan analyse --no-progress

    - name: Deptrac (layer rules)
      run: vendor/bin/deptrac analyse --no-progress

    - name: Unit Tests
      run: vendor/bin/phpunit --testsuite=Unit

    - name: Integration Tests
      run: vendor/bin/phpunit --testsuite=Integration

    - name: Functional Tests
      run: |
          php bin/console doctrine:database:create --env=test
          php bin/console doctrine:migrations:migrate --no-interaction --env=test
          vendor/bin/phpunit --testsuite=Functional
```

## Fixtures with Foundry 2

Domain entities have private constructors, so tell Foundry to use the named constructor:

```php
namespace Tests\Support\Factory;

use App\Domain\User\Entity\User;
use App\Domain\User\ValueObject\Email;
use App\Domain\User\ValueObject\UserId;
use Zenstruck\Foundry\Object\Instantiator;
use Zenstruck\Foundry\Persistence\PersistentObjectFactory;

/** @extends PersistentObjectFactory<User> */
final class UserFactory extends PersistentObjectFactory
{
    public static function class(): string
    {
        return User::class;
    }

    protected function defaults(): array
    {
        return [
            'id' => new UserId(self::faker()->uuid()),
            'email' => new Email(self::faker()->unique()->safeEmail()),
            'name' => self::faker()->name(),
            'passwordHash' => 'not-a-real-hash',
            'now' => new \DateTimeImmutable(),
        ];
    }

    protected function initialize(): static
    {
        return $this->instantiateWith(Instantiator::namedConstructor('register'));
    }
}

// Usage in functional tests:
$user = UserFactory::createOne(['name' => 'John']);
```

Foundry 1's `ModelFactory`, `getDefaults()` and `getClass()` no longer exist in Foundry 2. Unit tests in `tests/Unit` should build entities with plain named constructors or test builders, not Foundry.
