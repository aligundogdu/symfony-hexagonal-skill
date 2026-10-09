# Role Hierarchy Design

## Naming Convention

```
ROLE_{MODULE}_{ACTION}
```

| Module | Actions |
|--------|---------|
| USER | CREATE, VIEW, LIST, EDIT, DELETE |
| ORDER | CREATE, VIEW, LIST, EDIT, CANCEL, MANAGE |
| PRODUCT | CREATE, VIEW, LIST, EDIT, DELETE, PUBLISH |
| REPORT | VIEW, GENERATE, EXPORT |
| SETTINGS | VIEW, EDIT |

## Example Hierarchy

```yaml
# config/packages/security.yaml
security:
    role_hierarchy:
        # Super admin
        ROLE_SUPER_ADMIN:
            - ROLE_ADMIN

        # Admin inherits all management roles
        ROLE_ADMIN:
            - ROLE_USER_MANAGE
            - ROLE_ORDER_MANAGE
            - ROLE_PRODUCT_MANAGE
            - ROLE_REPORT_MANAGE
            - ROLE_SETTINGS_MANAGE

        # Management roles group CRUDs
        ROLE_USER_MANAGE:
            - ROLE_USER_CREATE
            - ROLE_USER_VIEW
            - ROLE_USER_LIST
            - ROLE_USER_EDIT
            - ROLE_USER_DELETE

        ROLE_ORDER_MANAGE:
            - ROLE_ORDER_CREATE
            - ROLE_ORDER_VIEW
            - ROLE_ORDER_LIST
            - ROLE_ORDER_EDIT
            - ROLE_ORDER_CANCEL

        ROLE_PRODUCT_MANAGE:
            - ROLE_PRODUCT_CREATE
            - ROLE_PRODUCT_VIEW
            - ROLE_PRODUCT_LIST
            - ROLE_PRODUCT_EDIT
            - ROLE_PRODUCT_DELETE
            - ROLE_PRODUCT_PUBLISH

        ROLE_REPORT_MANAGE:
            - ROLE_REPORT_VIEW
            - ROLE_REPORT_GENERATE
            - ROLE_REPORT_EXPORT

        ROLE_SETTINGS_MANAGE:
            - ROLE_SETTINGS_VIEW
            - ROLE_SETTINGS_EDIT

        # Staff roles
        ROLE_MANAGER:
            - ROLE_ORDER_MANAGE
            - ROLE_PRODUCT_VIEW
            - ROLE_PRODUCT_LIST
            - ROLE_REPORT_MANAGE

        ROLE_SUPPORT:
            - ROLE_USER_VIEW
            - ROLE_USER_LIST
            - ROLE_ORDER_VIEW
            - ROLE_ORDER_LIST

        # Basic user
        ROLE_USER:
            - ROLE_USER_VIEW
```

## Full security.yaml

The domain `User` is not a Symfony `UserInterface`. Infrastructure provides a small adapter + provider, so Domain stays framework-free.

```yaml
security:
    password_hashers:
        App\Infrastructure\User\Security\SecurityUser: 'auto'

    providers:
        app_user_provider:
            id: App\Infrastructure\User\Security\SecurityUserProvider

    firewalls:
        dev:
            pattern: ^/(_(profiler|wdt)|css|images|js)/
            security: false

        api:
            pattern: ^/api
            stateless: true
            provider: app_user_provider
            entry_point: App\Presentation\Shared\Security\ApiAuthenticationEntryPoint
            json_login:
                check_path: /api/login
            # Token auth, pick one:
            # access_token:                       # built in since Symfony 6.2
            #     token_handler: App\Infrastructure\Shared\Security\ApiTokenHandler
            # jwt: ~                              # requires lexik/jwt-authentication-bundle

        main:
            lazy: true
            provider: app_user_provider

    access_control:
        - { path: ^/api/login, roles: PUBLIC_ACCESS }
        - { path: ^/api/docs, roles: PUBLIC_ACCESS }
        - { path: ^/api, roles: IS_AUTHENTICATED_FULLY }

    role_hierarchy:
        # ... as above
```

### Security User Adapter

```php
namespace App\Infrastructure\User\Security;

use App\Domain\User\Entity\User;
use Symfony\Component\Security\Core\User\PasswordAuthenticatedUserInterface;
use Symfony\Component\Security\Core\User\UserInterface;

final readonly class SecurityUser implements UserInterface, PasswordAuthenticatedUserInterface
{
    /** @param list<string> $roles */
    public function __construct(
        private string $id,
        private string $email,
        private string $passwordHash,
        private array $roles,
    ) {
    }

    public static function fromDomain(User $user): self
    {
        // Map domain permissions to roles here if the domain models them (e.g. $user->roles())
        return new self($user->id()->value, $user->email()->value, $user->passwordHash(), ['ROLE_USER']);
    }

    public function getUserIdentifier(): string
    {
        return $this->id; // stable ID, so voters can compare it with ownerId/customerId
    }

    public function getEmail(): string
    {
        return $this->email;
    }

    public function getRoles(): array
    {
        return array_values(array_unique([...$this->roles, 'ROLE_USER']));
    }

    public function getPassword(): string
    {
        return $this->passwordHash;
    }

    /**
     * Required by UserInterface up to Symfony 7.x, deprecated since 7.3. Nothing to erase:
     * plain passwords never live on this object.
     */
    public function eraseCredentials(): void
    {
    }
}
```

```php
namespace App\Infrastructure\User\Security;

use App\Domain\User\Port\UserRepositoryInterface;
use App\Domain\User\ValueObject\Email;
use App\Domain\User\ValueObject\UserId;
use Symfony\Component\Security\Core\Exception\UnsupportedUserException;
use Symfony\Component\Security\Core\Exception\UserNotFoundException;
use Symfony\Component\Security\Core\User\UserInterface;
use Symfony\Component\Security\Core\User\UserProviderInterface;

/** @implements UserProviderInterface<SecurityUser> */
final readonly class SecurityUserProvider implements UserProviderInterface
{
    public function __construct(
        private UserRepositoryInterface $users,
    ) {
    }

    public function loadUserByIdentifier(string $identifier): UserInterface
    {
        // json_login sends the email; tokens/sessions carry the ID
        $user = str_contains($identifier, '@')
            ? $this->users->findByEmail(new Email($identifier))
            : $this->users->findById(new UserId($identifier));

        if ($user === null) {
            throw new UserNotFoundException();
        }

        return SecurityUser::fromDomain($user);
    }

    public function refreshUser(UserInterface $user): UserInterface
    {
        if (!$user instanceof SecurityUser) {
            throw new UnsupportedUserException($user::class);
        }

        return $this->loadUserByIdentifier($user->getUserIdentifier());
    }

    public function supportsClass(string $class): bool
    {
        return $class === SecurityUser::class;
    }
}
```

`json_login` uses the email as identifier while the session/token uses the ID returned by `getUserIdentifier()`; the provider accepts both.

## Checking Roles in Code

### In Controllers (prefer `#[IsGranted]`)
```php
#[IsGranted('ROLE_USER_CREATE')]
public function create(): JsonResponse { ... }
```

### In Services (via Security component)
```php
use Symfony\Bundle\SecurityBundle\Security; // Symfony 6.2+
use Symfony\Component\Security\Core\Exception\AccessDeniedException;

// Infrastructure / Presentation only. Application code receives the needed facts
// (e.g. the current user ID) through the command, not through Security.
final readonly class SomeService
{
    public function __construct(
        private Security $security,
    ) {
    }

    public function doSomething(): void
    {
        if (!$this->security->isGranted('ROLE_ADMIN')) {
            throw new AccessDeniedException();
        }
    }
}
```

### Resource-based checks
```php
#[IsGranted('ORDER_EDIT', subject: 'id')]
```

## Multi-Tenant Roles

For SaaS applications with organization-scoped roles, load memberships through a read port:

```php
/** @extends Voter<string, string> */
final class OrganizationVoter extends Voter
{
    public function __construct(
        private readonly MembershipReadRepositoryInterface $memberships,
    ) {
    }

    protected function supports(string $attribute, mixed $subject): bool
    {
        return str_starts_with($attribute, 'ORG_') && is_string($subject); // subject = organization ID
    }

    protected function voteOnAttribute(string $attribute, mixed $subject, TokenInterface $token, ?Vote $vote = null): bool
    {
        return $this->memberships->hasRole($token->getUserIdentifier(), $subject, $attribute);
    }
}
```
