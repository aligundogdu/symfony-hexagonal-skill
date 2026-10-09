# Voter Patterns

## Where Voters Live

Voters are Infrastructure concerns: they live in `Infrastructure/{Module}/Security/`:

```
src/Infrastructure/Order/Security/OrderVoter.php
src/Infrastructure/Document/Security/DocumentVoter.php
```

## Full Voter Example: Order

The subject is the order ID (from `#[IsGranted(..., subject: 'id')]`). The voter loads a read model through a Domain read port.

```php
namespace App\Domain\Order\ReadModel;

final readonly class OrderAccessView
{
    public function __construct(
        public string $orderId,
        public string $customerId,
        public string $status,
    ) {
    }
}
```

```php
namespace App\Infrastructure\Order\Security;

use App\Domain\Order\Port\OrderReadRepositoryInterface;
use App\Domain\Order\ReadModel\OrderAccessView;
use Symfony\Component\Security\Core\Authentication\Token\TokenInterface;
use Symfony\Component\Security\Core\Authorization\AccessDecisionManagerInterface;
use Symfony\Component\Security\Core\Authorization\Voter\Vote;
use Symfony\Component\Security\Core\Authorization\Voter\Voter;

/** @extends Voter<string, string> */
final class OrderVoter extends Voter
{
    public const VIEW = 'ORDER_VIEW';
    public const EDIT = 'ORDER_EDIT';
    public const CANCEL = 'ORDER_CANCEL';

    public function __construct(
        private readonly OrderReadRepositoryInterface $orders,
        private readonly AccessDecisionManagerInterface $accessDecisionManager,
    ) {
    }

    protected function supports(string $attribute, mixed $subject): bool
    {
        return in_array($attribute, [self::VIEW, self::EDIT, self::CANCEL], true)
            && is_string($subject);
    }

    /**
     * The 4th parameter exists since Symfony 7.3 and is part of the parent signature in 8.0.
     * Declaring it keeps the voter compatible with 6.4, 7.x and 8.x ($vote is null before 7.3).
     */
    protected function voteOnAttribute(string $attribute, mixed $subject, TokenInterface $token, ?Vote $vote = null): bool
    {
        $order = $this->orders->findAccessView($subject);
        if ($order === null) {
            $vote?->addReason(sprintf('Order %s not found', $subject));

            return false;
        }

        $isOwner = $order->customerId === $token->getUserIdentifier();

        return match ($attribute) {
            self::VIEW => $isOwner || $this->accessDecisionManager->decide($token, ['ROLE_ORDER_VIEW']),
            self::EDIT => $this->canEdit($order, $isOwner, $vote),
            self::CANCEL => $this->canCancel($order, $isOwner, $token),
            default => false,
        };
    }

    private function canEdit(OrderAccessView $order, bool $isOwner, ?Vote $vote): bool
    {
        if ($order->status !== 'pending') {
            $vote?->addReason('Only pending orders can be edited');

            return false;
        }

        return $isOwner;
    }

    private function canCancel(OrderAccessView $order, bool $isOwner, TokenInterface $token): bool
    {
        if ($isOwner && $order->status === 'pending') {
            return true;
        }

        // Admins can cancel any non-delivered order; decide() respects the role hierarchy
        return $order->status !== 'delivered'
            && $this->accessDecisionManager->decide($token, ['ROLE_ADMIN']);
    }
}
```

Use `AccessDecisionManagerInterface::decide()` (or `Security::isGranted()`) for role checks inside voters: `$user->getRoles()` ignores the role hierarchy.

## Controller Usage

```php
#[Route('/{id}', methods: ['PUT'])]
#[IsGranted('ORDER_EDIT', subject: 'id')]
public function update(string $id, #[MapRequestPayload] UpdateOrderRequest $request): JsonResponse
{
    $this->commandBus->dispatch(new UpdateOrder($id, $request->note));

    return $this->success(null);
}
```

A missing order makes the voter deny (403), which also avoids revealing which IDs exist. If the API must answer 404 instead, let the voter grant for unknown IDs (there is nothing to protect) and let the handler throw `OrderNotFoundException`, mapped to 404 by the exception subscriber.

## Testing Voters

```php
namespace Tests\Unit\Infrastructure\Order\Security;

use App\Domain\Order\Port\OrderReadRepositoryInterface;
use App\Domain\Order\ReadModel\OrderAccessView;
use App\Infrastructure\Order\Security\OrderVoter;
use PHPUnit\Framework\TestCase;
use Symfony\Component\Security\Core\Authentication\Token\UsernamePasswordToken;
use Symfony\Component\Security\Core\Authorization\AccessDecisionManagerInterface;
use Symfony\Component\Security\Core\Authorization\Voter\VoterInterface;
use Symfony\Component\Security\Core\User\InMemoryUser;

final class OrderVoterTest extends TestCase
{
    public function test_owner_can_view_their_order(): void
    {
        $voter = $this->voterFor(new OrderAccessView('order-1', 'user-123', 'pending'));

        $result = $voter->vote($this->token('user-123'), 'order-1', [OrderVoter::VIEW]);

        self::assertSame(VoterInterface::ACCESS_GRANTED, $result);
    }

    public function test_other_user_cannot_edit_order(): void
    {
        $voter = $this->voterFor(new OrderAccessView('order-1', 'user-123', 'pending'));

        $result = $voter->vote($this->token('user-456'), 'order-1', [OrderVoter::EDIT]);

        self::assertSame(VoterInterface::ACCESS_DENIED, $result);
    }

    private function voterFor(OrderAccessView $view): OrderVoter
    {
        // createStub: return values only (PHPUnit 13 emits a notice for mocks without expectations)
        $orders = $this->createStub(OrderReadRepositoryInterface::class);
        $orders->method('findAccessView')->willReturn($view);

        $adm = $this->createStub(AccessDecisionManagerInterface::class);
        $adm->method('decide')->willReturn(false);

        return new OrderVoter($orders, $adm);
    }

    private function token(string $userIdentifier): UsernamePasswordToken
    {
        $user = new InMemoryUser($userIdentifier, null, ['ROLE_USER']);

        return new UsernamePasswordToken($user, 'api', $user->getRoles());
    }
}
```

`InMemoryUser` avoids mocking `UserInterface` and works on every supported version.

## API Key / Service Authentication

For machine-to-machine APIs, combine with custom authenticators:

```php
#[Route('/api/webhooks/payment', methods: ['POST'])]
#[IsGranted('ROLE_WEBHOOK')]
public function handlePaymentWebhook(#[MapRequestPayload] PaymentWebhookRequest $request): JsonResponse
{
    // Authenticated via API key / signature authenticator
    // Authorized via ROLE_WEBHOOK
}
```
