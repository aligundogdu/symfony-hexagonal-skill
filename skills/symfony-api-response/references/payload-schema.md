# API Payload Schema

## ApiResponseTrait

```php
namespace App\Presentation\Shared;

use Symfony\Component\HttpFoundation\JsonResponse;

trait ApiResponseTrait
{
    protected function success(mixed $result = null, int $status = 200, ?array $extra = null): JsonResponse
    {
        return new JsonResponse([
            'result' => $result,
            'error' => null,
            'extra' => $extra,
            'status' => $status,
        ], $status);
    }

    protected function error(
        string $message,
        int $status = 400,
        ?string $code = null,
        ?array $details = null,
        ?array $extra = null,
    ): JsonResponse {
        $error = ['message' => $message];
        if ($code !== null) {
            $error['code'] = $code;
        }
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

    protected function paginated(array $items, int $total, int $page, int $limit): JsonResponse
    {
        return $this->success($items, 200, [
            'pagination' => [
                'total' => $total,
                'page' => $page,
                'limit' => $limit,
                'totalPages' => (int) ceil($total / $limit),
            ],
        ]);
    }

    protected function created(mixed $result = null): JsonResponse
    {
        return $this->success($result, 201);
    }

    protected function noContent(): JsonResponse
    {
        return $this->success(null, 204);
    }
}
```

## Full Controller Example

```php
namespace App\Presentation\User\API;

use App\Application\User\Command\RegisterUser;
use App\Application\User\Command\UpdateUserProfile;
use App\Application\User\Query\GetUserById;
use App\Application\User\Query\ListUsers;
use App\Presentation\Shared\ApiResponseTrait;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Messenger\MessageBusInterface;
use Symfony\Component\Messenger\Stamp\HandledStamp;
use Symfony\Component\Routing\Attribute\Route;
use Symfony\Component\Security\Http\Attribute\IsGranted;

#[Route('/api/users')]
final class UserController
{
    use ApiResponseTrait;

    public function __construct(
        private readonly MessageBusInterface $commandBus,
        private readonly MessageBusInterface $queryBus,
    ) {
    }

    #[Route('', methods: ['GET'])]
    #[IsGranted('ROLE_USER_LIST')]
    public function list(Request $request): JsonResponse
    {
        $query = new ListUsers(
            page: $request->query->getInt('page', 1),
            limit: $request->query->getInt('limit', 20),
            search: $request->query->get('search'),
        );

        $result = $this->queryBus->dispatch($query)
            ->last(HandledStamp::class)?->getResult();

        return $this->paginated(
            $result->items,
            $result->total,
            $result->page,
            $result->limit,
        );
    }

    #[Route('/{id}', methods: ['GET'])]
    #[IsGranted('ROLE_USER_VIEW')]
    public function show(string $id): JsonResponse
    {
        $result = $this->queryBus->dispatch(new GetUserById($id))
            ->last(HandledStamp::class)?->getResult();

        if ($result === null) {
            return $this->error('User not found', 404, 'USER_NOT_FOUND');
        }

        return $this->success($result);
    }

    #[Route('', methods: ['POST'])]
    #[IsGranted('ROLE_USER_CREATE')]
    public function create(Request $request): JsonResponse
    {
        $data = json_decode($request->getContent(), true, 512, JSON_THROW_ON_ERROR);

        $command = new RegisterUser(
            email: $data['email'],
            name: $data['name'],
            password: $data['password'],
        );

        $userId = $this->commandBus->dispatch($command)
            ->last(HandledStamp::class)?->getResult();

        return $this->created(['id' => $userId]);
    }

    #[Route('/{id}', methods: ['PUT'])]
    #[IsGranted('ROLE_USER_EDIT')]
    public function update(string $id, Request $request): JsonResponse
    {
        $data = json_decode($request->getContent(), true, 512, JSON_THROW_ON_ERROR);

        $command = new UpdateUserProfile(
            userId: $id,
            name: $data['name'] ?? null,
            bio: $data['bio'] ?? null,
        );

        $this->commandBus->dispatch($command);

        return $this->noContent();
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
