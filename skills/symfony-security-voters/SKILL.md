---
name: symfony-security-voters
description: "Symfony security in hexagonal architecture: #[IsGranted] on every endpoint, role hierarchy, resource voters with subject loading, voter vote reasons (7.3+), security user adapter, user provider, JSON 401/403. Works on Symfony 6.4, 7.x, 8.x. Use when: security, voter, role, authorization, access control, permission, IsGranted, role hierarchy, RBAC, firewall, authentication"
---

# Symfony Security & Voters

You are an expert in Symfony security with Voters pattern within hexagonal architecture.

## When to Activate

- User needs authorization on endpoints
- User asks about voters or role hierarchy
- User wants access control logic
- User mentions RBAC, permissions, or security

## Version Notes

| Feature | Requires | Fallback |
|---|---|---|
| `#[IsGranted('ATTR', subject: 'argName')]` | Symfony 6.2 | `AuthorizationCheckerInterface::isGranted()` |
| `?Vote $vote = null` 4th voter parameter (reasons in profiler / logs) | Symfony 7.3 (part of the signature in 8.0) | Declare it anyway: harmless before 7.3 |
| `#[IsGranted]` `methods:` option, `#[CurrentUser]` union types | Symfony 7.4 | separate routes / single user class |
| `#[IsGranted]` with a static closure | Symfony 7.3 + PHP 8.5 | Voter |
| `subject: new Expression('...')` | Symfony 6.2 | string argument name |
| `UserInterface::eraseCredentials()` | deprecated 7.3 | do not keep plain passwords on the user |

## Core Rule: Every Endpoint Has a ROLE

**No endpoint is publicly accessible without explicit `#[IsGranted]` or Voter check.** Public endpoints use `#[IsGranted('PUBLIC_ACCESS')]` so the decision is visible.

```php
#[Route('/api/users', methods: ['GET'])]
#[IsGranted('ROLE_USER_LIST')]  // ALWAYS required
public function list(): JsonResponse { /* ... */ }
```

## Role Hierarchy

Define roles in `security.yaml`:

```yaml
security:
    role_hierarchy:
        ROLE_ADMIN: [ROLE_USER_CREATE, ROLE_USER_EDIT, ROLE_USER_DELETE, ROLE_USER_LIST, ROLE_USER_VIEW]
        ROLE_MANAGER: [ROLE_USER_LIST, ROLE_USER_VIEW, ROLE_ORDER_MANAGE]
        ROLE_USER: [ROLE_USER_VIEW]
```

### Naming Convention
- Module-scoped: `ROLE_{MODULE}_{ACTION}`
- Examples: `ROLE_USER_CREATE`, `ROLE_ORDER_VIEW`, `ROLE_REPORT_GENERATE`
- Voter attributes (resource permissions) have no `ROLE_` prefix: `ORDER_EDIT`

## Simple Cases: Use `#[IsGranted]`

```php
#[IsGranted('ROLE_USER_CREATE')]
public function create(): JsonResponse { /* ... */ }
```

## Complex Cases: Use Voters

When authorization depends on the resource ("can this user edit THIS order?"). Controllers only know the ID, so the voter receives the ID and loads what it needs through a **read port**: Presentation never touches Domain entities.

```php
namespace App\Infrastructure\{Module}\Security;

use App\Domain\{Module}\Port\{Entity}ReadRepositoryInterface;
use Symfony\Component\Security\Core\Authentication\Token\TokenInterface;
use Symfony\Component\Security\Core\Authorization\Voter\Vote;
use Symfony\Component\Security\Core\Authorization\Voter\Voter;

/** @extends Voter<string, string> */
final class {Entity}Voter extends Voter
{
    public const VIEW = '{MODULE}_VIEW';
    public const EDIT = '{MODULE}_EDIT';

    public function __construct(
        private readonly {Entity}ReadRepositoryInterface $repository,
    ) {
    }

    protected function supports(string $attribute, mixed $subject): bool
    {
        return in_array($attribute, [self::VIEW, self::EDIT], true) && is_string($subject);
    }

    protected function voteOnAttribute(string $attribute, mixed $subject, TokenInterface $token, ?Vote $vote = null): bool
    {
        $view = $this->repository->findById($subject);
        if ($view === null) {
            $vote?->addReason('Resource not found');

            return false;
        }

        return match ($attribute) {
            self::VIEW, self::EDIT => $view->ownerId === $token->getUserIdentifier(),
            default => false,
        };
    }
}
```

### Using the Voter in a Controller
```php
#[Route('/{id}', methods: ['PUT'])]
#[IsGranted('{MODULE}_EDIT', subject: 'id')] // 'id' = controller argument name
public function update(string $id, #[MapRequestPayload] Update{Entity}Request $request): JsonResponse
{
    $this->commandBus->dispatch(new Update{Entity}($id /* , ... */));

    return $this->success(null);
}
```

Use the attribute string (`'ORDER_EDIT'`) in Presentation instead of importing the voter class from Infrastructure.

## References

See `references/` for detailed guides:
- `voter-patterns.md` - Full voter examples and testing
- `role-hierarchy.md` - Role hierarchy design, security.yaml, security user adapter
