# Layer Responsibilities

## Domain Layer

**Purpose**: Core business logic, rules, and invariants. Pure PHP only.

**Contains**:
- **Entities**: Aggregate roots and entities with business logic
- **Value Objects**: Immutable, self-validating objects (Email, Money, UserId)
- **Domain Events**: Immutable records of something that happened (past-tense naming)
- **Exceptions**: Domain-specific exception classes
- **Ports**: Interfaces defining contracts for external dependencies

**Rules**:
- NO framework imports (`Symfony\`, `Doctrine\`, `Psr\`)
- NO infrastructure concerns (database, HTTP, filesystem)
- Entities use private constructors + static factory methods
- All state changes emit domain events
- Value objects are `final readonly` with self-validation in constructor

**Example Entity**:
```php
namespace App\Domain\User\Entity;

use App\Domain\User\Event\UserRegistered;
use App\Domain\User\ValueObject\Email;
use App\Domain\User\ValueObject\UserId;

final class User
{
    private array $domainEvents = [];

    private function __construct(
        private UserId $id,
        private Email $email,
        private string $name,
        private \DateTimeImmutable $createdAt,
    ) {
    }

    public static function register(UserId $id, Email $email, string $name): self
    {
        $user = new self($id, $email, $name, new \DateTimeImmutable());
        $user->recordEvent(new UserRegistered($id, $email));
        return $user;
    }

    public function pullDomainEvents(): array
    {
        $events = $this->domainEvents;
        $this->domainEvents = [];
        return $events;
    }

    private function recordEvent(object $event): void
    {
        $this->domainEvents[] = $event;
    }
}
```

## Application Layer

**Purpose**: Use case orchestration. Coordinates domain objects and ports.

**Contains**:
- **Commands**: Write operation DTOs (final readonly)
- **Command Handlers**: Execute write operations via `__invoke`
- **Queries**: Read operation DTOs (final readonly)
- **Query Handlers**: Execute read operations, return DTOs
- **DTOs**: Data transfer objects for input/output
- **Event Handlers**: React to domain events (side-effects)

**Rules**:
- May depend on Domain layer only
- Handlers receive ports via constructor injection
- Command handlers return void or a scalar ID
- Query handlers return DTOs, never entities
- Side-effects (email, notifications) go in Event Handlers, not Command Handlers

**Example Command Handler**:
```php
namespace App\Application\User\Command;

use App\Domain\User\Entity\User;
use App\Domain\User\Port\UserRepositoryInterface;
use App\Domain\User\ValueObject\Email;
use App\Domain\User\ValueObject\UserId;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;

#[AsMessageHandler(bus: 'command.bus')]
final readonly class RegisterUserHandler
{
    public function __construct(
        private UserRepositoryInterface $userRepository,
    ) {
    }

    public function __invoke(RegisterUser $command): string
    {
        $userId = UserId::generate();
        $user = User::register($userId, new Email($command->email), $command->name);
        $this->userRepository->save($user);

        return (string) $userId;
    }
}
```

## Infrastructure Layer

**Purpose**: Technical implementations of domain ports.

**Contains**:
- **Persistence**: Doctrine repositories implementing port interfaces, ORM mappings
- **Messaging**: Message transport adapters
- **ExternalService**: HTTP clients, third-party API adapters

**Rules**:
- Implements Domain port interfaces
- Contains ALL framework-specific code (Doctrine, HTTP clients)
- ORM mapping files (XML/attributes) live here, not in Domain
- Repository adapters translate between Domain entities and Doctrine

**Example Repository Adapter**:
```php
namespace App\Infrastructure\User\Persistence;

use App\Domain\User\Entity\User;
use App\Domain\User\Port\UserRepositoryInterface;
use App\Domain\User\ValueObject\UserId;
use Doctrine\ORM\EntityManagerInterface;

final readonly class DoctrineUserRepository implements UserRepositoryInterface
{
    public function __construct(
        private EntityManagerInterface $entityManager,
    ) {
    }

    public function save(User $user): void
    {
        $this->entityManager->persist($user);
        $this->entityManager->flush();
    }

    public function findById(UserId $id): ?User
    {
        return $this->entityManager->find(User::class, (string) $id);
    }
}
```

## Presentation Layer

**Purpose**: Deliver application to the outside world (HTTP, CLI, GraphQL).

**Contains**:
- **API**: REST controllers (thin — delegate to command/query bus)
- **CLI**: Symfony Console commands
- **GraphQL**: Resolvers and type definitions

**Rules**:
- Controllers are thin — dispatch commands/queries only
- Input validation happens here (request validation)
- Response formatting uses standard JSON payload
- Every endpoint must have `#[IsGranted]` or Voter check
- No business logic in controllers

**Example Controller**:
```php
namespace App\Presentation\User\API;

use App\Application\User\Command\RegisterUser;
use App\Presentation\Shared\ApiResponseTrait;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Messenger\MessageBusInterface;
use Symfony\Component\Routing\Attribute\Route;
use Symfony\Component\Security\Http\Attribute\IsGranted;

#[Route('/api/users')]
final class UserController
{
    use ApiResponseTrait;

    public function __construct(
        private readonly MessageBusInterface $commandBus,
    ) {
    }

    #[Route('', methods: ['POST'])]
    #[IsGranted('ROLE_USER_CREATE')]
    public function register(Request $request): JsonResponse
    {
        $data = json_decode($request->getContent(), true);
        $command = new RegisterUser($data['email'], $data['name']);

        $userId = $this->commandBus->dispatch($command);

        return $this->success(['id' => $userId], 201);
    }
}
```
