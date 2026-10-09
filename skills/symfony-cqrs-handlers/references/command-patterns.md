# Command Patterns

## Full Command + Handler Example

### Command

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
        #[Assert\Length(min: 2, max: 100)]
        public string $name,

        #[Assert\NotBlank]
        #[Assert\Length(min: 8)]
        #[\SensitiveParameter]
        public string $plainPassword,
    ) {
    }
}
```

Always pass constraint options as named arguments (`Length(min: 2)`): option arrays are deprecated since Symfony 7.3 and removed in 8.0, while named arguments work on every supported version.

### Password Hashing Port

Hashing is an external concern, so the handler depends on a Domain port, not on `UserPasswordHasherInterface`:

```php
namespace App\Domain\User\Port;

interface PasswordHasherInterface
{
    public function hash(string $plainPassword): string;

    public function verify(string $hash, string $plainPassword): bool;
}
```

```php
namespace App\Infrastructure\User\Security;

use App\Domain\User\Port\PasswordHasherInterface;
use Symfony\Component\PasswordHasher\Hasher\PasswordHasherFactoryInterface;

final readonly class SymfonyPasswordHasher implements PasswordHasherInterface
{
    public function __construct(
        private PasswordHasherFactoryInterface $hasherFactory,
    ) {
    }

    public function hash(string $plainPassword): string
    {
        return $this->hasherFactory->getPasswordHasher(SecurityUser::class)->hash($plainPassword);
    }

    public function verify(string $hash, string $plainPassword): bool
    {
        return $this->hasherFactory->getPasswordHasher(SecurityUser::class)->verify($hash, $plainPassword);
    }
}
```

### Handler

```php
namespace App\Application\User\Command;

use App\Domain\Shared\Port\IdGeneratorInterface;
use App\Domain\User\Entity\User;
use App\Domain\User\Exception\UserAlreadyExistsException;
use App\Domain\User\Port\PasswordHasherInterface;
use App\Domain\User\Port\UserRepositoryInterface;
use App\Domain\User\ValueObject\Email;
use App\Domain\User\ValueObject\UserId;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;

#[AsMessageHandler(bus: 'command.bus')]
final readonly class RegisterUserHandler
{
    public function __construct(
        private UserRepositoryInterface $userRepository,
        private PasswordHasherInterface $passwordHasher,
        private IdGeneratorInterface $ids,
    ) {
    }

    public function __invoke(RegisterUser $command): string
    {
        $email = new Email($command->email);

        if ($this->userRepository->existsByEmail($email)) {
            throw UserAlreadyExistsException::withEmail($email->value);
        }

        $user = User::register(
            new UserId($this->ids->generate()),
            $email,
            $command->name,
            $this->passwordHasher->hash($command->plainPassword),
            new \DateTimeImmutable(),
        );

        $this->userRepository->save($user);

        return $user->id()->value;
    }
}
```

The `existsByEmail` check gives a friendly error; the unique index on `email` is what actually guarantees uniqueness under concurrency.

## Command That Updates

```php
final readonly class UpdateUserProfile
{
    public function __construct(
        public string $userId,
        public ?string $name = null,
        public ?string $bio = null,
    ) {
    }
}

#[AsMessageHandler(bus: 'command.bus')]
final readonly class UpdateUserProfileHandler
{
    public function __construct(
        private UserRepositoryInterface $userRepository,
    ) {
    }

    public function __invoke(UpdateUserProfile $command): void
    {
        $user = $this->userRepository->findById(new UserId($command->userId))
            ?? throw UserNotFoundException::withId($command->userId);

        if ($command->name !== null) {
            $user->changeName($command->name);
        }
        if ($command->bio !== null) {
            $user->updateBio($command->bio);
        }

        $this->userRepository->save($user);
    }
}
```

## Command That Deactivates

```php
final readonly class DeactivateUser
{
    public function __construct(
        public string $userId,
        public string $reason,
    ) {
    }
}

#[AsMessageHandler(bus: 'command.bus')]
final readonly class DeactivateUserHandler
{
    public function __construct(
        private UserRepositoryInterface $userRepository,
    ) {
    }

    public function __invoke(DeactivateUser $command): void
    {
        $user = $this->userRepository->findById(new UserId($command->userId))
            ?? throw UserNotFoundException::withId($command->userId);

        $user->deactivate($command->reason, new \DateTimeImmutable());
        $this->userRepository->save($user);
    }
}
```

## Dispatching Commands from Controllers

```php
// Presentation\Shared\Bus\CommandBus returns the handler result and unwraps HandlerFailedException
$userId = $this->commandBus->dispatch(new RegisterUser($email, $name, $password));
```

If you must use `MessageBusInterface` directly: `$envelope->last(HandledStamp::class)?->getResult()` gives the result, and every handler exception arrives wrapped in `HandlerFailedException` (use `$e->getPrevious()`).

## Async Commands

Some commands can be dispatched asynchronously. The handler code does not change.

```yaml
# messenger.yaml (all versions)
framework:
    messenger:
        routing:
            'App\Application\Report\Command\GenerateReport': async
            'App\Application\Email\Command\SendBulkEmail': async
```

Symfony 7.2+ alternative, on the command class itself (Application may import Messenger):

```php
use Symfony\Component\Messenger\Attribute\AsMessage;

#[AsMessage('async')]
final readonly class GenerateReport { /* ... */ }
```

YAML routing wins when both are set. Async command handlers must be idempotent (see the messenger-async skill), and `CommandBus::dispatch()` returns `null` for them because nothing was handled yet: return `202` with an ID generated before dispatch instead.
