---
name: symfony-api-response
description: "Symfony REST API response standard {result, error, extra, status}: thin controllers, #[MapRequestPayload] / #[MapQueryString] request DTOs, ApiResponseTrait, exception subscriber that unwraps Messenger HandlerFailedException, validation error format, debug mode. Use when: API, endpoint, controller, response, error handling, JSON, REST, API response, exception subscriber, HTTP, request DTO"
---

# Symfony API Response Standard

You are an expert in building standardized REST APIs within Symfony hexagonal architecture.

## When to Activate

- User creates API endpoints or controllers
- User asks about response format or error handling
- User needs exception handling for APIs
- User mentions REST, JSON, or API design

## Version Notes

| Feature | Requires | Fallback |
|---|---|---|
| `#[MapRequestPayload]`, `#[MapQueryString]` | Symfony 6.3 | `json_decode` + `ValidatorInterface` (see validation skill) |
| `Symfony\Component\Routing\Attribute\Route` | Symfony 6.2 | `Routing\Annotation\Route` |
| `#[MapUploadedFile]` | Symfony 7.1 | `$request->files->get()` |
| `#[MapRequestHeader]`, variadic `#[MapRequestPayload] Dto ...$items` | Symfony 8.1 | `$request->headers->get()`, `type: Dto::class` array |

Never call `$request->get()` (removed in Symfony 8).

## Standard JSON Payload

ALL API responses use this format:

```json
{
    "result": null,
    "error": null,
    "extra": null,
    "status": 200
}
```

| Field | Type | Description |
|-------|------|-------------|
| `result` | `mixed` | Success data (null on error) |
| `error` | `?object` | Error details `{code, message, details?}` (null on success) |
| `extra` | `?object` | Metadata: pagination, debug info |
| `status` | `int` | HTTP status code (same as the response status) |

### Success Response
```json
{
    "result": {"id": "0199a3c2-...", "name": "John"},
    "error": null,
    "extra": null,
    "status": 200
}
```

### Error Response
```json
{
    "result": null,
    "error": {"code": "USER_NOT_FOUND", "message": "User not found"},
    "extra": null,
    "status": 404
}
```

### Debug Mode (APP_DEBUG=true)
```json
{
    "result": null,
    "error": {"code": "INTERNAL_ERROR", "message": "Something went wrong"},
    "extra": {"debug": {"exception": "...", "file": "...", "line": 42, "trace": "..."}},
    "status": 500
}
```

In production, 5xx messages are generic: never leak exception messages or traces.

Because every response carries a body, there is no `204 No Content` in this API: successful writes without data return `200` with `"result": null` (or `202` for async commands).

## Controller Pattern

Controllers are thin: map input, dispatch, format output.

```php
namespace App\Presentation\{Module}\API;

use App\Presentation\Shared\ApiResponseTrait;
use App\Presentation\Shared\Bus\CommandBus;
use App\Presentation\Shared\Bus\QueryBus;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpKernel\Attribute\MapRequestPayload;
use Symfony\Component\Routing\Attribute\Route;
use Symfony\Component\Security\Http\Attribute\IsGranted;

#[Route('/api/{module}')]
final class {Entity}Controller
{
    use ApiResponseTrait;

    public function __construct(
        private readonly CommandBus $commandBus,
        private readonly QueryBus $queryBus,
    ) {
    }

    #[Route('', methods: ['POST'])]
    #[IsGranted('ROLE_{MODULE}_CREATE')] // ALWAYS include
    public function create(#[MapRequestPayload] Create{Entity}Request $request): JsonResponse
    {
        $id = $this->commandBus->dispatch(new Create{Entity}(/* from $request */));

        return $this->created(['id' => $id]);
    }
}
```

## References

See `references/` for detailed guides:
- `payload-schema.md` - ApiResponseTrait, request DTOs, full controller example
- `exception-handling.md` - ApiExceptionSubscriber, domain error mapping, validation errors
