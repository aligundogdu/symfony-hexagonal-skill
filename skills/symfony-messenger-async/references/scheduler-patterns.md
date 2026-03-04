# Symfony Scheduler Patterns

## Why Scheduler (Not Cron)

- Part of the application — version-controlled, testable
- Uses Messenger infrastructure (retry, monitoring)
- No server-level cron configuration needed
- Can be scaled with workers

## Basic Scheduler Setup

### 1. Create a Schedule Provider

```php
namespace App\Infrastructure\Shared\Scheduler;

use App\Application\Cleanup\Command\PurgeExpiredSessions;
use App\Application\Report\Command\GenerateDailyReport;
use Symfony\Component\Scheduler\Attribute\AsSchedule;
use Symfony\Component\Scheduler\RecurringMessage;
use Symfony\Component\Scheduler\Schedule;
use Symfony\Component\Scheduler\ScheduleProviderInterface;

#[AsSchedule('default')]
final class AppScheduleProvider implements ScheduleProviderInterface
{
    public function getSchedule(): Schedule
    {
        $schedule = new Schedule();

        // Every hour: purge expired sessions
        $schedule->add(
            RecurringMessage::every('1 hour', new PurgeExpiredSessions())
        );

        // Daily at 6 AM: generate report
        $schedule->add(
            RecurringMessage::cron('0 6 * * *', new GenerateDailyReport())
        );

        // Every 5 minutes: process pending webhooks
        $schedule->add(
            RecurringMessage::every('5 minutes', new ProcessPendingWebhooks())
        );

        return $schedule;
    }
}
```

### 2. Configure Transport

```yaml
# config/packages/messenger.yaml
framework:
    messenger:
        transports:
            scheduler_default:
                dsn: 'scheduler://default'
```

### 3. Run the Worker

```bash
php bin/console messenger:consume scheduler_default
```

## Scheduled Tasks as Commands

Scheduled tasks are regular commands — they follow the same CQRS pattern:

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
        $this->sessionRepository->deleteExpiredBefore($cutoff);
    }
}
```

## Schedule Frequency Options

```php
// Fixed intervals
RecurringMessage::every('30 seconds', $message);
RecurringMessage::every('5 minutes', $message);
RecurringMessage::every('1 hour', $message);
RecurringMessage::every('1 day', $message);

// Cron expressions
RecurringMessage::cron('*/5 * * * *', $message);     // Every 5 minutes
RecurringMessage::cron('0 * * * *', $message);        // Every hour
RecurringMessage::cron('0 6 * * *', $message);        // Daily at 6 AM
RecurringMessage::cron('0 0 * * 1', $message);        // Weekly on Monday
RecurringMessage::cron('0 0 1 * *', $message);        // Monthly
```

## Multiple Schedules

```php
#[AsSchedule('maintenance')]
final class MaintenanceScheduleProvider implements ScheduleProviderInterface
{
    public function getSchedule(): Schedule
    {
        $schedule = new Schedule();
        $schedule->add(RecurringMessage::cron('0 2 * * *', new DatabaseBackup()));
        $schedule->add(RecurringMessage::cron('0 3 * * 0', new LogRotation()));
        return $schedule;
    }
}

#[AsSchedule('reports')]
final class ReportsScheduleProvider implements ScheduleProviderInterface
{
    public function getSchedule(): Schedule
    {
        $schedule = new Schedule();
        $schedule->add(RecurringMessage::cron('0 6 * * *', new GenerateDailyReport()));
        $schedule->add(RecurringMessage::cron('0 7 * * 1', new GenerateWeeklyReport()));
        return $schedule;
    }
}
```

```yaml
framework:
    messenger:
        transports:
            scheduler_maintenance:
                dsn: 'scheduler://maintenance'
            scheduler_reports:
                dsn: 'scheduler://reports'
```

```bash
# Run specific schedule workers
php bin/console messenger:consume scheduler_maintenance
php bin/console messenger:consume scheduler_reports
```

## Supervisor Configuration

```ini
[program:scheduler-default]
command=php /var/www/app/bin/console messenger:consume scheduler_default --time-limit=3600
numprocs=1
autostart=true
autorestart=true

[program:scheduler-maintenance]
command=php /var/www/app/bin/console messenger:consume scheduler_maintenance --time-limit=3600
numprocs=1
autostart=true
autorestart=true
```
