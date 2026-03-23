# No Native SQL Policy

## Rule

**NEVER use native/raw SQL in application code.** Always use Doctrine's abstraction layers: QueryBuilder (ORM or DBAL), DQL, finder methods, or Criteria API.

**Only exception:** Doctrine Migrations (`$this->addSql()`) - the migration API requires raw SQL by design.

## Forbidden Patterns

All of the following are CRITICAL violations when found in application code:

```php
// FORBIDDEN: Connection::executeQuery with raw SQL
$connection->executeQuery('SELECT * FROM users WHERE email = ?', [$email]);

// FORBIDDEN: Connection::executeStatement with raw SQL
$connection->executeStatement('UPDATE users SET status = ? WHERE id = ?', ['active', $id]);

// FORBIDDEN: Connection::prepare with raw SQL
$stmt = $connection->prepare('SELECT * FROM orders WHERE customer_id = :id');
$stmt->bindValue('id', $customerId);
$result = $stmt->executeQuery();

// FORBIDDEN: Connection::exec with raw SQL
$connection->exec('DROP TABLE temp_users');

// FORBIDDEN: EntityManager::getConnection() to bypass ORM
$entityManager->getConnection()->executeQuery('SELECT ...');

// FORBIDDEN: NativeQuery
$rsm = new ResultSetMapping();
$query = $entityManager->createNativeQuery('SELECT * FROM users', $rsm);

// FORBIDDEN: Raw SQL via DBAL Statement
$connection->fetchAllAssociative('SELECT * FROM users');
$connection->fetchOne('SELECT COUNT(*) FROM users');
```

## Correct Alternatives

### Simple queries: Use ORM QueryBuilder

```php
// Instead of: SELECT * FROM users WHERE email = ?
$user = $this->entityManager->createQueryBuilder()
    ->select('u')
    ->from(User::class, 'u')
    ->where('u.email.value = :email')
    ->setParameter('email', $email)
    ->getQuery()
    ->getOneOrNullResult();
```

### Complex read queries: Use DBAL QueryBuilder

```php
// Instead of: SELECT u.id, u.email, COUNT(o.id) FROM users u LEFT JOIN orders o ...
$qb = $this->connection->createQueryBuilder()
    ->select('u.id', 'u.email', 'COUNT(o.id) AS order_count')
    ->from('users', 'u')
    ->leftJoin('u', 'orders', 'o', 'o.customer_id = u.id')
    ->groupBy('u.id')
    ->orderBy('order_count', 'DESC');

$results = $qb->fetchAllAssociative();
```

### Filtering with dynamic conditions: Use DBAL QueryBuilder

```php
// Instead of: building raw SQL string with concatenation
$qb = $this->connection->createQueryBuilder()
    ->select('id', 'name', 'email', 'status', 'created_at')
    ->from('users');

if ($status !== null) {
    $qb->andWhere('status = :status')->setParameter('status', $status);
}

if ($search !== null) {
    $qb->andWhere('(name LIKE :search OR email LIKE :search)')
        ->setParameter('search', '%' . $search . '%');
}

$qb->orderBy('created_at', 'DESC')
    ->setFirstResult(($page - 1) * $limit)
    ->setMaxResults($limit);

$rows = $qb->fetchAllAssociative();
```

### Aggregations: Use DQL or DBAL QueryBuilder

```php
// Instead of: SELECT COUNT(*) FROM users WHERE status = 'active'
$count = (int) $this->entityManager->createQueryBuilder()
    ->select('COUNT(u.id)')
    ->from(User::class, 'u')
    ->where('u.status = :status')
    ->setParameter('status', 'active')
    ->getQuery()
    ->getSingleScalarResult();
```

### Batch updates: Use DQL UPDATE

```php
// Instead of: UPDATE users SET status = 'inactive' WHERE last_login < ?
$this->entityManager->createQueryBuilder()
    ->update(User::class, 'u')
    ->set('u.status', ':status')
    ->where('u.lastLogin < :threshold')
    ->setParameter('status', 'inactive')
    ->setParameter('threshold', $thresholdDate)
    ->getQuery()
    ->execute();
```

### Batch deletes: Use DQL DELETE

```php
// Instead of: DELETE FROM sessions WHERE expired_at < NOW()
$this->entityManager->createQueryBuilder()
    ->delete(Session::class, 's')
    ->where('s.expiredAt < :now')
    ->setParameter('now', new \DateTimeImmutable())
    ->getQuery()
    ->execute();
```

### Subqueries: Use DQL with nested QueryBuilder

```php
// Instead of: SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE total > 1000)
$subQuery = $this->entityManager->createQueryBuilder()
    ->select('IDENTITY(o.user)')
    ->from(Order::class, 'o')
    ->where('o.total > :minTotal')
    ->getDQL();

$users = $this->entityManager->createQueryBuilder()
    ->select('u')
    ->from(User::class, 'u')
    ->where($this->entityManager->getExpressionBuilder()->in('u.id', $subQuery))
    ->setParameter('minTotal', 1000)
    ->getQuery()
    ->getResult();
```

### Criteria API for collection filtering

```php
use Doctrine\Common\Collections\Criteria;

$criteria = Criteria::create()
    ->where(Criteria::expr()->eq('status', 'active'))
    ->andWhere(Criteria::expr()->gt('createdAt', $since))
    ->orderBy(['createdAt' => 'DESC'])
    ->setMaxResults(10);

$activeUsers = $userRepository->matching($criteria);
```

## Migrations: The Exception

Doctrine Migrations use `$this->addSql()` which takes raw SQL. This is acceptable because:
- The migration API is designed around raw SQL - there is no QueryBuilder alternative
- Migrations are schema management, not application logic
- They run once and are versioned - not part of the runtime query path

```php
// ALLOWED in migrations only
public function up(Schema $schema): void
{
    $this->addSql('CREATE TABLE users (
        id VARCHAR(36) NOT NULL,
        email VARCHAR(255) NOT NULL,
        PRIMARY KEY (id)
    )');
}
```

## Common Objections

### "QueryBuilder is slower than raw SQL"
QueryBuilder adds negligible overhead - the SQL generation happens once and can be cached. The database query itself is the bottleneck, not the PHP object that builds the SQL string.

### "I need a database-specific function"
Use `$queryBuilder->expr()` or DQL functions. For truly database-specific features, create a custom DQL function and register it in `doctrine.yaml`.

### "My query is too complex for QueryBuilder"
DBAL QueryBuilder supports JOINs, subqueries, UNION (via `->add('select', ...)`), CTEs, and window functions. If you think QueryBuilder can't handle it, check the DBAL documentation first. In extremely rare edge cases, discuss with the team before resorting to native SQL.
