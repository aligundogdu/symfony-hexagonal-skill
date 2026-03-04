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
        public string $password,
    ) {
    }
}
```

### Handler

```php
namespace App\Application\User\Command;

use App\Domain\User\Entity\User;
use App\Domain\User\Exception\UserAlreadyExistsException;
use App\Domain\User\Port\UserRepositoryInterface;
use App\Domain\User\ValueObject\Email;
use App\Domain\User\ValueObject\UserId;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;
use Symfony\Component\PasswordHasher\Hasher\UserPasswordHasherInterface;

#[AsMessageHandler(bus: 'command.bus')]
final readonly class RegisterUserHandler
{
    public function __construct(
        private UserRepositoryInterface $userRepository,
        private UserPasswordHasherInterface $passwordHasher,
    ) {
    }

    public function __invoke(RegisterUser $command): string
    {
        $email = new Email($command->email);

        if ($this->userRepository->existsByEmail($email)) {
            throw UserAlreadyExistsException::withEmail($email);
        }

        $userId = UserId::generate();
        $hashedPassword = $this->passwordHasher->hashPassword(/* ... */);
        $user = User::register($userId, $email, $command->name, $hashedPassword);

        $this->userRepository->save($user);

        return $userId->value;
    }
}
```

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
        $user = $this->userRepository->findById(new UserId($command->userId));
        if ($user === null) {
            throw UserNotFoundException::withId($command->userId);
        }

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

## Command That Deletes

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
        $user = $this->userRepository->findById(new UserId($command->userId));
        if ($user === null) {
            throw UserNotFoundException::withId($command->userId);
        }

        $user->deactivate($command->reason);
        $this->userRepository->save($user);
    }
}
```

## Dispatching Commands from Controllers

```php
use Symfony\Component\Messenger\MessageBusInterface;
use Symfony\Component\Messenger\Stamp\HandledStamp;

// In controller:
$envelope = $this->commandBus->dispatch(new RegisterUser($email, $name, $password));

// Get return value if handler returns something:
$handledStamp = $envelope->last(HandledStamp::class);
$userId = $handledStamp->getResult();
```

## Async Commands

Some commands can be dispatched asynchronously:

```yaml
# messenger.yaml
framework:
    messenger:
        routing:
            'App\Application\Report\Command\GenerateReport': async
            'App\Application\Email\Command\SendBulkEmail': async
```
