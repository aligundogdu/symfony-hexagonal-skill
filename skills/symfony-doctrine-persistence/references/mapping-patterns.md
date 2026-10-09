# Doctrine Mapping Patterns

## Rule: Mapping Lives in Infrastructure

Domain entities have NO Doctrine annotations/attributes. Mapping is defined as XML in `Infrastructure/{Module}/Persistence/Mapping/`. The `<?xml ?>` declaration must be the very first bytes of the file (no comment before it): ORM 3 validates every mapping file against the XSD and fails at boot otherwise.

## XML Mapping

### Entity Mapping

File: `src/Infrastructure/User/Persistence/Mapping/Entity.User.orm.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<doctrine-mapping xmlns="http://doctrine-project.org/schemas/orm/doctrine-mapping"
                  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                  xsi:schemaLocation="http://doctrine-project.org/schemas/orm/doctrine-mapping
                  https://www.doctrine-project.org/schemas/orm/doctrine-mapping.xsd">

    <entity name="App\Domain\User\Entity\User" table="users">
        <id name="id" type="user_id" column="id" />

        <embedded name="email" class="App\Domain\User\ValueObject\Email" use-column-prefix="false" />

        <field name="name" type="string" length="255" />
        <field name="passwordHash" type="string" column="password_hash" length="255" />
        <field name="status" type="string" length="20" enum-type="App\Domain\User\ValueObject\UserStatus" />
        <field name="createdAt" type="datetime_immutable" column="created_at" />
        <field name="updatedAt" type="datetime_immutable" column="updated_at" nullable="true" />

        <indexes>
            <index name="idx_user_status" columns="status" />
        </indexes>
    </entity>
</doctrine-mapping>
```

`user_id` is a custom DBAL type (below) that converts the `UserId` value object. Alternative without a custom type: map `id` as `<embedded>` with a `value` field, or keep `type="guid"` and store `string` in the entity.

### Embeddable (Value Object) Mapping

File: `src/Infrastructure/User/Persistence/Mapping/ValueObject.Email.orm.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<doctrine-mapping xmlns="http://doctrine-project.org/schemas/orm/doctrine-mapping"
                  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                  xsi:schemaLocation="http://doctrine-project.org/schemas/orm/doctrine-mapping
                  https://www.doctrine-project.org/schemas/orm/doctrine-mapping.xsd">

    <embeddable name="App\Domain\User\ValueObject\Email">
        <field name="value" type="string" column="email" length="180" unique="true" />
    </embeddable>
</doctrine-mapping>
```

`final readonly` value objects work as embeddables: Doctrine hydrates through reflection without calling the constructor (so DB data is trusted, invariants are enforced on the way in).

### Doctrine Configuration

```yaml
# config/packages/doctrine.yaml
doctrine:
    dbal:
        url: '%env(resolve:DATABASE_URL)%'
        types:
            user_id: App\Infrastructure\User\Persistence\Type\UserIdType
    orm:
        # DoctrineBundle 2.16+ with ORM 3.4+ on PHP 8.4: use native lazy objects
        # (always on from DoctrineBundle 3.1, where the option is deprecated). Omit on older stacks.
        # enable_native_lazy_objects: true
        mappings:
            User:
                type: xml
                is_bundle: false
                dir: '%kernel.project_dir%/src/Infrastructure/User/Persistence/Mapping'
                prefix: 'App\Domain\User'
                alias: User
            Order:
                type: xml
                is_bundle: false
                dir: '%kernel.project_dir%/src/Infrastructure/Order/Persistence/Mapping'
                prefix: 'App\Domain\Order'
                alias: Order
```

**File naming:** with `type: xml` DoctrineBundle uses the simplified XML driver: the file name is the class name relative to `prefix`, with `\` replaced by `.`. With `prefix: 'App\Domain\User'`, `App\Domain\User\Entity\User` lives in `Entity.User.orm.xml` and `App\Domain\User\ValueObject\Email` in `ValueObject.Email.orm.xml`. Run `php bin/console doctrine:mapping:info` to confirm every class is found.

## Custom Doctrine Types

For value objects that need custom DB representation (DBAL 3 and 4 compatible):

```php
namespace App\Infrastructure\User\Persistence\Type;

use App\Domain\User\ValueObject\UserId;
use Doctrine\DBAL\Platforms\AbstractPlatform;
use Doctrine\DBAL\Types\ConversionException;
use Doctrine\DBAL\Types\Type;

final class UserIdType extends Type
{
    public function getSQLDeclaration(array $column, AbstractPlatform $platform): string
    {
        return $platform->getGuidTypeDeclarationSQL($column);
    }

    public function convertToPHPValue(mixed $value, AbstractPlatform $platform): ?UserId
    {
        if ($value === null || $value instanceof UserId) {
            return $value;
        }
        if (!is_string($value)) {
            throw new ConversionException(sprintf('Cannot convert %s to UserId', get_debug_type($value)));
        }

        return new UserId($value);
    }

    public function convertToDatabaseValue(mixed $value, AbstractPlatform $platform): ?string
    {
        return match (true) {
            $value === null => null,
            $value instanceof UserId => $value->value,
            is_string($value) => $value,
            default => throw new ConversionException(sprintf('Cannot convert %s to database value', get_debug_type($value))),
        };
    }
}
```

DBAL 4 removed `getName()` and `requiresSQLCommentHint()`: the name comes from the `doctrine.dbal.types` config. On **DBAL 3** `getName()` is still abstract, so add `public function getName(): string { return 'user_id'; }`; keeping it after upgrading to DBAL 4 is harmless.

Prefer embeddables for multi-column value objects (e.g. `Money` = amount + currency); custom types for single-column ones (IDs).

## Relation Mapping

### One-to-Many (Aggregate with children)

`Entity.Order.orm.xml` (prefix `App\Domain\Order`):

```xml
<entity name="App\Domain\Order\Entity\Order" table="orders">
    <id name="id" type="order_id" column="id" />
    <field name="customerId" type="guid" column="customer_id" />
    <field name="status" type="string" length="20" enum-type="App\Domain\Order\ValueObject\OrderStatus" />
    <field name="currency" type="string" length="3" />
    <field name="placedAt" type="datetime_immutable" column="placed_at" />

    <one-to-many field="items" target-entity="App\Domain\Order\Entity\OrderItem" mapped-by="order" orphan-removal="true">
        <cascade>
            <cascade-persist />
            <cascade-remove />
        </cascade>
    </one-to-many>
</entity>
```

`Entity.OrderItem.orm.xml`:

```xml
<entity name="App\Domain\Order\Entity\OrderItem" table="order_items">
    <id name="id" type="integer" column="id">
        <generator strategy="IDENTITY" />
    </id>
    <field name="productId" type="guid" column="product_id" />
    <field name="quantity" type="integer" />
    <embedded name="unitPrice" class="App\Domain\Shared\ValueObject\Money" column-prefix="unit_price_" />

    <many-to-one field="order" target-entity="App\Domain\Order\Entity\Order" inversed-by="items">
        <join-column name="order_id" referenced-column-name="id" nullable="false" on-delete="CASCADE" />
    </many-to-one>
</entity>
```

The domain `OrderItem` has the matching `$id` and `$order` properties (see domain-modeling `entity-patterns.md`). ORM 3 defaults `AUTO` to `IDENTITY` on most platforms; write `IDENTITY` (or `SEQUENCE` on PostgreSQL) explicitly.

### Many-to-Many (prefer IDs across aggregates)

Across aggregate boundaries, reference by ID (`<field name="categoryIds" type="json" />` or a join entity) instead of object associations. Inside one aggregate:

```xml
<entity name="App\Domain\Product\Entity\Product" table="products">
    <many-to-many field="tags" target-entity="App\Domain\Product\Entity\Tag">
        <join-table name="product_tags">
            <join-columns>
                <join-column name="product_id" referenced-column-name="id" />
            </join-columns>
            <inverse-join-columns>
                <join-column name="tag_id" referenced-column-name="id" />
            </inverse-join-columns>
        </join-table>
    </many-to-many>
</entity>
```

## Enum Mapping

```xml
<field name="status" type="string" length="20" enum-type="App\Domain\Order\ValueObject\OrderStatus" />
```

The XML attribute is `enum-type` (kebab-case); `enumType` is the PHP attribute spelling and is rejected by the XSD.
