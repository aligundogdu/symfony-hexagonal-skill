# Symfony Scheduler Patterns

## Why Scheduler (Not Cron)

- Part of the application: version-controlled, testable
- Uses Messenger infrastructure (retry, failure transport, monitoring)
- No server-level crontab to keep in sync
- Scheduled work is just a regular CQRS command

Requires `symfony/scheduler` (Symfony 6.3+; attributes since 6.4).

## Basic Scheduler Setup

### 1. Create a Schedule Provider

```php
namespace App\Infrastructure\Shared\Scheduler;

use App\Application\Cleanup\Command\PurgeExpiredSessions;
use App\Application\Report\Command\GenerateDailyReport;
use App\Application\Webhook\Command\ProcessPendingWebhooks;
use Symfony\Component\Lock\LockFactory;
use Symfony\Component\Scheduler\Attribute\AsSchedule;
use Symfony\Component\Scheduler\RecurringMessage;
use Symfony\Component\Scheduler\Schedule;
use Symfony\Component\Scheduler\ScheduleProviderInterface;
use Symfony\Contracts\Cache\CacheInterface;

#[AsSchedule('default')]
final class AppScheduleProvider implements ScheduleProviderInterface
{
    private ?Schedule $schedule = null;

    public function __construct(
        private readonly CacheInterface $cache,
        private readonly LockFactory $lockFactory,
    ) {
    }

    public function getSchedule(): Schedule
    {
        return $this->schedule ??= (new Schedule())
            ->with(
                // Every hour: purge expired sessions
                RecurringMessage::every('1 hour', new PurgeExpiredSessions()),
                // Daily at 6 AM (server timezone unless given): generate report
                RecurringMessage::cron('0 6 * * *', new GenerateDailyReport(), new \DateTimeZone('Europe/Istanbul')),
                // Every 5 minutes: process pending webhooks
                RecurringMessage::every('5 minutes', new ProcessPendingWebhooks()),
            )
            // Remember the last run across restarts, so deploys do not skip or repeat runs
            ->stateful($this->cache)
            // Only one scheduler worker triggers a message when several are running
            ->lock($this->lockFactory->createLock('schedule_default'));
    }
}
```

`(new Schedule())->...` works on every PHP version; `new Schedule()->...` needs PHP 8.4. `RecurringMessage::cron()` needs `dragonmantank/cron-expression`.

### 2. Transport

Nothing to configure: each `#[AsSchedule('name')]` automatically gets a `scheduler_name` transport. Do not declare `scheduler://` DSNs by hand.

### 3. Run the Worker

```bash
php bin/console messenger:consume scheduler_default
php bin/console debug:scheduler   # list schedules and next run dates
```

Scheduled messages are dispatched on the **default bus** (`default_bus: command.bus`), so validation and `doctrine_transaction` middleware apply. Route heavy commands to `async` as usual to keep the scheduler worker responsive:

```yaml
framework:
    messenger:
        routing:
            'App\Application\Report\Command\GenerateDailyReport': async
```

## Scheduled Tasks as Commands

Scheduled tasks are regular commands; they follow the same CQRS pattern:

```php
namespace App\Application\Cleanup\Command;

final readonly class PurgeExpiredSessions
{
    public function __construct(
        public int $maxAgeDays = 30,
    ) {
    }
}

#[AsMessageHandler(bus: 'command.bus')]
final readonly class PurgeExpiredSessionsHandler
{
    public function __construct(
        private SessionRepositoryInterface $sessionRepository,
    ) {
    }

    public function __invoke(PurgeExpiredSessions $command): void
    {
        $cutoff = new \DateTimeImmutable(sprintf('-%d days', $command->maxAgeDays));
        $this->sessionRepository->deleteExpiredBefore($cutoff); // DQL DELETE, no native SQL
    }
}
```

## Attribute Shortcut (Symfony 6.4+)

`#[AsCronTask]` / `#[AsPeriodicTask]` schedule a **service method call**, bypassing the command bus and its middleware. Use them only for Infrastructure housekeeping that is not a use case; business work stays a command in a `ScheduleProviderInterface`.

```php
namespace App\Infrastructure\Shared\Maintenance;

use Symfony\Component\Scheduler\Attribute\AsCronTask;

#[AsCronTask('0 3 * * *', jitter: 60, schedule: 'maintenance')]
final readonly class ClearTemporaryUploads
{
    public function __invoke(): void
    {
        // filesystem cleanup
    }
}
```

## Schedule Frequency Options

```php
// Fixed intervals
RecurringMessage::every('30 seconds', $message);
RecurringMessage::every('5 minutes', $message);
RecurringMessage::every('1 day', $message, from: '04:00'); // aligned start

// Cron expressions
RecurringMessage::cron('*/5 * * * *', $message);     // Every 5 minutes
RecurringMessage::cron('0 * * * *', $message);       // Every hour
RecurringMessage::cron('0 6 * * *', $message);       // Daily at 6 AM
RecurringMessage::cron('0 0 * * 1', $message);       // Weekly on Monday
RecurringMessage::cron('0 0 1 * *', $message);       // Monthly
RecurringMessage::cron('#midnight', $message);       // Hashed: spreads load across apps
```

## Multiple Schedules

```php
#[AsSchedule('maintenance')]
final class MaintenanceScheduleProvider implements ScheduleProviderInterface
{
    public function getSchedule(): Schedule
    {
        return (new Schedule())->with(
            RecurringMessage::cron('0 2 * * *', new ArchiveOldOrders()),
            RecurringMessage::cron('0 3 * * 0', new RotateAuditLog()),
        );
    }
}

#[AsSchedule('reports')]
final class ReportsScheduleProvider implements ScheduleProviderInterface
{
    public function getSchedule(): Schedule
    {
        return (new Schedule())->with(
            RecurringMessage::cron('0 6 * * *', new GenerateDailyReport()),
            RecurringMessage::cron('0 7 * * 1', new GenerateWeeklyReport()),
        );
    }
}
```

```bash
# Transports scheduler_maintenance / scheduler_reports exist automatically
php bin/console messenger:consume scheduler_maintenance scheduler_reports
```

Symfony 8.1+: `php bin/console messenger:consume 'scheduler_.*'` consumes every schedule with one regex.

## Supervisor Configuration

```ini
[program:scheduler]
command=php /var/www/app/bin/console messenger:consume scheduler_default scheduler_maintenance scheduler_reports --time-limit=3600
numprocs=1
autostart=true
autorestart=true
```

Running more than one scheduler process is safe only with `->lock(...)` (and `->stateful(...)` to survive restarts).

## Testing Schedules

```php
public function test_daily_report_is_scheduled(): void
{
    $provider = new ReportsScheduleProvider();
    $messages = $provider->getSchedule()->getRecurringMessages();

    self::assertCount(2, $messages);
}
```
