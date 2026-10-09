# Validation Layers

## Layer 1: Presentation - Input Validation

### Request DTO Pattern

```php
namespace App\Presentation\User\API\Request;

use Symfony\Component\Validator\Constraints as Assert;

final readonly class CreateUserRequest
{
    public function __construct(
        #[Assert\NotBlank(message: 'Email is required')]
        #[Assert\Email(message: 'Invalid email format')]
        public string $email = '',

        #[Assert\NotBlank(message: 'Name is required')]
        #[Assert\Length(min: 2, max: 100, minMessage: 'Name too short', maxMessage: 'Name too long')]
        public string $name = '',

        #[Assert\NotBlank(message: 'Password is required')]
        #[Assert\Length(min: 8, minMessage: 'Password must be at least 8 characters')]
        public string $password = '',
    ) {
    }
}
```

### Controller (Symfony 6.3+)

```php
use Symfony\Component\HttpKernel\Attribute\MapRequestPayload;

#[Route('', methods: ['POST'])]
#[IsGranted('ROLE_USER_CREATE')]
public function create(#[MapRequestPayload] CreateUserRequest $request): JsonResponse
{
    // $request is deserialized AND validated here; failures become a 422 HttpException
    // whose previous exception holds the violations (ApiExceptionSubscriber formats them).
    $userId = $this->commandBus->dispatch(
        new RegisterUser($request->email, $request->name, $request->password),
    );

    return $this->created(['id' => $userId]);
}
```

Useful options: `#[MapRequestPayload(validationGroups: ['create'])]`, `acceptFormat: 'json'`, `validationFailedStatusCode: 422` (default for payloads; `#[MapQueryString]` defaults to 404, set 422 explicitly).

### Fallback for Symfony < 6.3 (legacy projects)

```php
public function create(Request $request, SerializerInterface $serializer, ValidatorInterface $validator): JsonResponse
{
    $dto = $serializer->deserialize($request->getContent(), CreateUserRequest::class, 'json');
    $violations = $validator->validate($dto);
    if (count($violations) > 0) {
        throw new ValidationFailedException($dto, $violations); // same 422 format via the subscriber
    }
    // ...
}
```

## Layer 2: Application - Command/Query Validation

### Automatic via Messenger Middleware

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

use App\Application\User\Validation\UniqueEmail;
use Symfony\Component\Validator\Constraints as Assert;

final readonly class RegisterUser
{
    public function __construct(
        #[Assert\NotBlank]
        #[Assert\Email]
        #[UniqueEmail]
        public string $email,

        #[Assert\NotBlank]
        #[Assert\Length(min: 2)]
        public string $name,

        #[Assert\NotBlank]
        #[Assert\Length(min: 8)]
        public string $plainPassword,
    ) {
    }
}
```

If validation fails, Messenger throws `Symfony\Component\Messenger\Exception\ValidationFailedException`, caught by `ApiExceptionSubscriber`.

## Layer 3: Domain - Invariant Protection

### Value Object Self-Validation

```php
namespace App\Domain\User\ValueObject;

use App\Domain\User\Exception\InvalidAgeException;
use App\Domain\User\Exception\InvalidEmailException;

final readonly class Email
{
    public function __construct(public string $value)
    {
        if (filter_var($value, FILTER_VALIDATE_EMAIL) === false) {
            throw InvalidEmailException::forValue($value);
        }
    }
}

final readonly class Age
{
    public function __construct(public int $value)
    {
        if ($value < 0 || $value > 150) {
            throw InvalidAgeException::outOfRange($value);
        }
    }
}
```

### Entity Business Rule Validation

```php
final class Order
{
    public function addItem(string $productId, int $quantity, Money $unitPrice, \DateTimeImmutable $now): void
    {
        if (!$this->isPending()) {
            throw InvalidOrderTransitionException::itemsLocked($this->id->value, $this->status);
        }
        // OrderItem's constructor rejects quantity <= 0
        // ...
    }
}
```

### Symfony 7.4+: Validator Metadata for Domain Classes Without Touching Them

`#[ExtendsValidationFor]` attaches constraints to a class from a separate class, so Domain stays attribute-free while the Validator can still validate domain objects (for example in an admin form):

```php
namespace App\Infrastructure\User\Validation;

use App\Domain\User\ValueObject\Email;
use Symfony\Component\Validator\Attribute\ExtendsValidationFor;
use Symfony\Component\Validator\Constraints as Assert;

#[ExtendsValidationFor(Email::class)]
abstract class EmailValidation
{
    #[Assert\Email]
    #[Assert\Length(max: 180)]
    public string $value = '';
}
```

Property names must match the target class. On older versions, put the constraints on the Request DTO or Command instead (never on the Domain class).

## Custom Constraint (named arguments: Symfony 6.4 to 8.x)

Constraint option arrays are deprecated since 7.3 and removed in 8.0. Declare a typed constructor:

```php
namespace App\Application\User\Validation;

use Symfony\Component\Validator\Attribute\HasNamedArguments;
use Symfony\Component\Validator\Constraint;

#[\Attribute(\Attribute::TARGET_PROPERTY | \Attribute::TARGET_PARAMETER)]
final class UniqueEmail extends Constraint
{
    public string $message = 'This email is already registered.';

    /** @param list<string>|null $groups */
    #[HasNamedArguments]
    public function __construct(?string $message = null, ?array $groups = null, mixed $payload = null)
    {
        parent::__construct(null, $groups, $payload);
        $this->message = $message ?? $this->message;
    }
}
```

```php
namespace App\Application\User\Validation;

use App\Domain\User\Port\UserRepositoryInterface;
use App\Domain\User\ValueObject\Email;
use Symfony\Component\Validator\Constraint;
use Symfony\Component\Validator\ConstraintValidator;
use Symfony\Component\Validator\Exception\UnexpectedTypeException;

final class UniqueEmailValidator extends ConstraintValidator
{
    public function __construct(
        private readonly UserRepositoryInterface $userRepository,
    ) {
    }

    public function validate(mixed $value, Constraint $constraint): void
    {
        if (!$constraint instanceof UniqueEmail) {
            throw new UnexpectedTypeException($constraint, UniqueEmail::class);
        }
        if (!is_string($value) || $value === '' || filter_var($value, FILTER_VALIDATE_EMAIL) === false) {
            return; // format errors are reported by Assert\Email
        }

        if ($this->userRepository->existsByEmail(new Email($value))) {
            $this->context->buildViolation($constraint->message)->addViolation();
        }
    }
}
```

The constraint lives in Application because it needs a Domain port; Presentation must not import Domain ports. The unique DB index remains the real guarantee under concurrency.

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

// Controller
public function update(#[MapRequestPayload(validationGroups: ['name'])] UpdateUserRequest $request): JsonResponse

// Messenger: attach groups to a command dispatch
$this->commandBus->dispatch($command, [new ValidationStamp(['Default', 'strict'])]);
```

## Validation Flow Summary

```
Request → [L1: Format valid?] → Command → [L2: Use-case pre-check?] → Handler → [L3: Domain invariant?] → Success
              ↓ 422                           ↓ 422                              ↓ 422 / 409 (domain exception)
        HttpException(previous:        Messenger ValidationFailed          Domain Exception
        ValidationFailedException)
```
