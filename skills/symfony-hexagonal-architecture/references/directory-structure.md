# Directory Structure Reference

## Full Project Layout

```
project-root/
├── config/
│   ├── packages/
│   │   ├── messenger.yaml
│   │   ├── security.yaml
│   │   └── doctrine.yaml
│   ├── services.yaml
│   └── routes.yaml
├── src/
│   ├── Domain/
│   │   └── {Module}/
│   │       ├── Entity/
│   │       │   └── {AggregateRoot}.php
│   │       ├── ValueObject/
│   │       │   └── {ValueObject}.php
│   │       ├── Event/
│   │       │   └── {PastTenseEvent}.php
│   │       ├── Exception/
│   │       │   └── {DomainException}.php
│   │       ├── Port/
│   │       │   ├── {Entity}RepositoryInterface.php
│   │       │   └── {Entity}ReadRepositoryInterface.php
│   │       └── ReadModel/
│   │           └── {Entity}View.php
│   ├── Application/
│   │   └── {Module}/
│   │       ├── Command/
│   │       │   ├── {ActionCommand}.php
│   │       │   └── {ActionCommand}Handler.php
│   │       ├── Query/
│   │       │   ├── {GetQuery}.php
│   │       │   └── {GetQuery}Handler.php
│   │       ├── DTO/
│   │       │   └── {Data}DTO.php
│   │       └── EventHandler/
│   │           └── When{Event}{Action}.php
│   ├── Infrastructure/
│   │   └── {Module}/
│   │       ├── Persistence/
│   │       │   ├── Doctrine{Entity}Repository.php
│   │       │   ├── Dbal{Entity}ReadRepository.php
│   │       │   └── Mapping/
│   │       │       └── Entity.{Entity}.orm.xml
│   │       ├── Security/
│   │       │   └── {Entity}Voter.php
│   │       ├── Messaging/
│   │       │   └── {ExternalMessaging}.php
│   │       └── ExternalService/
│   │           └── {ApiClient}.php
│   └── Presentation/
│       └── {Module}/
│           ├── API/
│           │   ├── {Entity}Controller.php
│           │   └── Request/
│           │       └── {Action}Request.php
│           ├── CLI/
│           │   └── {Action}ConsoleCommand.php
│           └── GraphQL/
│               ├── Type/
│               └── Resolver/
├── tests/
│   ├── Unit/
│   │   └── Domain/
│   │       └── {Module}/
│   ├── Integration/
│   │   └── Application/
│   │       └── {Module}/
│   ├── Functional/
│   │   └── Presentation/
│   │       └── {Module}/
│   └── Support/
│       └── Adapter/
│           └── InMemory{Entity}Repository.php
└── migrations/
```

## Example: User Module

```
src/
├── Domain/Shared/
│   ├── Event/DomainEvent.php
│   ├── Port/IdGeneratorInterface.php
│   └── ReadModel/Page.php
├── Domain/User/
│   ├── Entity/User.php
│   ├── ValueObject/Email.php
│   ├── ValueObject/UserId.php
│   ├── Event/UserRegistered.php
│   ├── Exception/UserAlreadyExistsException.php
│   ├── Port/UserRepositoryInterface.php
│   ├── Port/UserReadRepositoryInterface.php
│   ├── Port/PasswordHasherInterface.php
│   └── ReadModel/UserView.php
├── Application/User/
│   ├── Command/RegisterUser.php
│   ├── Command/RegisterUserHandler.php
│   ├── Query/GetUserById.php
│   ├── Query/GetUserByIdHandler.php
│   ├── DTO/UserDTO.php
│   └── EventHandler/WhenUserRegisteredSendWelcomeEmail.php
├── Infrastructure/Shared/
│   └── Identity/SymfonyUuidGenerator.php
├── Infrastructure/User/
│   ├── Persistence/
│   │   ├── DoctrineUserRepository.php
│   │   ├── DbalUserReadRepository.php
│   │   └── Mapping/
│   │       ├── Entity.User.orm.xml
│   │       └── ValueObject.Email.orm.xml
│   ├── Security/
│   │   ├── SecurityUser.php
│   │   ├── SecurityUserProvider.php
│   │   └── SymfonyPasswordHasher.php
│   └── ExternalService/
│       └── MailerNotificationService.php
├── Presentation/Shared/
│   ├── ApiResponseTrait.php
│   ├── Bus/CommandBus.php
│   ├── Bus/QueryBus.php
│   └── EventSubscriber/ApiExceptionSubscriber.php
└── Presentation/User/
    ├── API/UserController.php
    ├── API/Request/RegisterUserRequest.php
    └── CLI/CreateUserConsoleCommand.php
```

## Namespace Convention

```php
// Domain
namespace App\Domain\User\Entity;
namespace App\Domain\User\ValueObject;
namespace App\Domain\User\Event;
namespace App\Domain\User\Exception;
namespace App\Domain\User\Port;
namespace App\Domain\User\ReadModel;

// Application
namespace App\Application\User\Command;
namespace App\Application\User\Query;
namespace App\Application\User\DTO;
namespace App\Application\User\EventHandler;

// Infrastructure
namespace App\Infrastructure\User\Persistence;
namespace App\Infrastructure\User\Security;
namespace App\Infrastructure\User\Messaging;
namespace App\Infrastructure\User\ExternalService;

// Presentation
namespace App\Presentation\User\API;
namespace App\Presentation\User\CLI;
namespace App\Presentation\User\GraphQL;
```

## services.yaml (works on Symfony 6.4, 7.x, 8.x)

```yaml
services:
    _defaults:
        autowire: true
        autoconfigure: true
        bind:
            $eventBus: '@event.bus'

    App\:
        resource: '../src/'
        exclude:
            - '../src/Kernel.php'
            # Domain data classes are never services
            - '../src/Domain/*/Entity/'
            - '../src/Domain/*/ValueObject/'
            - '../src/Domain/*/Event/'
            - '../src/Domain/*/Exception/'
            - '../src/Domain/*/ReadModel/'
            - '../src/Application/*/DTO/'
            - '../src/Presentation/*/API/Request/'

    # Bind ports to adapters
    App\Domain\Shared\Port\IdGeneratorInterface:
        alias: App\Infrastructure\Shared\Identity\SymfonyUuidGenerator

    App\Domain\User\Port\UserRepositoryInterface:
        alias: App\Infrastructure\User\Persistence\DoctrineUserRepository

    App\Domain\User\Port\UserReadRepositoryInterface:
        alias: App\Infrastructure\User\Persistence\DbalUserReadRepository

    App\Domain\User\Port\PasswordHasherInterface:
        alias: App\Infrastructure\User\Security\SymfonyPasswordHasher
```

Symfony 7.4+ alternative: `#[AsAlias(UserRepositoryInterface::class)]` on the adapter class (available since 6.3) keeps the binding next to the adapter. YAML aliases remain the most visible option and work everywhere.

## Routes for Presentation Controllers

```yaml
# config/routes.yaml
api:
    resource:
        path: ../src/Presentation/
        namespace: App\Presentation
    type: attribute
```
