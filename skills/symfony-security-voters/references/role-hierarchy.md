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

```yaml
security:
    password_hashers:
        Symfony\Component\Security\Core\User\PasswordAuthenticatedUserInterface: 'auto'

    providers:
        app_user_provider:
            entity:
                class: App\Infrastructure\User\Persistence\SecurityUser
                property: email

    firewalls:
        dev:
            pattern: ^/(_(profiler|wdt)|css|images|js)/
            security: false

        api:
            pattern: ^/api
            stateless: true
            json_login:
                check_path: /api/login
            jwt: ~
            # Or API token:
            # custom_authenticator:
            #     - App\Infrastructure\Shared\Security\ApiTokenAuthenticator

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

## Checking Roles in Code

### In Controllers (prefer `#[IsGranted]`)
```php
#[IsGranted('ROLE_USER_CREATE')]
public function create(): JsonResponse { ... }
```

### In Services (via Security component)
```php
use Symfony\Bundle\SecurityBundle\Security;

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

### In Voters (for resource-based checks)
```php
$this->denyAccessUnlessGranted('EDIT', $order);
```

## Multi-Tenant Roles

For SaaS applications with organization-scoped roles:

```php
// Custom voter that checks organization membership
final class OrganizationVoter extends Voter
{
    protected function voteOnAttribute(string $attribute, mixed $subject, TokenInterface $token): bool
    {
        $user = $token->getUser();
        $organization = $subject;

        // Check if user belongs to this organization with the required role
        return $user->hasOrganizationRole($organization->id(), $attribute);
    }
}
```
