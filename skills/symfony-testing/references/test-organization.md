# Test Organization

## phpunit.xml.dist Configuration

```xml
<?xml version="1.0" encoding="UTF-8"?>
<phpunit xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:noNamespaceSchemaLocation="vendor/phpunit/phpunit/phpunit.xsd"
         backupGlobals="false"
         colors="true"
         bootstrap="tests/bootstrap.php"
         cacheDirectory=".phpunit.cache">

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

    <coverage>
        <include>
            <directory suffix=".php">src</directory>
        </include>
        <exclude>
            <directory>src/Kernel.php</directory>
        </exclude>
    </coverage>

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
php bin/phpunit

# By suite
php bin/phpunit --testsuite=Unit
php bin/phpunit --testsuite=Integration
php bin/phpunit --testsuite=Functional

# Specific test file
php bin/phpunit tests/Unit/Domain/User/ValueObject/EmailTest.php

# Specific test method
php bin/phpunit --filter=test_valid_email_is_created

# With coverage
php bin/phpunit --coverage-html coverage/
```

## Test Suites by Layer

### Unit Suite (Fast, no framework)
- Tests `Domain/` classes: entities, value objects, domain events
- Pure PHP — no container, no database
- Use `PHPUnit\Framework\TestCase`
- Target: 100% coverage of Domain layer

### Integration Suite (Medium, mocked ports)
- Tests `Application/` handlers: commands, queries, event handlers
- Mock port interfaces
- Use `PHPUnit\Framework\TestCase` with mocks
- Tests business logic orchestration

### Functional Suite (Slow, full stack)
- Tests `Presentation/` controllers: HTTP requests/responses
- Full Symfony kernel
- Uses test database
- Use `Symfony\Bundle\FrameworkBundle\Test\WebTestCase`
- Tests API contracts, authentication, authorization

## PHPStan Configuration

```neon
# phpstan.neon
parameters:
    level: 8
    paths:
        - src/
        - tests/
    excludePaths:
        - src/Kernel.php
    tmpDir: var/phpstan
    checkGenericClassInNonGenericObjectType: false

includes:
    - vendor/phpstan/phpstan-symfony/extension.neon
    - vendor/phpstan/phpstan-doctrine/extension.neon
    - vendor/phpstan/phpstan-phpunit/extension.neon
    - vendor/phpstan/phpstan-strict-rules/rules.neon
```

```bash
# Run PHPStan
vendor/bin/phpstan analyse

# Specific paths
vendor/bin/phpstan analyse src/Domain/

# Generate baseline for existing code
vendor/bin/phpstan analyse --generate-baseline
```

## CI/CD Test Pipeline

```yaml
# .github/workflows/test.yml (or similar)
steps:
    - name: PHPStan
      run: vendor/bin/phpstan analyse --no-progress

    - name: Unit Tests
      run: php bin/phpunit --testsuite=Unit

    - name: Integration Tests
      run: php bin/phpunit --testsuite=Integration

    - name: Functional Tests
      run: |
          php bin/console doctrine:database:create --env=test
          php bin/console doctrine:migrations:migrate --no-interaction --env=test
          php bin/phpunit --testsuite=Functional
```

## Fixtures with Foundry

```php
namespace Tests\Support\Factory;

use App\Domain\User\Entity\User;
use App\Domain\User\ValueObject\Email;
use App\Domain\User\ValueObject\UserId;
use Zenstruck\Foundry\ModelFactory;

final class UserFactory extends ModelFactory
{
    protected function getDefaults(): array
    {
        return [
            'id' => UserId::generate(),
            'email' => new Email(self::faker()->email()),
            'name' => self::faker()->name(),
        ];
    }

    protected static function getClass(): string
    {
        return User::class;
    }
}

// Usage in tests:
$user = UserFactory::createOne(['name' => 'John']);
```
