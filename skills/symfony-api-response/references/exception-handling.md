# Exception Handling

## ApiExceptionSubscriber

Converts every exception under `/api` into the standard JSON payload. Three details matter:

1. **Unwrap Messenger**: exceptions thrown inside sync handlers arrive wrapped in `HandlerFailedException`. Without unwrapping, every domain error becomes a 500.
2. **`#[MapRequestPayload]` failures** arrive as an `HttpException` (422) whose previous exception is a `ValidationFailedException`: read the violations from there.
3. **Never leak internals**: 5xx responses get a generic message unless `kernel.debug` is true.

```php
namespace App\Presentation\Shared\EventSubscriber;

use App\Domain\User\Exception\UserAlreadyExistsException;
use App\Domain\User\Exception\UserNotFoundException;
use Symfony\Component\DependencyInjection\Attribute\Autowire;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpKernel\Event\ExceptionEvent;
use Symfony\Component\HttpKernel\Exception\HttpExceptionInterface;
use Symfony\Component\HttpKernel\KernelEvents;
use Symfony\Component\Messenger\Exception\HandlerFailedException;
use Symfony\Component\Messenger\Exception\ValidationFailedException as MessengerValidationFailedException;
use Symfony\Component\Security\Core\Exception\AccessDeniedException;
use Symfony\Component\Security\Core\Exception\AuthenticationException;
use Symfony\Component\Validator\ConstraintViolationListInterface;
use Symfony\Component\Validator\Exception\ValidationFailedException;

final readonly class ApiExceptionSubscriber implements EventSubscriberInterface
{
    /** Domain exception class => [HTTP status, error code] */
    private const DOMAIN_MAP = [
        UserNotFoundException::class => [404, 'USER_NOT_FOUND'],
        UserAlreadyExistsException::class => [409, 'USER_ALREADY_EXISTS'],
    ];

    public function __construct(
        #[Autowire('%kernel.debug%')]
        private bool $debug,
    ) {
    }

    public static function getSubscribedEvents(): array
    {
        // Priority above the security ExceptionListener (1) would hide 401 handling: stay at 0
        return [KernelEvents::EXCEPTION => ['onException', 0]];
    }

    public function onException(ExceptionEvent $event): void
    {
        if (!str_starts_with($event->getRequest()->getPathInfo(), '/api')) {
            return; // HTML pages keep Symfony's error rendering
        }

        $exception = $this->unwrap($event->getThrowable());
        [$status, $code] = $this->resolve($exception);

        $error = [
            'code' => $code,
            'message' => $status >= 500 && !$this->debug ? 'Internal server error' : $exception->getMessage(),
        ];

        $violations = $this->violations($exception);
        if ($violations !== null) {
            $error['message'] = 'Validation failed';
            $error['details'] = $violations;
        }

        $extra = null;
        if ($this->debug && $status >= 500) {
            $extra = ['debug' => [
                'exception' => $exception::class,
                'file' => $exception->getFile(),
                'line' => $exception->getLine(),
                'trace' => $exception->getTraceAsString(),
            ]];
        }

        $headers = $exception instanceof HttpExceptionInterface ? $exception->getHeaders() : [];

        $event->setResponse(new JsonResponse(
            ['result' => null, 'error' => $error, 'extra' => $extra, 'status' => $status],
            $status,
            $headers,
        ));
    }

    private function unwrap(\Throwable $exception): \Throwable
    {
        while ($exception instanceof HandlerFailedException && $exception->getPrevious() !== null) {
            $exception = $exception->getPrevious();
        }

        return $exception;
    }

    /** @return array{int, string} */
    private function resolve(\Throwable $e): array
    {
        foreach (self::DOMAIN_MAP as $class => $mapping) {
            if ($e instanceof $class) {
                return $mapping;
            }
        }

        return match (true) {
            $this->violations($e) !== null => [422, 'VALIDATION_ERROR'],
            $e instanceof AuthenticationException => [401, 'UNAUTHENTICATED'],
            $e instanceof AccessDeniedException => [403, 'ACCESS_DENIED'],
            $e instanceof HttpExceptionInterface => [$e->getStatusCode(), $this->httpCode($e->getStatusCode())],
            $e instanceof \DomainException => [422, 'DOMAIN_ERROR'],
            $e instanceof \InvalidArgumentException => [400, 'INVALID_ARGUMENT'],
            default => [500, 'INTERNAL_ERROR'],
        };
    }

    /** @return array<string, list<string>>|null */
    private function violations(\Throwable $e): ?array
    {
        $list = match (true) {
            $e instanceof MessengerValidationFailedException => $e->getViolations(),
            $e instanceof ValidationFailedException => $e->getViolations(),
            // #[MapRequestPayload] / #[MapQueryString]: HttpException(422) with previous ValidationFailedException
            $e->getPrevious() instanceof ValidationFailedException => $e->getPrevious()->getViolations(),
            default => null,
        };

        if (!$list instanceof ConstraintViolationListInterface) {
            return null;
        }

        $errors = [];
        foreach ($list as $violation) {
            $errors[$violation->getPropertyPath()][] = (string) $violation->getMessage();
        }

        return $errors;
    }

    private function httpCode(int $status): string
    {
        return match ($status) {
            400 => 'BAD_REQUEST',
            401 => 'UNAUTHENTICATED',
            403 => 'ACCESS_DENIED',
            404 => 'NOT_FOUND',
            405 => 'METHOD_NOT_ALLOWED',
            409 => 'CONFLICT',
            415 => 'UNSUPPORTED_MEDIA_TYPE',
            422 => 'UNPROCESSABLE_ENTITY',
            429 => 'RATE_LIMITED',
            default => $status >= 500 ? 'INTERNAL_ERROR' : 'HTTP_ERROR',
        };
    }
}
```

With `autoconfigure: true` no service definition is needed: `#[Autowire('%kernel.debug%')]` (Symfony 6.1+) injects the flag. On older setups bind `$debug: '%kernel.debug%'` in `services.yaml`.

Importing `App\Domain\*\Exception\*` here is the one allowed Presentation → Domain dependency (see `dependency-rules.md`).

## Unauthenticated Requests

The firewall's entry point produces 401 responses before controllers run. Make them follow the payload too:

```php
namespace App\Presentation\Shared\Security;

use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Security\Core\Exception\AuthenticationException;
use Symfony\Component\Security\Http\EntryPoint\AuthenticationEntryPointInterface;

final class ApiAuthenticationEntryPoint implements AuthenticationEntryPointInterface
{
    public function start(Request $request, ?AuthenticationException $authException = null): JsonResponse
    {
        return new JsonResponse([
            'result' => null,
            'error' => ['code' => 'UNAUTHENTICATED', 'message' => 'Authentication required'],
            'extra' => null,
            'status' => 401,
        ], 401);
    }
}
```

```yaml
# security.yaml
firewalls:
    api:
        entry_point: App\Presentation\Shared\Security\ApiAuthenticationEntryPoint
```

## Rate Limiting Response

```json
{
    "result": null,
    "error": {
        "code": "RATE_LIMITED",
        "message": "Too many requests"
    },
    "extra": {
        "retryAfter": 60
    },
    "status": 429
}
```
