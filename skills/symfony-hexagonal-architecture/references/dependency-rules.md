# Dependency Rules

## Import Rules by Layer

### Domain Layer - ZERO external dependencies

```
ALLOWED imports in Domain/:
✅ Other Domain/ classes (same module, or Domain\Shared)
✅ PHP built-in classes (DateTimeImmutable, InvalidArgumentException, etc.)

FORBIDDEN imports in Domain/:
❌ Symfony\*            (also: no #[Assert\...], #[AsMessage], #[Map] attributes)
❌ Doctrine\*           (also: no #[ORM\...] attributes, no Collection types)
❌ Psr\*                (define your own ClockInterface / LoggerPort if needed)
❌ App\Application\*
❌ App\Infrastructure\*
❌ App\Presentation\*
❌ Any third-party library (incl. ramsey/uuid, symfony/uid, polyfills used implicitly)
```

### Application Layer

```
ALLOWED imports in Application/:
✅ App\Domain\* (entities, value objects, ports, events)
✅ Symfony\Component\Messenger\* (for #[AsMessageHandler], #[AsMessage], stamps)
✅ Symfony\Component\Validator\* (for command/DTO constraints)

FORBIDDEN imports in Application/:
❌ App\Infrastructure\*
❌ App\Presentation\*
❌ Doctrine\*
❌ Symfony\Component\HttpFoundation\*, Symfony\Component\Security\* (use ports)
❌ Concrete adapter classes
```

### Infrastructure Layer

```
ALLOWED imports in Infrastructure/:
✅ App\Domain\* (implements port interfaces)
✅ Doctrine\* (ORM, DBAL)
✅ Symfony\* (framework services)
✅ Third-party libraries (HTTP clients, SDKs)

FORBIDDEN imports in Infrastructure/:
❌ App\Application\* (no direct handler calls)
❌ App\Presentation\*
```

### Presentation Layer

```
ALLOWED imports in Presentation/:
✅ App\Application\* (commands, queries, DTOs)
✅ Symfony\* (controllers, routing, security, serializer, validator)

FORBIDDEN imports in Presentation/:
❌ App\Domain\* (never use domain objects directly)
   Exception: App\Domain\*\Exception\* may be imported to map domain errors to HTTP codes
❌ App\Infrastructure\* (never use adapters directly; voter attribute names are passed as strings/constants)
❌ Doctrine\* (no direct DB access)
```

## Deptrac (Recommended Enforcement)

```bash
composer require --dev deptrac/deptrac   # package moved from qossmic/deptrac
vendor/bin/deptrac analyse
```

```yaml
# deptrac.yaml
deptrac:
  paths:
    - ./src
  layers:
    - name: Domain
      collectors:
        - type: bool
          must:
            - type: directory
              value: src/Domain/.*
          must_not:
            - type: directory
              value: src/Domain/.*/Exception/.*
    - name: DomainException
      collectors:
        - type: directory
          value: src/Domain/.*/Exception/.*
    - name: Application
      collectors:
        - type: directory
          value: src/Application/.*
    - name: Infrastructure
      collectors:
        - type: directory
          value: src/Infrastructure/.*
    - name: Presentation
      collectors:
        - type: directory
          value: src/Presentation/.*
    # Vendor layers so that "Domain uses Symfony/Doctrine" is reported too
    - name: Symfony
      collectors:
        - type: classLike
          value: ^Symfony\\.*
    - name: SymfonyMessengerValidator
      collectors:
        - type: classLike
          value: ^Symfony\\Component\\(Messenger|Validator)\\.*
    - name: Doctrine
      collectors:
        - type: classLike
          value: ^Doctrine\\.*
  ruleset:
    Domain:
      - DomainException
    DomainException: ~
    Application:
      - Domain
      - DomainException
      - SymfonyMessengerValidator
    Infrastructure:
      - Domain
      - DomainException
      - Symfony
      - Doctrine
    Presentation:
      - Application
      - DomainException     # error mapping only
      - Symfony
```

Run `vendor/bin/deptrac analyse --report-uncovered` once to confirm the vendor layers collect what you expect in your deptrac version.

## PHPStan

### phpstan.neon (PHPStan 2.x)

```neon
includes:
    - vendor/phpstan/phpstan-symfony/extension.neon
    - vendor/phpstan/phpstan-doctrine/extension.neon
    - vendor/phpstan/phpstan-phpunit/extension.neon
    - vendor/phpstan/phpstan-strict-rules/rules.neon
    - vendor/phpstan/phpstan-deprecation-rules/rules.neon

parameters:
    level: 8          # mandatory minimum; 9 recommended for new projects, 10 = no implicit mixed
    paths:
        - src/
        - tests/
    excludePaths:
        - src/Kernel.php
    tmpDir: var/phpstan
    symfony:
        containerXmlPath: var/cache/dev/App_KernelDevDebugContainer.xml
    doctrine:
        objectManagerLoader: tests/object-manager.php
```

Notes:
- `checkGenericClassInNonGenericObjectType` was removed in PHPStan 2: delete it from old configs or PHPStan fails with "unknown parameter".
- `phpstan-deprecation-rules` is the cheapest way to find code that will break on Symfony 8.
- Level 8 requires iterable value types: write `/** @var list<DomainEvent> */` instead of a bare `array`.

```bash
composer require --dev phpstan/phpstan phpstan/extension-installer \
    phpstan/phpstan-symfony phpstan/phpstan-doctrine phpstan/phpstan-phpunit \
    phpstan/phpstan-strict-rules phpstan/phpstan-deprecation-rules
```

With `phpstan/extension-installer` the `includes:` block can be dropped.

## Cross-Module Communication

Modules should communicate through domain events, not direct imports:

```
ALLOWED cross-module:
✅ Module A dispatches event → Module B's Application/EventHandler handles it
✅ Shared kernel value objects (App\Domain\Shared\*)

FORBIDDEN cross-module:
❌ Module A directly calls Module B's repository
❌ Module A imports Module B's entities
❌ Direct service-to-service calls between modules
```

### Shared Kernel

Common value objects and interfaces shared across modules:

```
src/Domain/Shared/
├── ValueObject/
│   ├── Money.php
│   └── DateRange.php
├── Event/
│   └── DomainEvent.php          (base interface)
├── ReadModel/
│   └── Page.php                 (generic pagination result for read ports)
└── Port/
    ├── IdGeneratorInterface.php (UUIDs without depending on symfony/uid)
    └── ClockInterface.php       (testable "now")
```
