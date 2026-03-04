# Migration Workflow

## Strategy Choice

**Always ask the user** which migration strategy they prefer before generating migrations:

### Option A: Auto-Diff (Recommended for development)
```bash
# Generate migration from mapping changes
php bin/console doctrine:migrations:diff

# Review the generated migration
# Apply migration
php bin/console doctrine:migrations:migrate
```

### Option B: Manual (Recommended for production-critical)
```bash
# Create empty migration
php bin/console doctrine:migrations:generate

# Write SQL manually for full control
```

## Migration Configuration

```yaml
# config/packages/doctrine_migrations.yaml
doctrine_migrations:
    migrations_paths:
        'DoctrineMigrations': '%kernel.project_dir%/migrations'
    enable_profiler: false
    organize_migrations: false
```

## Migration Template

```php
declare(strict_types=1);

namespace DoctrineMigrations;

use Doctrine\DBAL\Schema\Schema;
use Doctrine\Migrations\AbstractMigration;

final class Version20240101000000 extends AbstractMigration
{
    public function getDescription(): string
    {
        return 'Create users table';
    }

    public function up(Schema $schema): void
    {
        $this->addSql('CREATE TABLE users (
            id VARCHAR(36) NOT NULL,
            email VARCHAR(255) NOT NULL,
            name VARCHAR(255) NOT NULL,
            password_hash VARCHAR(255) NOT NULL,
            status VARCHAR(20) NOT NULL DEFAULT \'active\',
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NULL,
            PRIMARY KEY (id),
            UNIQUE INDEX idx_user_email (email)
        ) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci ENGINE = InnoDB');
    }

    public function down(Schema $schema): void
    {
        $this->addSql('DROP TABLE users');
    }
}
```

## Common Commands

```bash
# Check migration status
php bin/console doctrine:migrations:status

# Generate diff from mappings
php bin/console doctrine:migrations:diff

# Create empty migration
php bin/console doctrine:migrations:generate

# Run pending migrations
php bin/console doctrine:migrations:migrate

# Rollback last migration
php bin/console doctrine:migrations:migrate prev

# Rollback to specific version
php bin/console doctrine:migrations:migrate 'DoctrineMigrations\Version20240101000000'

# List all migrations
php bin/console doctrine:migrations:list
```

## Best Practices

1. **Never edit applied migrations** — Create a new migration instead
2. **Always review auto-generated migrations** before applying
3. **Write both `up()` and `down()`** for reversibility
4. **Use descriptive `getDescription()`** for documentation
5. **Test migrations** in CI/CD pipeline before production
6. **Keep migrations atomic** — one logical change per migration
7. **Add data migrations** when schema changes require data transformation

## Data Migration Example

```php
public function up(Schema $schema): void
{
    // Schema change
    $this->addSql('ALTER TABLE users ADD status VARCHAR(20) NOT NULL DEFAULT \'active\'');

    // Data migration
    $this->addSql('UPDATE users SET status = \'active\' WHERE deleted_at IS NULL');
    $this->addSql('UPDATE users SET status = \'deleted\' WHERE deleted_at IS NOT NULL');
}
```

## CI/CD Integration

```yaml
# In your CI pipeline
steps:
    - name: Run migrations
      run: |
          php bin/console doctrine:migrations:migrate --no-interaction
          php bin/console doctrine:schema:validate
```
