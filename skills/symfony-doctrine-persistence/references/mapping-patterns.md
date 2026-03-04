# Doctrine Mapping Patterns

## Rule: Mapping Lives in Infrastructure

Domain entities have NO Doctrine annotations/attributes. Mapping is defined in `Infrastructure/{Module}/Persistence/Mapping/`.

## XML Mapping

### Entity Mapping

```xml
<!-- src/Infrastructure/User/Persistence/Mapping/User.orm.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<doctrine-mapping xmlns="http://doctrine-project.org/schemas/orm/doctrine-mapping"
                  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                  xsi:schemaLocation="http://doctrine-project.org/schemas/orm/doctrine-mapping
                  https://www.doctrine-project.org/schemas/orm/doctrine-mapping.xsd">

    <entity name="App\Domain\User\Entity\User" table="users">
        <id name="id" type="string" column="id" length="36" />

        <embedded name="email" class="App\Domain\User\ValueObject\Email" use-column-prefix="false" />

        <field name="name" type="string" length="255" />
        <field name="passwordHash" type="string" column="password_hash" length="255" />
        <field name="status" type="string" length="20" />
        <field name="createdAt" type="datetime_immutable" column="created_at" />
        <field name="updatedAt" type="datetime_immutable" column="updated_at" nullable="true" />

        <indexes>
            <index name="idx_user_email" columns="email" />
            <index name="idx_user_status" columns="status" />
        </indexes>
    </entity>
</doctrine-mapping>
```

### Embeddable (Value Object) Mapping

```xml
<!-- src/Infrastructure/User/Persistence/Mapping/Email.orm.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<doctrine-mapping xmlns="http://doctrine-project.org/schemas/orm/doctrine-mapping">

    <embeddable name="App\Domain\User\ValueObject\Email">
        <field name="value" type="string" column="email" length="255" unique="true" />
    </embeddable>
</doctrine-mapping>
```

### Doctrine Configuration

```yaml
# config/packages/doctrine.yaml
doctrine:
    orm:
        mappings:
            User:
                type: xml
                dir: '%kernel.project_dir%/src/Infrastructure/User/Persistence/Mapping'
                prefix: 'App\Domain\User'
                alias: User
            Order:
                type: xml
                dir: '%kernel.project_dir%/src/Infrastructure/Order/Persistence/Mapping'
                prefix: 'App\Domain\Order'
                alias: Order
```

## Custom Doctrine Types

For value objects that need custom DB representation:

```php
namespace App\Infrastructure\Shared\Persistence\Type;

use App\Domain\Shared\ValueObject\Money;
use Doctrine\DBAL\Platforms\AbstractPlatform;
use Doctrine\DBAL\Types\Type;

final class MoneyType extends Type
{
    public const NAME = 'money';

    public function getSQLDeclaration(array $column, AbstractPlatform $platform): string
    {
        return $platform->getIntegerTypeDeclarationSQL($column);
    }

    public function convertToPHPValue($value, AbstractPlatform $platform): ?Money
    {
        if ($value === null) {
            return null;
        }

        return new Money((int) $value, 'EUR');
    }

    public function convertToDatabaseValue($value, AbstractPlatform $platform): ?int
    {
        if ($value === null) {
            return null;
        }

        return $value instanceof Money ? $value->amount : (int) $value;
    }

    public function getName(): string
    {
        return self::NAME;
    }
}
```

Register in `doctrine.yaml`:
```yaml
doctrine:
    dbal:
        types:
            money: App\Infrastructure\Shared\Persistence\Type\MoneyType
```

## Relation Mapping

### One-to-Many (Aggregate with children)

```xml
<entity name="App\Domain\Order\Entity\Order" table="orders">
    <id name="id" type="string" column="id" length="36" />
    <field name="customerId" type="string" column="customer_id" length="36" />
    <field name="status" type="string" length="20" />
    <field name="createdAt" type="datetime_immutable" column="created_at" />

    <one-to-many field="items" target-entity="App\Domain\Order\Entity\OrderItem" mapped-by="order">
        <cascade>
            <cascade-persist />
            <cascade-remove />
        </cascade>
    </one-to-many>
</entity>

<entity name="App\Domain\Order\Entity\OrderItem" table="order_items">
    <id name="id" type="integer" column="id">
        <generator strategy="AUTO" />
    </id>
    <field name="productId" type="string" column="product_id" length="36" />
    <field name="quantity" type="integer" />
    <field name="unitPrice" type="integer" column="unit_price" />

    <many-to-one field="order" target-entity="App\Domain\Order\Entity\Order" inversed-by="items">
        <join-column name="order_id" referenced-column-name="id" nullable="false" />
    </many-to-one>
</entity>
```

### Many-to-Many

```xml
<entity name="App\Domain\Product\Entity\Product" table="products">
    <many-to-many field="categories" target-entity="App\Domain\Category\Entity\Category">
        <join-table name="product_categories">
            <join-columns>
                <join-column name="product_id" referenced-column-name="id" />
            </join-columns>
            <inverse-join-columns>
                <join-column name="category_id" referenced-column-name="id" />
            </inverse-join-columns>
        </join-table>
    </many-to-many>
</entity>
```

## Enum Mapping

```xml
<field name="status" type="string" length="20" enumType="App\Domain\Order\ValueObject\OrderStatus" />
```
