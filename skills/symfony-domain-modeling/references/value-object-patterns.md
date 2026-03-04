# Value Object Patterns

## Rules
- Always `final readonly class`
- Self-validating in constructor
- Immutable — no setters, return new instances for transformations
- Implement `equals()` for comparison
- Use `__toString()` for string representation

## UUID-based ID

```php
namespace App\Domain\{Module}\ValueObject;

final readonly class {Entity}Id
{
    public function __construct(
        public string $value,
    ) {
        if (!preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[47][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i', $value)) {
            throw new \InvalidArgumentException(sprintf('Invalid UUID: %s', $value));
        }
    }

    public static function generate(): self
    {
        return new self(uuid_create(UUID_TYPE_RANDOM));
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

## Email

```php
namespace App\Domain\User\ValueObject;

use App\Domain\User\Exception\InvalidEmailException;

final readonly class Email
{
    public function __construct(
        public string $value,
    ) {
        if (!filter_var($value, FILTER_VALIDATE_EMAIL)) {
            throw InvalidEmailException::forValue($value);
        }
    }

    public function domain(): string
    {
        return explode('@', $this->value)[1];
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

## Money

```php
namespace App\Domain\Shared\ValueObject;

final readonly class Money
{
    public function __construct(
        public int $amount,       // stored in cents
        public string $currency,
    ) {
        if ($amount < 0) {
            throw new \InvalidArgumentException('Amount cannot be negative');
        }
        if (strlen($currency) !== 3) {
            throw new \InvalidArgumentException('Currency must be ISO 4217');
        }
    }

    public static function zero(string $currency): self
    {
        return new self(0, $currency);
    }

    public static function fromFloat(float $amount, string $currency): self
    {
        return new self((int) round($amount * 100), $currency);
    }

    public function add(self $other): self
    {
        $this->guardSameCurrency($other);
        return new self($this->amount + $other->amount, $this->currency);
    }

    public function subtract(self $other): self
    {
        $this->guardSameCurrency($other);
        return new self($this->amount - $other->amount, $this->currency);
    }

    public function multiply(int $factor): self
    {
        return new self($this->amount * $factor, $this->currency);
    }

    public function toFloat(): float
    {
        return $this->amount / 100;
    }

    public function equals(self $other): bool
    {
        return $this->amount === $other->amount && $this->currency === $other->currency;
    }

    public function __toString(): string
    {
        return sprintf('%s %.2f', $this->currency, $this->toFloat());
    }

    private function guardSameCurrency(self $other): void
    {
        if ($this->currency !== $other->currency) {
            throw new \InvalidArgumentException(
                sprintf('Cannot operate on different currencies: %s vs %s', $this->currency, $other->currency)
            );
        }
    }
}
```

## Date Range

```php
namespace App\Domain\Shared\ValueObject;

final readonly class DateRange
{
    public function __construct(
        public \DateTimeImmutable $start,
        public \DateTimeImmutable $end,
    ) {
        if ($start > $end) {
            throw new \InvalidArgumentException('Start date must be before end date');
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
            self::ACTIVE => in_array($target, [self::INACTIVE, self::SUSPENDED]),
            self::INACTIVE => $target === self::ACTIVE,
            self::SUSPENDED => $target === self::ACTIVE,
        };
    }
}
```

## Composite Value Object

```php
namespace App\Domain\{Module}\ValueObject;

final readonly class Address
{
    public function __construct(
        public string $street,
        public string $city,
        public string $postalCode,
        public string $country,
    ) {
        if (empty($street) || empty($city) || empty($postalCode) || empty($country)) {
            throw new \InvalidArgumentException('All address fields are required');
        }
        if (strlen($country) !== 2) {
            throw new \InvalidArgumentException('Country must be ISO 3166-1 alpha-2');
        }
    }

    public function equals(self $other): bool
    {
        return $this->street === $other->street
            && $this->city === $other->city
            && $this->postalCode === $other->postalCode
            && $this->country === $other->country;
    }

    public function __toString(): string
    {
        return sprintf('%s, %s %s, %s', $this->street, $this->postalCode, $this->city, $this->country);
    }
}
```
