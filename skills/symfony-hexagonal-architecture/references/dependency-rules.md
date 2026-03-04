# Dependency Rules

## Import Rules by Layer

### Domain Layer — ZERO external dependencies

```
ALLOWED imports in Domain/:
✅ Other Domain/ classes (same or different module)
✅ PHP built-in classes (DateTimeImmutable, InvalidArgumentException, etc.)

FORBIDDEN imports in Domain/:
❌ Symfony\Component\*
❌ Doctrine\*
❌ App\Application\*
❌ App\Infrastructure\*
❌ App\Presentation\*
❌ Any third-party library
```

### Application Layer

```
ALLOWED imports in Application/:
✅ App\Domain\* (entities, value objects, ports, events)
✅ Symfony\Component\Messenger\* (for #[AsMessageHandler])
✅ Symfony\Component\Validator\* (for DTO validation)

FORBIDDEN imports in Application/:
❌ App\Infrastructure\*
❌ App\Presentation\*
❌ Doctrine\*
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
✅ Symfony\* (controllers, routing, security, forms)

FORBIDDEN imports in Presentation/:
❌ App\Domain\* (never use domain objects directly)
❌ App\Infrastructure\* (never use adapters directly)
❌ Doctrine\* (no direct DB access)
```

## PHPStan Enforcement

### depfile.neon — Dependency Rules for deptrac/phpstan

```neon
# phpstan-deptrac.neon
parameters:
    paths:
        - src/

rules:
    # Domain has no external deps
    - layer: Domain
      disallow:
        - Symfony\*
        - Doctrine\*
        - App\Application\*
        - App\Infrastructure\*
        - App\Presentation\*

    # Application only uses Domain
    - layer: Application
      disallow:
        - Doctrine\*
        - App\Infrastructure\*
        - App\Presentation\*

    # Presentation doesn't touch Domain or Infrastructure directly
    - layer: Presentation
      disallow:
        - App\Domain\*
        - App\Infrastructure\*
        - Doctrine\*
```

### PHPStan Configuration (phpstan.neon)

```neon
parameters:
    level: 8
    paths:
        - src/
    excludePaths:
        - src/Kernel.php
    checkGenericClassInNonGenericObjectType: false

includes:
    - vendor/phpstan/phpstan-symfony/extension.neon
    - vendor/phpstan/phpstan-doctrine/extension.neon
```

### Recommended PHPStan Extensions

```
composer require --dev \
    phpstan/phpstan \
    phpstan/phpstan-symfony \
    phpstan/phpstan-doctrine \
    phpstan/phpstan-strict-rules \
    phpstan/phpstan-deprecation-rules
```

## Deptrac Configuration (Alternative)

For projects that prefer Deptrac for layer dependency enforcement:

```yaml
# deptrac.yaml
deptrac:
  paths:
    - ./src/
  layers:
    - name: Domain
      collectors:
        - type: directory
          value: src/Domain/.*
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
  ruleset:
    Domain: ~
    Application:
      - Domain
    Infrastructure:
      - Domain
    Presentation:
      - Application
```

## Cross-Module Communication

Modules should communicate through domain events, not direct imports:

```
ALLOWED cross-module:
✅ Module A dispatches event → Module B handles event
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
│   ├── Uuid.php
│   ├── Money.php
│   └── DateRange.php
├── Event/
│   └── DomainEvent.php (base interface)
└── Port/
    └── EventDispatcherInterface.php
```
