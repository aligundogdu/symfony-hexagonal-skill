# API Payload Schema

## ApiResponseTrait

```php
namespace App\Presentation\Shared;

use Symfony\Component\HttpFoundation\JsonResponse;

trait ApiResponseTrait
{
    /**
     * @param array<string, mixed>|null $extra
     */
    protected function success(mixed $result = null, int $status = 200, ?array $extra = null): JsonResponse
    {
        return new JsonResponse([
            'result' => $result,
            'error' => null,
            'extra' => $extra,
            'status' => $status,
        ], $status);
    }

    /**
     * @param array<string, list<string>>|null $details
     * @param array<string, mixed>|null        $extra
     */
    protected function error(
        string $message,
        int $status = 400,
        string $code = 'ERROR',
        ?array $details = null,
        ?array $extra = null,
    ): JsonResponse {
        $error = ['code' => $code, 'message' => $message];
        if ($details !== null) {
            $error['details'] = $details;
        }

        return new JsonResponse([
            'result' => null,
            'error' => $error,
            'extra' => $extra,
            'status' => $status,
        ], $status);
    }

    /**
     * @param list<mixed> $items
     */
    protected function paginated(array $items, int $total, int $page, int $limit): JsonResponse
    {
        return $this->success($items, 200, [
            'pagination' => [
                'total' => $total,
                'page' => $page,
                'limit' => $limit,
                'totalPages' => $limit > 0 ? (int) ceil($total / $limit) : 0,
            ],
        ]);
    }

    protected function created(mixed $result = null): JsonResponse
    {
        return $this->success($result, 201);
    }

    protected function accepted(mixed $result = null): JsonResponse
    {
        return $this->success($result, 202);
    }
}
```

`JsonResponse` serializes public properties of DTOs via `json_encode`. If DTOs contain `DateTimeImmutable` or need custom names, inject `SerializerInterface` and build the payload with `$serializer->normalize($result)` instead.

## Request DTOs (Presentation)

```php
namespace App\Presentation\User\API\Request;

use Symfony\Component\Validator\Constraints as Assert;

final readonly class RegisterUserRequest
{
    public function __construct(
        #[Assert\NotBlank]
        #[Assert\Email]
        public string $email = '',

        #[Assert\NotBlank]
        #[Assert\Length(min: 2, max: 100)]
        public string $name = '',

        #[Assert\NotBlank]
        #[Assert\Length(min: 8)]
        #[Assert\NotCompromisedPassword]
        public string $password = '',
    ) {
    }
}
```

Defaults let missing fields reach the validator as `''` (clear `NotBlank` violations) instead of a type error.

## Full Controller Example

```php
namespace App\Presentation\User\API;

use App\Application\User\Command\RegisterUser;
use App\Application\User\Command\UpdateUserProfile;
use App\Application\User\Query\GetUserById;
use App\Application\User\Query\ListUsers;
use App\Domain\Shared\ReadModel\Page;
use App\Presentation\Shared\ApiResponseTrait;
use App\Presentation\Shared\Bus\CommandBus;
use App\Presentation\Shared\Bus\QueryBus;
use App\Presentation\User\API\Request\ListUsersRequest;
use App\Presentation\User\API\Request\RegisterUserRequest;
use App\Presentation\User\API\Request\UpdateUserProfileRequest;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpKernel\Attribute\MapQueryString;
use Symfony\Component\HttpKernel\Attribute\MapRequestPayload;
use Symfony\Component\Routing\Attribute\Route;
use Symfony\Component\Security\Http\Attribute\IsGranted;

#[Route('/api/users')]
final class UserController
{
    use ApiResponseTrait;

    public function __construct(
        private readonly CommandBus $commandBus,
        private readonly QueryBus $queryBus,
    ) {
    }

    #[Route('', methods: ['GET'])]
    #[IsGranted('ROLE_USER_LIST')]
    public function list(
        #[MapQueryString(validationFailedStatusCode: 422)] ListUsersRequest $request = new ListUsersRequest(),
    ): JsonResponse {
        /** @var Page<mixed> $page */
        $page = $this->queryBus->ask(new ListUsers($request->page, $request->limit, $request->status, $request->search));

        return $this->paginated($page->items, $page->total, $page->page, $page->limit);
    }

    #[Route('/{id}', methods: ['GET'], requirements: ['id' => '[0-9a-f-]{36}'])]
    #[IsGranted('ROLE_USER_VIEW')]
    public function show(string $id): JsonResponse
    {
        $user = $this->queryBus->ask(new GetUserById($id));

        if ($user === null) {
            return $this->error('User not found', 404, 'USER_NOT_FOUND');
        }

        return $this->success($user);
    }

    #[Route('', methods: ['POST'])]
    #[IsGranted('ROLE_USER_CREATE')]
    public function create(#[MapRequestPayload] RegisterUserRequest $request): JsonResponse
    {
        $userId = $this->commandBus->dispatch(
            new RegisterUser($request->email, $request->name, $request->password),
        );

        return $this->created(['id' => $userId]);
    }

    #[Route('/{id}', methods: ['PUT'], requirements: ['id' => '[0-9a-f-]{36}'])]
    #[IsGranted('ROLE_USER_EDIT')]
    public function update(string $id, #[MapRequestPayload] UpdateUserProfileRequest $request): JsonResponse
    {
        $this->commandBus->dispatch(new UpdateUserProfile($id, $request->name, $request->bio));

        return $this->success(null);
    }
}
```

## Validation Error Format

```json
{
    "result": null,
    "error": {
        "code": "VALIDATION_ERROR",
        "message": "Validation failed",
        "details": {
            "email": ["This value is not a valid email address."],
            "name": ["This value should not be blank."]
        }
    },
    "extra": null,
    "status": 422
}
```
