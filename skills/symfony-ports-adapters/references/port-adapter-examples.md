# Port & Adapter Examples

## Repository Port + Doctrine Adapter

### Port
```php
namespace App\Domain\User\Port;

use App\Domain\User\Entity\User;
use App\Domain\User\ValueObject\Email;
use App\Domain\User\ValueObject\UserId;

interface UserRepositoryInterface
{
    public function save(User $user): void;
    public function findById(UserId $id): ?User;
    public function findByEmail(Email $email): ?User;
    public function existsByEmail(Email $email): bool;
    public function remove(User $user): void;
}
```

### Adapter
```php
namespace App\Infrastructure\User\Persistence;

use App\Domain\User\Entity\User;
use App\Domain\User\Port\UserRepositoryInterface;
use App\Domain\User\ValueObject\Email;
use App\Domain\User\ValueObject\UserId;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Component\Messenger\MessageBusInterface;

final readonly class DoctrineUserRepository implements UserRepositoryInterface
{
    public function __construct(
        private EntityManagerInterface $entityManager,
        private MessageBusInterface $eventBus,
    ) {
    }

    public function save(User $user): void
    {
        $this->entityManager->persist($user);
        $this->entityManager->flush();

        foreach ($user->pullDomainEvents() as $event) {
            $this->eventBus->dispatch($event);
        }
    }

    public function findById(UserId $id): ?User
    {
        return $this->entityManager->find(User::class, $id->value);
    }

    public function findByEmail(Email $email): ?User
    {
        return $this->entityManager
            ->getRepository(User::class)
            ->findOneBy(['email.value' => $email->value]);
    }

    public function existsByEmail(Email $email): bool
    {
        return $this->findByEmail($email) !== null;
    }

    public function remove(User $user): void
    {
        $this->entityManager->remove($user);
        $this->entityManager->flush();
    }
}
```

## Payment Gateway Port + Stripe Adapter

### Port
```php
namespace App\Domain\Payment\Port;

use App\Domain\Shared\ValueObject\Money;

interface PaymentGatewayInterface
{
    public function charge(string $customerId, Money $amount, string $description): PaymentResult;
    public function refund(string $paymentId, ?Money $amount = null): RefundResult;
    public function createCustomer(string $email, string $name): string;
}
```

### Adapter
```php
namespace App\Infrastructure\Payment\ExternalService;

use App\Domain\Payment\Port\PaymentGatewayInterface;
use App\Domain\Payment\Port\PaymentResult;
use App\Domain\Payment\Port\RefundResult;
use App\Domain\Shared\ValueObject\Money;
use Stripe\StripeClient;

final readonly class StripePaymentGateway implements PaymentGatewayInterface
{
    public function __construct(
        private StripeClient $stripe,
    ) {
    }

    public function charge(string $customerId, Money $amount, string $description): PaymentResult
    {
        $charge = $this->stripe->paymentIntents->create([
            'amount' => $amount->amount,
            'currency' => strtolower($amount->currency),
            'customer' => $customerId,
            'description' => $description,
        ]);

        return new PaymentResult(
            id: $charge->id,
            status: $charge->status,
            success: $charge->status === 'succeeded',
        );
    }

    public function refund(string $paymentId, ?Money $amount = null): RefundResult
    {
        $params = ['payment_intent' => $paymentId];
        if ($amount !== null) {
            $params['amount'] = $amount->amount;
        }

        $refund = $this->stripe->refunds->create($params);

        return new RefundResult(
            id: $refund->id,
            status: $refund->status,
        );
    }

    public function createCustomer(string $email, string $name): string
    {
        $customer = $this->stripe->customers->create([
            'email' => $email,
            'name' => $name,
        ]);

        return $customer->id;
    }
}
```

## Notification Port + Mailer Adapter

### Port
```php
namespace App\Domain\Notification\Port;

interface NotificationServiceInterface
{
    public function sendWelcomeEmail(string $userId, string $email): void;
    public function sendOrderConfirmation(string $orderId, string $email): void;
    public function sendPasswordReset(string $email, string $token): void;
}
```

### Adapter
```php
namespace App\Infrastructure\Notification\ExternalService;

use App\Domain\Notification\Port\NotificationServiceInterface;
use Symfony\Component\Mailer\MailerInterface;
use Symfony\Component\Mime\Email;

final readonly class SymfonyMailerAdapter implements NotificationServiceInterface
{
    public function __construct(
        private MailerInterface $mailer,
        private string $fromEmail,
    ) {
    }

    public function sendWelcomeEmail(string $userId, string $email): void
    {
        $message = (new Email())
            ->from($this->fromEmail)
            ->to($email)
            ->subject('Welcome!')
            ->text(sprintf('Welcome, user %s!', $userId));

        $this->mailer->send($message);
    }

    // ... other methods
}
```

## File Storage Port + S3 Adapter

### Port
```php
namespace App\Domain\Document\Port;

interface FileStorageInterface
{
    public function upload(string $path, string $content, string $mimeType): string;
    public function download(string $path): string;
    public function delete(string $path): void;
    public function exists(string $path): bool;
    public function getUrl(string $path): string;
}
```

### Adapter
```php
namespace App\Infrastructure\Document\ExternalService;

use App\Domain\Document\Port\FileStorageInterface;
use Aws\S3\S3Client;

final readonly class S3FileStorage implements FileStorageInterface
{
    public function __construct(
        private S3Client $s3Client,
        private string $bucket,
    ) {
    }

    public function upload(string $path, string $content, string $mimeType): string
    {
        $this->s3Client->putObject([
            'Bucket' => $this->bucket,
            'Key' => $path,
            'Body' => $content,
            'ContentType' => $mimeType,
        ]);

        return $path;
    }

    // ... other methods
}
```

## Testing with In-Memory Adapters

Create test adapters for unit testing without infrastructure:

```php
namespace Tests\Support\Adapter;

use App\Domain\User\Entity\User;
use App\Domain\User\Port\UserRepositoryInterface;
use App\Domain\User\ValueObject\Email;
use App\Domain\User\ValueObject\UserId;

final class InMemoryUserRepository implements UserRepositoryInterface
{
    /** @var array<string, User> */
    private array $users = [];

    public function save(User $user): void
    {
        $this->users[(string) $user->id()] = $user;
    }

    public function findById(UserId $id): ?User
    {
        return $this->users[$id->value] ?? null;
    }

    public function findByEmail(Email $email): ?User
    {
        foreach ($this->users as $user) {
            if ($user->email()->equals($email)) {
                return $user;
            }
        }
        return null;
    }

    public function existsByEmail(Email $email): bool
    {
        return $this->findByEmail($email) !== null;
    }

    public function remove(User $user): void
    {
        unset($this->users[(string) $user->id()]);
    }
}
```
