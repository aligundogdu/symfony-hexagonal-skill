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
│   └── routes/
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
│   │       └── Port/
│   │           └── {RepositoryInterface}.php
│   ├── Application/
│   │   └── {Module}/
│   │       ├── Command/
│   │       │   ├── {ActionCommand}.php
│   │       │   └── {ActionCommandHandler}.php
│   │       ├── Query/
│   │       │   ├── {GetQuery}.php
│   │       │   └── {GetQueryHandler}.php
│   │       ├── DTO/
│   │       │   └── {DataDTO}.php
│   │       └── EventHandler/
│   │           └── {WhenEventHandler}.php
│   ├── Infrastructure/
│   │   └── {Module}/
│   │       ├── Persistence/
│   │       │   ├── Doctrine{Entity}Repository.php
│   │       │   └── Mapping/
│   │       │       └── {Entity}.orm.xml
│   │       ├── Messaging/
│   │       │   └── {ExternalMessaging}.php
│   │       └── ExternalService/
│   │           └── {ApiClient}.php
│   └── Presentation/
│       └── {Module}/
│           ├── API/
│           │   └── {Entity}Controller.php
│           ├── CLI/
│           │   └── {ActionCommand}.php
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
│   └── Functional/
│       └── Presentation/
│           └── {Module}/
└── migrations/
```

## Example: User Module

```
src/
├── Domain/User/
│   ├── Entity/User.php
│   ├── ValueObject/Email.php
│   ├── ValueObject/UserId.php
│   ├── Event/UserRegistered.php
│   ├── Exception/UserAlreadyExistsException.php
│   └── Port/UserRepositoryInterface.php
├── Application/User/
│   ├── Command/RegisterUser.php
│   ├── Command/RegisterUserHandler.php
│   ├── Query/GetUserById.php
│   ├── Query/GetUserByIdHandler.php
│   ├── DTO/UserDTO.php
│   └── EventHandler/WhenUserRegisteredSendWelcomeEmail.php
├── Infrastructure/User/
│   ├── Persistence/
│   │   ├── DoctrineUserRepository.php
│   │   └── Mapping/User.orm.xml
│   └── ExternalService/
│       └── MailerAdapter.php
└── Presentation/User/
    ├── API/UserController.php
    └── CLI/CreateUserCommand.php
```

## Namespace Convention

```php
// Domain
namespace App\Domain\User\Entity;
namespace App\Domain\User\ValueObject;
namespace App\Domain\User\Event;
namespace App\Domain\User\Exception;
namespace App\Domain\User\Port;

// Application
namespace App\Application\User\Command;
namespace App\Application\User\Query;
namespace App\Application\User\DTO;
namespace App\Application\User\EventHandler;

// Infrastructure
namespace App\Infrastructure\User\Persistence;
namespace App\Infrastructure\User\Messaging;
namespace App\Infrastructure\User\ExternalService;

// Presentation
namespace App\Presentation\User\API;
namespace App\Presentation\User\CLI;
namespace App\Presentation\User\GraphQL;
```

## services.yaml Module Binding

```yaml
services:
    # Auto-configure each layer
    App\Domain\:
        resource: '../src/Domain/'

    App\Application\:
        resource: '../src/Application/'

    App\Infrastructure\:
        resource: '../src/Infrastructure/'

    App\Presentation\:
        resource: '../src/Presentation/'

    # Bind ports to adapters
    App\Domain\User\Port\UserRepositoryInterface:
        alias: App\Infrastructure\User\Persistence\DoctrineUserRepository
```
