# Validation Layers

## Layer 1: Presentation — Input Validation

### Request DTO Pattern

```php
namespace App\Presentation\User\API\Request;

use Symfony\Component\Validator\Constraints as Assert;

final readonly class CreateUserRequest
{
    public function __construct(
        #[Assert\NotBlank(message: 'Email is required')]
        #[Assert\Email(message: 'Invalid email format')]
        public string $email,

        #[Assert\NotBlank(message: 'Name is required')]
        #[Assert\Length(min: 2, max: 100, minMessage: 'Name too short', maxMessage: 'Name too long')]
        public string $name,

        #[Assert\NotBlank(message: 'Password is required')]
        #[Assert\Length(min: 8, minMessage: 'Password must be at least 8 characters')]
        public string $password,
    ) {
    }
}
```

### Controller Validation

```php
use Symfony\Component\Validator\Validator\ValidatorInterface;

#[Route('', methods: ['POST'])]
#[IsGranted('ROLE_USER_CREATE')]
public function create(Request $request, ValidatorInterface $validator): JsonResponse
{
    $data = json_decode($request->getContent(), true, 512, JSON_THROW_ON_ERROR);

    $requestDto = new CreateUserRequest(
        email: $data['email'] ?? '',
        name: $data['name'] ?? '',
        password: $data['password'] ?? '',
    );

    $violations = $validator->validate($requestDto);

    if ($violations->count() > 0) {
        $errors = [];
        foreach ($violations as $violation) {
            $errors[$violation->getPropertyPath()][] = $violation->getMessage();
        }
        return $this->error('Validation failed', 422, 'VALIDATION_ERROR', $errors);
    }

    $command = new RegisterUser($requestDto->email, $requestDto->name, $requestDto->password);
    $userId = $this->commandBus->dispatch($command)
        ->last(HandledStamp::class)?->getResult();

    return $this->created(['id' => $userId]);
}
```

## Layer 2: Application — Command/Query Validation

### Automatic via Messenger Middleware

The `validation` middleware validates commands/queries before they reach the handler:

```yaml
framework:
    messenger:
        buses:
            command.bus:
                middleware:
                    - validation        # <-- validates automatically
                    - doctrine_transaction
```

```php
namespace App\Application\User\Command;

use Symfony\Component\Validator\Constraints as Assert;

final readonly class RegisterUser
{
    public function __construct(
        #[Assert\NotBlank]
        #[Assert\Email]
        public string $email,

        #[Assert\NotBlank]
        #[Assert\Length(min: 2)]
        public string $name,

        #[Assert\NotBlank]
        #[Assert\Length(min: 8)]
        public string $password,
    ) {
    }
}
```

If validation fails, Messenger throws `ValidationFailedException` — caught by `ApiExceptionSubscriber`.

## Layer 3: Domain — Invariant Protection

### Value Object Self-Validation

```php
namespace App\Domain\User\ValueObject;

final readonly class Email
{
    public function __construct(public string $value)
    {
        if (!filter_var($value, FILTER_VALIDATE_EMAIL)) {
            throw InvalidEmailException::forValue($value);
        }
    }
}

final readonly class Age
{
    public function __construct(public int $value)
    {
        if ($value < 0 || $value > 150) {
            throw new \InvalidArgumentException(sprintf('Invalid age: %d', $value));
        }
    }
}
```

### Entity Business Rule Validation

```php
final class Order
{
    public function addItem(string $productId, int $quantity, Money $price): void
    {
        if ($this->status !== OrderStatus::PENDING) {
            throw new \DomainException('Can only add items to pending orders');
        }
        if ($quantity <= 0) {
            throw new \InvalidArgumentException('Quantity must be positive');
        }
        // ...
    }
}
```

## Custom Constraint

```php
namespace App\Presentation\Shared\Constraint;

use Symfony\Component\Validator\Constraint;

#[\Attribute]
final class UniqueEmail extends Constraint
{
    public string $message = 'This email is already registered.';
}
```

```php
namespace App\Presentation\Shared\Constraint;

use App\Domain\User\Port\UserRepositoryInterface;
use App\Domain\User\ValueObject\Email;
use Symfony\Component\Validator\Constraint;
use Symfony\Component\Validator\ConstraintValidator;

final class UniqueEmailValidator extends ConstraintValidator
{
    public function __construct(
        private readonly UserRepositoryInterface $userRepository,
    ) {
    }

    public function validate(mixed $value, Constraint $constraint): void
    {
        if ($value === null || $value === '') {
            return;
        }

        try {
            $email = new Email($value);
        } catch (\Exception) {
            return; // Email format validation is handled by Assert\Email
        }

        if ($this->userRepository->existsByEmail($email)) {
            $this->context->buildViolation($constraint->message)->addViolation();
        }
    }
}
```

## Validation Groups

```php
final readonly class UpdateUserRequest
{
    public function __construct(
        #[Assert\NotBlank(groups: ['name'])]
        #[Assert\Length(min: 2, max: 100, groups: ['name'])]
        public ?string $name = null,

        #[Assert\Email(groups: ['email'])]
        public ?string $email = null,
    ) {
    }
}

// Validate specific groups:
$violations = $validator->validate($request, null, ['name']);
```

## Validation Flow Summary

```
Request → [L1: Format valid?] → Command → [L2: Business pre-check?] → Handler → [L3: Domain invariant?] → Success
              ↓ 422                           ↓ 422                           ↓ 422 (DomainException)
          Validation Error            ValidationFailed              Domain Exception
```
