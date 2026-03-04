# Exception Handling

## ExceptionSubscriber

Catches all exceptions and converts them to the standard JSON payload:

```php
namespace App\Presentation\Shared\EventSubscriber;

use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpKernel\Event\ExceptionEvent;
use Symfony\Component\HttpKernel\KernelEvents;

final readonly class ApiExceptionSubscriber implements EventSubscriberInterface
{
    public function __construct(
        private bool $debug,
    ) {
    }

    public static function getSubscribedEvents(): array
    {
        return [
            KernelEvents::EXCEPTION => ['onException', 0],
        ];
    }

    public function onException(ExceptionEvent $event): void
    {
        $exception = $event->getThrowable();
        $statusCode = $this->resolveStatusCode($exception);
        $errorCode = $this->resolveErrorCode($exception);

        $payload = [
            'result' => null,
            'error' => [
                'code' => $errorCode,
                'message' => $exception->getMessage(),
            ],
            'extra' => null,
            'status' => $statusCode,
        ];

        if ($this->debug && $statusCode >= 500) {
            $payload['extra'] = [
                'debug' => [
                    'exception' => get_class($exception),
                    'file' => $exception->getFile(),
                    'line' => $exception->getLine(),
                    'trace' => $exception->getTraceAsString(),
                ],
            ];
        }

        $event->setResponse(new JsonResponse($payload, $statusCode));
    }

    private function resolveStatusCode(\Throwable $exception): int
    {
        return match (true) {
            $exception instanceof \DomainException => 422,
            $exception instanceof \InvalidArgumentException => 400,
            $exception instanceof AccessDeniedException => 403,
            $exception instanceof NotFoundHttpException => 404,
            $exception instanceof HttpExceptionInterface => $exception->getStatusCode(),
            default => 500,
        };
    }

    private function resolveErrorCode(\Throwable $exception): string
    {
        return match (true) {
            $exception instanceof \DomainException => 'DOMAIN_ERROR',
            $exception instanceof \InvalidArgumentException => 'VALIDATION_ERROR',
            $exception instanceof AccessDeniedException => 'ACCESS_DENIED',
            $exception instanceof NotFoundHttpException => 'NOT_FOUND',
            default => 'INTERNAL_ERROR',
        };
    }
}
```

## Service Registration

```yaml
# config/services.yaml
services:
    App\Presentation\Shared\EventSubscriber\ApiExceptionSubscriber:
        arguments:
            $debug: '%kernel.debug%'
```

## Domain Exception Mapping

Map domain exceptions to specific HTTP status codes and error codes:

```php
namespace App\Presentation\Shared\EventSubscriber;

use App\Domain\User\Exception\UserNotFoundException;
use App\Domain\User\Exception\UserAlreadyExistsException;
use App\Domain\Order\Exception\OrderAlreadyCancelledException;

// In resolveStatusCode():
private function resolveStatusCode(\Throwable $exception): int
{
    return match (true) {
        $exception instanceof UserNotFoundException => 404,
        $exception instanceof UserAlreadyExistsException => 409,
        $exception instanceof OrderAlreadyCancelledException => 422,
        // ... generic fallbacks
        $exception instanceof \DomainException => 422,
        default => 500,
    };
}

// In resolveErrorCode():
private function resolveErrorCode(\Throwable $exception): string
{
    return match (true) {
        $exception instanceof UserNotFoundException => 'USER_NOT_FOUND',
        $exception instanceof UserAlreadyExistsException => 'USER_ALREADY_EXISTS',
        $exception instanceof OrderAlreadyCancelledException => 'ORDER_ALREADY_CANCELLED',
        // ... generic fallbacks
        $exception instanceof \DomainException => 'DOMAIN_ERROR',
        default => 'INTERNAL_ERROR',
    };
}
```

## Validation Exception Handling

For Symfony Validator constraint violations:

```php
use Symfony\Component\Validator\Exception\ValidationFailedException;
use Symfony\Component\Messenger\Exception\ValidationFailedException as MessengerValidationFailed;

// Add to resolveStatusCode():
$exception instanceof ValidationFailedException => 422,
$exception instanceof MessengerValidationFailed => 422,

// Custom formatting for validation errors:
private function formatValidationErrors(\Throwable $exception): ?array
{
    $violations = match (true) {
        $exception instanceof MessengerValidationFailed => $exception->getViolations(),
        $exception instanceof ValidationFailedException => $exception->getViolations(),
        default => null,
    };

    if ($violations === null) {
        return null;
    }

    $errors = [];
    foreach ($violations as $violation) {
        $field = $violation->getPropertyPath();
        $errors[$field][] = $violation->getMessage();
    }

    return $errors;
}
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
