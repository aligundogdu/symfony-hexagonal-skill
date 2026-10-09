# Value Object Patterns

## Rules
- Always `final readonly class` (PHP 8.2+; on PHP 8.1 use `final class` with `public readonly` properties)
- Self-validating in constructor
- Immutable: no setters, return new instances for transformations
- Implement `equals()` for comparison
- Use `__toString()` for string representation where it is meaningful

## UUID-based ID + ID Generator Port

The ID value object only validates. Generation goes through a port so Domain never depends on `symfony/uid`, `ramsey/uuid` or the `uuid_create()` polyfill.

```php
namespace App\Domain\{Module}\ValueObject;

use App\Domain\{Module}\Exception\Invalid{Entity}IdException;

final readonly class {Entity}Id
{
    private const PATTERN = '/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i';

    public function __construct(
        public string $value,
    ) {
        if (preg_match(self::PATTERN, $value) !== 1) {
            throw Invalid{Entity}IdException::forValue($value);
        }
    }

    public function equals(self $other): bool
    {
        return strtolower($this->value) === strtolower($other->value);
    }

    public function __toString(): string
    {
        return $this->value;
    }
}
```

```php
namespace App\Domain\Shared\Port;

interface IdGeneratorInterface
{
    /** Returns a new RFC 9562 UUID string (v7 recommended: time-ordered, index friendly). */
    public function generate(): string;
}
```

```php
namespace App\Infrastructure\Shared\Identity;

use App\Domain\Shared\Port\IdGeneratorInterface;
use Symfony\Component\Uid\Factory\UuidFactory;

final readonly class SymfonyUuidGenerator implements IdGeneratorInterface
{
    public function __construct(
        private UuidFactory $uuidFactory,
    ) {
    }

    public function generate(): string
    {
        // Symfony 7.4+: the default factory already produces UUIDv7.
        // Symfony 6.4 / 7.0-7.3: configure `framework.uid.default_uuid_version: 7`
        // or call Symfony\Component\Uid\Uuid::v7() directly.
        return $this->uuidFactory->create()->toRfc4122();
    }
}
```

Tests use a deterministic fake:

```php
namespace Tests\Support\Adapter;

use App\Domain\Shared\Port\IdGeneratorInterface;

final class SequentialIdGenerator implements IdGeneratorInterface
{
    private int $counter = 0;

    public function generate(): string
    {
        return sprintf('00000000-0000-7000-8000-%012d', ++$this->counter);
    }
}
```

## Email

```php
namespace App\Domain\User\ValueObject;

use App\Domain\User\Exception\InvalidEmailException;

final readonly class Email
{
    public string $value;

    public function __construct(string $value)
    {
        $normalized = strtolower(trim($value));
        if (filter_var($normalized, FILTER_VALIDATE_EMAIL) === false) {
            throw InvalidEmailException::forValue($value);
        }

        $this->value = $normalized;
    }

    public function domain(): string
    {
        return substr($this->value, strrpos($this->value, '@') + 1);
    }

    public function equals(self $other): bool
    {
        return $this->value === $other->value;
    }

    public function __toString(): string
    {
        return $this->value;
    }
}
```

## Money

Amounts are integers in minor units (cents). Never build money from floats.

```php
namespace App\Domain\Shared\ValueObject;

use App\Domain\Shared\Exception\InvalidMoneyException;

final readonly class Money
{
    public function __construct(
        public int $amount,       // minor units, e.g. cents
        public string $currency,  // ISO 4217
    ) {
        if ($amount < 0) {
            throw InvalidMoneyException::negativeAmount($amount);
        }
        if (preg_match('/^[A-Z]{3}$/', $currency) !== 1) {
            throw InvalidMoneyException::invalidCurrency($currency);
        }
    }

    public static function zero(string $currency): self
    {
        return new self(0, $currency);
    }

    public function add(self $other): self
    {
        $this->guardSameCurrency($other);

        return new self($this->amount + $other->amount, $this->currency);
    }

    public function subtract(self $other): self
    {
        $this->guardSameCurrency($other);

        return new self($this->amount - $other->amount, $this->currency); // throws if result < 0
    }

    public function multiply(int $factor): self
    {
        return new self($this->amount * $factor, $this->currency);
    }

    public function equals(self $other): bool
    {
        return $this->amount === $other->amount && $this->currency === $other->currency;
    }

    public function __toString(): string
    {
        return sprintf('%s %d.%02d', $this->currency, intdiv($this->amount, 100), $this->amount % 100);
    }

    private function guardSameCurrency(self $other): void
    {
        if ($this->currency !== $other->currency) {
            throw InvalidMoneyException::currencyMismatch($this->currency, $other->currency);
        }
    }
}
```

PHP 8.5 alternative for withers on readonly classes: `return clone($this, ['amount' => $this->amount + $other->amount]);` (validation in the constructor is skipped by `clone`, so only use it for changes that cannot break invariants).

## Date Range

```php
namespace App\Domain\Shared\ValueObject;

use App\Domain\Shared\Exception\InvalidDateRangeException;

final readonly class DateRange
{
    public function __construct(
        public \DateTimeImmutable $start,
        public \DateTimeImmutable $end,
    ) {
        if ($start > $end) {
            throw InvalidDateRangeException::startAfterEnd($start, $end);
        }
    }

    public function contains(\DateTimeImmutable $date): bool
    {
        return $date >= $this->start && $date <= $this->end;
    }

    public function overlaps(self $other): bool
    {
        return $this->start <= $other->end && $this->end >= $other->start;
    }

    public function durationInDays(): int
    {
        return (int) $this->start->diff($this->end)->days;
    }
}
```

## Enum-based Value Object (Status, Type)

```php
namespace App\Domain\{Module}\ValueObject;

enum {Status}: string
{
    case ACTIVE = 'active';
    case INACTIVE = 'inactive';
    case SUSPENDED = 'suspended';

    public function isActive(): bool
    {
        return $this === self::ACTIVE;
    }

    public function canTransitionTo(self $target): bool
    {
        return match ($this) {
            self::ACTIVE => in_array($target, [self::INACTIVE, self::SUSPENDED], true),
            self::INACTIVE, self::SUSPENDED => $target === self::ACTIVE,
        };
    }
}
```

Doctrine maps backed enums natively (`enum-type` in XML), no custom type needed.

## Composite Value Object

```php
namespace App\Domain\{Module}\ValueObject;

use App\Domain\{Module}\Exception\InvalidAddressException;

final readonly class Address
{
    public function __construct(
        public string $street,
        public string $city,
        public string $postalCode,
        public string $country, // ISO 3166-1 alpha-2
    ) {
        foreach (['street' => $street, 'city' => $city, 'postalCode' => $postalCode] as $field => $value) {
            if (trim($value) === '') {
                throw InvalidAddressException::missingField($field);
            }
        }
        if (preg_match('/^[A-Z]{2}$/', $country) !== 1) {
            throw InvalidAddressException::invalidCountry($country);
        }
    }

    public function equals(self $other): bool
    {
        return $this == $other; // same class, compares all properties
    }

    public function __toString(): string
    {
        return sprintf('%s, %s %s, %s', $this->street, $this->postalCode, $this->city, $this->country);
    }
}
```

Map composite value objects as Doctrine embeddables (see doctrine-persistence `mapping-patterns.md`).
