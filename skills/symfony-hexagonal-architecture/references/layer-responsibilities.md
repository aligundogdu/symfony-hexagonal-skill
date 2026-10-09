# Layer Responsibilities

All examples target the baseline (PHP 8.2+, Symfony 6.4+) unless marked otherwise. See `version-compatibility.md`.

## Domain Layer

**Purpose**: Core business logic, rules, and invariants. Pure PHP only.

**Contains**:
- **Entities**: Aggregate roots and entities with business logic
- **Value Objects**: Immutable, self-validating objects (Email, Money, UserId)
- **Domain Events**: Immutable records of something that happened (past-tense naming)
- **Exceptions**: Domain-specific exception classes
- **Ports**: Interfaces defining contracts for external dependencies (persistence, IDs, hashing, clock, notifications)
- **Read models** (optional): Plain view objects returned by read ports

**Rules**:
- NO framework imports (`Symfony\`, `Doctrine\`, `Psr\`) and no framework attributes
- NO infrastructure concerns (database, HTTP, filesystem, UUID libraries)
- Entities use private constructors + static factory methods
- All state changes emit domain events
- Value objects are `final readonly` with self-validation in constructor

**Example Entity**:
```php
namespace App\Domain\User\Entity;

use App\Domain\Shared\Event\DomainEvent;
use App\Domain\User\Event\UserRegistered;
use App\Domain\User\ValueObject\Email;
use App\Domain\User\ValueObject\UserId;

final class User
{
    /** @var list<DomainEvent> */
    private array $domainEvents = [];

    private function __construct(
        private UserId $id,
        private Email $email,
        private string $name,
        private string $passwordHash,
        private \DateTimeImmutable $createdAt,
    ) {
    }

    public static function register(
        UserId $id,
        Email $email,
        string $name,
        string $passwordHash,
        \DateTimeImmutable $now,
    ): self {
        $user = new self($id, $email, $name, $passwordHash, $now);
        $user->recordEvent(new UserRegistered($id->value, $email->value, $now));

        return $user;
    }

    public function id(): UserId
    {
        return $this->id;
    }

    public function email(): Email
    {
        return $this->email;
    }

    public function name(): string
    {
        return $this->name;
    }

    public function passwordHash(): string
    {
        return $this->passwordHash;
    }

    /** @return list<DomainEvent> */
    public function pullDomainEvents(): array
    {
        $events = $this->domainEvents;
        $this->domainEvents = [];

        return $events;
    }

    private function recordEvent(DomainEvent $event): void
    {
        $this->domainEvents[] = $event;
    }
}
```

PHP 8.4+ (Symfony 8 projects) may replace getters with asymmetric visibility: `public private(set) Email $email`. Doctrine ORM 3.4+ supports it. Keep getters on PHP 8.2/8.3.

## Application Layer

**Purpose**: Use case orchestration. Coordinates domain objects and ports.

**Contains**:
- **Commands**: Write operation messages (final readonly)
- **Command Handlers**: Execute write operations via `__invoke`
- **Queries**: Read operation messages (final readonly)
- **Query Handlers**: Execute read operations, return DTOs
- **DTOs**: Data transfer objects for output
- **Event Handlers**: React to domain events (side-effects)

**Rules**:
- May depend on Domain layer only (plus Messenger/Validator attributes)
- Handlers receive ports via constructor injection
- Command handlers return void or a scalar ID
- Query handlers return DTOs, never entities
- Side-effects (email, notifications) go in Event Handlers, not Command Handlers

**Example Command Handler**:
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
        private UserRepositoryInterface $users,
        private PasswordHasherInterface $passwordHasher,
        private IdGeneratorInterface $ids,
    ) {
    }

    public function __invoke(RegisterUser $command): string
    {
        $email = new Email($command->email);
        if ($this->users->existsByEmail($email)) {
            throw UserAlreadyExistsException::withEmail($email->value);
        }

        $user = User::register(
            new UserId($this->ids->generate()),
            $email,
            $command->name,
            $this->passwordHasher->hash($command->plainPassword),
            new \DateTimeImmutable(),
        );
        $this->users->save($user);

        return $user->id()->value;
    }
}
```

## Infrastructure Layer

**Purpose**: Technical implementations of domain ports.

**Contains**:
- **Persistence**: Doctrine repositories implementing port interfaces, XML mappings
- **Security**: Voters, user providers, password hasher adapters
- **Messaging**: Message transport adapters, middleware
- **ExternalService**: HTTP clients, third-party API adapters

**Rules**:
- Implements Domain port interfaces (framework glue such as voters, middleware and Doctrine types is also allowed here)
- Contains ALL framework-specific code (Doctrine, HTTP clients)
- ORM mapping files (XML) live here, not in Domain
- Repository adapters translate between Domain entities and Doctrine

**Example Repository Adapter**:
```php
namespace App\Infrastructure\User\Persistence;

use App\Domain\User\Entity\User;
use App\Domain\User\Port\UserRepositoryInterface;
use App\Domain\User\ValueObject\Email;
use App\Domain\User\ValueObject\UserId;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Component\Messenger\MessageBusInterface;
use Symfony\Component\Messenger\Stamp\DispatchAfterCurrentBusStamp;

final readonly class DoctrineUserRepository implements UserRepositoryInterface
{
    public function __construct(
        private EntityManagerInterface $entityManager,
        private MessageBusInterface $eventBus,
    ) {
    }

    public function save(User $user): void
    {
        $this->entityManager->persist($user);
        $this->entityManager->flush();

        // Released only after the current command (and its DB transaction) succeeded
        foreach ($user->pullDomainEvents() as $event) {
            $this->eventBus->dispatch($event, [new DispatchAfterCurrentBusStamp()]);
        }
    }

    public function findById(UserId $id): ?User
    {
        return $this->entityManager->find(User::class, $id->value);
    }

    public function existsByEmail(Email $email): bool
    {
        return $this->entityManager->getRepository(User::class)
            ->count(['email.value' => $email->value]) > 0;
    }
}
```

## Presentation Layer

**Purpose**: Deliver application to the outside world (HTTP, CLI, GraphQL).

**Contains**:
- **API**: REST controllers (thin, delegate to command/query bus) and Request DTOs
- **CLI**: Symfony Console commands
- **GraphQL**: Resolvers and type definitions

**Rules**:
- Controllers are thin, dispatch commands/queries only
- Input is mapped + validated with `#[MapRequestPayload]` / `#[MapQueryString]` (Symfony 6.3+)
- Response formatting uses standard JSON payload
- Every endpoint must have `#[IsGranted]` or Voter check
- No business logic in controllers

**Example Controller**:
```php
namespace App\Presentation\User\API;

use App\Application\User\Command\RegisterUser;
use App\Presentation\Shared\ApiResponseTrait;
use App\Presentation\Shared\Bus\CommandBus;
use App\Presentation\User\API\Request\RegisterUserRequest;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpKernel\Attribute\MapRequestPayload;
use Symfony\Component\Routing\Attribute\Route;
use Symfony\Component\Security\Http\Attribute\IsGranted;

#[Route('/api/users')]
final class UserController
{
    use ApiResponseTrait;

    public function __construct(
        private readonly CommandBus $commandBus,
    ) {
    }

    #[Route('', methods: ['POST'])]
    #[IsGranted('ROLE_USER_CREATE')]
    public function register(#[MapRequestPayload] RegisterUserRequest $request): JsonResponse
    {
        $userId = $this->commandBus->dispatch(
            new RegisterUser($request->email, $request->name, $request->password),
        );

        return $this->created(['id' => $userId]);
    }
}
```

`CommandBus` / `QueryBus` are small Presentation helpers around Messenger that return the handler result and unwrap `HandlerFailedException` (see the cqrs-handlers skill, `bus-configuration.md`). `Symfony\Component\Routing\Attribute\Route` exists since 6.2; on older code it was `Routing\Annotation\Route`.
