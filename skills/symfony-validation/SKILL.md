---
name: symfony-validation
description: "Symfony 3-layer validation in hexagonal architecture: Presentation request DTOs with #[MapRequestPayload], Application command validation via Messenger validation middleware, Domain invariants in value objects; custom constraints with named arguments, #[ExtendsValidationFor] (7.4+), validation groups. Use when: validation, validator, constraint, DTO validation, input validation, invariant, assert, validation group, custom constraint"
---

# Symfony Validation

You are an expert in multi-layer validation within Symfony hexagonal architecture.

## When to Activate

- User needs input validation
- User asks about validation strategies
- User needs custom constraints
- User mentions DTO validation or domain invariants

## Version Notes

| Feature | Requires | Fallback |
|---|---|---|
| `#[MapRequestPayload]` / `#[MapQueryString]` auto-validation | Symfony 6.3 | manual `ValidatorInterface::validate()` |
| Named-argument constraints `Length(min: 2)` | all versions; **arrays removed in 8.0** | - |
| Custom constraint with named-argument constructor | required for 8.0 (arrays deprecated 7.3) | same code works on 6.4 |
| `#[ExtendsValidationFor(Target::class)]` | Symfony 7.4 | validate a Request DTO / Command instead |
| `When(..., otherwise: [...])` | Symfony 7.3 | two constraints with groups |

## 3-Layer Validation Strategy

### Layer 1: Presentation (Input Validation)
**Where**: Request DTOs in `Presentation/{Module}/API/Request/`
**What**: Format validation: is the input well-formed?
**How**: Constraints on the DTO + `#[MapRequestPayload]` (422 on failure)

```php
namespace App\Presentation\User\API\Request;

use Symfony\Component\Validator\Constraints as Assert;

final readonly class RegisterUserRequest
{
    public function __construct(
        #[Assert\NotBlank]
        #[Assert\Email]
        public string $email = '',

        #[Assert\NotBlank]
        #[Assert\Length(min: 2, max: 100)]
        public string $name = '',

        #[Assert\NotBlank]
        #[Assert\Length(min: 8)]
        #[Assert\Regex(pattern: '/[A-Z]/', message: 'Must contain uppercase')]
        #[Assert\Regex(pattern: '/[0-9]/', message: 'Must contain a number')]
        public string $password = '',
    ) {
    }
}

// Controller
public function register(#[MapRequestPayload] RegisterUserRequest $request): JsonResponse
```

### Layer 2: Application (Command Validation)
**Where**: Command/Query classes, validated by the Messenger `validation` middleware
**What**: Use-case pre-checks: are the values acceptable for this use case (including checks that need ports, e.g. uniqueness)?
**How**: Symfony Validator constraints on command properties

```php
final readonly class RegisterUser
{
    public function __construct(
        #[Assert\NotBlank]
        #[Assert\Email]
        #[UniqueEmail]
        public string $email,

        #[Assert\NotBlank]
        public string $name,

        #[Assert\NotBlank]
        public string $plainPassword,
    ) {
    }
}
```

The `validation` middleware validates before handler execution and throws `Messenger\Exception\ValidationFailedException` (mapped to 422 by `ApiExceptionSubscriber`). Commands dispatched from CLI, Scheduler or other handlers are validated too, which is why this layer exists even with Layer 1.

### Layer 3: Domain (Invariants)
**Where**: Entity constructors/factories, value objects, business methods
**What**: Business invariants: is the operation valid in domain context?
**How**: Pure PHP checks, throw domain exceptions (no `#[Assert]` attributes in Domain)

```php
// Value object self-validates
final readonly class Email
{
    public function __construct(public string $value)
    {
        if (filter_var($value, FILTER_VALIDATE_EMAIL) === false) {
            throw InvalidEmailException::forValue($value);
        }
    }
}

// Entity protects invariants
final class Order
{
    public function cancel(string $reason, \DateTimeImmutable $now): void
    {
        if (!$this->status->canTransitionTo(OrderStatus::CANCELLED)) {
            throw InvalidOrderTransitionException::from($this->id->value, $this->status, OrderStatus::CANCELLED);
        }
        // ...
    }
}
```

## References

See `references/` for detailed guides:
- `validation-layers.md` - Full examples for each layer, custom constraints, `#[ExtendsValidationFor]`, groups, pre-6.3 fallback
