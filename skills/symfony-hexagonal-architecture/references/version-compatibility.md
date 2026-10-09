# Version Compatibility

The skills support **Symfony 6.4 LTS, 7.4 LTS and 8.x**. Code must match the project's installed versions, not the newest release.

## Step 0: Detect the Stack (always, before generating code)

The plugin's SessionStart hook prints a "Detected Stack" block. If it is missing (manual install), detect it yourself:

```bash
# Installed versions (authoritative)
composer show symfony/framework-bundle doctrine/orm doctrine/dbal doctrine/doctrine-bundle phpunit/phpunit phpstan/phpstan 2>/dev/null | grep -E '^(name|versions)'
# Fallback without vendor/: read composer.lock / composer.json
grep -A1 '"name": "symfony/framework-bundle"' composer.lock
grep '"php"' composer.json
```

Then pick the matching column below. When the project is older than a feature's minimum version, use the **Fallback** column. Never upgrade dependencies on your own; suggest it.

## Support Matrix (as of October 2026)

| | Symfony 6.4 LTS | Symfony 7.4 LTS | Symfony 8.1 (8.2 due Nov 2026) |
|---|---|---|---|
| PHP minimum | 8.1 | 8.2 | 8.4 |
| Support | bugfix ends Nov 2026, security Nov 2027 | bugfix Nov 2028, security Nov 2029 | 8.1 until Jan 2027, then 8.2 |
| Doctrine ORM | 2.x or 3.x | 3.x | 3.4+ (native lazy objects) |
| DBAL | 3.x or 4.x | 4.x | 4.x |
| DoctrineBundle | 2.x | 2.x or 3.x | 3.x |
| PHPUnit | 10 / 11 | 11 / 12 | 12 / 13 |
| PHPStan | 1.x or 2.x | 2.x | 2.x |
| Config formats | YAML, XML, PHP | YAML, PHP arrays (XML deprecated) | YAML, PHP arrays (XML removed) |

Rules of thumb:
- **8.0 = 7.4 minus deprecations.** Code that runs on 7.4 without deprecation notices runs on 8.x.
- **Baseline for generated code: PHP 8.2 + Symfony 6.4 APIs.** It runs on every supported version. Use newer features only when the detected version allows it.
- Projects on 6.4 should plan the move to 7.4 LTS (6.4 bugfix support ends November 2026).

## Feature Matrix

| Feature | Min. version | Fallback for older projects |
|---|---|---|
| `final readonly class` | PHP 8.2 | PHP 8.1: `final class` + `public readonly` promoted properties |
| `#[AsMessageHandler(bus: ...)]` | Symfony 6.0 | - |
| `#[MapRequestPayload]`, `#[MapQueryString]`, `#[MapQueryParameter]` | Symfony 6.3 | Decode JSON manually + `ValidatorInterface` |
| `#[IsGranted(attr, subject: 'argName')]` | Symfony 6.2 | `$authorizationChecker->isGranted()` in the controller |
| `#[AsCronTask]`, `#[AsPeriodicTask]`, Scheduler component | Symfony 6.3 / 6.4 | `ScheduleProviderInterface` (6.3) |
| `#[AsMessage('async')]` routing on the message class | Symfony 7.2 | `framework.messenger.routing` in YAML |
| Retry `jitter` option | Symfony 7.1 | omit it |
| `DeduplicateStamp` (needs symfony/lock) | Symfony 7.3 | Idempotency key + unique constraint (see messenger skill) |
| Voter `?Vote $vote` reasons | Symfony 7.3 | Declare the parameter anyway (see security skill), it is simply `null` before 7.3 |
| `#[IsGranted]` with a closure | Symfony 7.3 **and PHP 8.5** | `subject:` + Voter |
| `#[AsAlias(when: 'test')]` | Symfony 7.3 | `when@test:` block in `services.yaml` |
| ObjectMapper `#[Map]` | Symfony 7.3 (experimental), 8.1 adds `#[Map(source:)]` | Static `fromX()` named constructors on DTOs |
| Constraint options as named args only (`new Assert\Length(min: 3)`) | Required from 8.0 (arrays deprecated 7.3) | Named args work on every version, always use them |
| `#[ExtendsValidationFor(Target::class)]` | Symfony 7.4 | Validate a Request DTO / the Command instead |
| PHP array config + `config/reference.php` | Symfony 7.4 | YAML (works everywhere, still the recommended default) |
| UUIDv7 default in `UuidFactory` | Symfony 7.4 | `Uuid::v7()` explicitly (6.2+) |
| `#[AsMessageHandler(sign: true)]` message signing | Symfony 7.4 | Trusted transport only |
| `#[AsMessage(serializedTypeName: ...)]`, `PriorityStamp`, `#[MapRequestHeader]` | Symfony 8.1 | YAML serializer config, separate transports, `$request->headers` |
| Asymmetric visibility `public private(set)`, property hooks | PHP 8.4 (Doctrine ORM 3.4+) | Private property + getter |
| `clone($vo, ['amount' => $x])` (clone with) | PHP 8.5 | `new self(...)` in withers |
| Native lazy objects (`enable_native_lazy_objects`) | PHP 8.4 + ORM 3.4 + DoctrineBundle 2.16 (always on in DoctrineBundle 3.1) | Proxy classes (default) |
| `OffsetPaginator` + `Window` | Doctrine ORM 3.7 (`Paginator` deprecated) | `Doctrine\ORM\Tools\Pagination\Paginator` |
| Custom DBAL type without `getName()` | DBAL 4 (method removed) | DBAL 3: keep `getName()`, it is harmless to omit from 4 on |
| PHPUnit attributes only (`#[Test]`, `#[DataProvider]`) | PHPUnit 10 (annotations removed in 12) | `test_` method prefix works on every version |
| `createStub()` for stubs, `createMock()` only with expectations | Enforced by PHPUnit 13 (notice) | Same code works on 10+ |
| PHPStan level 10 | PHPStan 2.0 | level 9 max on 1.x |

## APIs Removed in Symfony 8 (never generate them)

| Removed / deprecated | Use instead |
|---|---|
| `Request::get()` (deprecated 7.4) | `$request->attributes`, `->query`, `->request`, or `#[MapQueryParameter]` |
| Constraint option arrays `new Assert\Choice(['choices' => ...])` | Named arguments `new Assert\Choice(choices: [...])` |
| Custom constraint without named-argument constructor | Constructor with named args (see validation skill) |
| XML for services/routes, fluent `Symfony\Config\*` builders | YAML or PHP array config. **Doctrine XML entity mapping is not affected.** |
| `UserInterface::eraseCredentials()` (deprecated 7.3) | Do not store plain passwords on the user object |
| Doctrine annotations (`@ORM\...`) (removed in ORM 3) | XML mapping in Infrastructure |
| YAML Doctrine mapping (removed in ORM 3) | XML mapping |
| `Type::getName()`, `requiresSQLCommentHint()` (DBAL 4) | Register the type name in `doctrine.yaml` |
| `checkGenericClassInNonGenericObjectType` (PHPStan 2) | Remove the parameter |
| Foundry `ModelFactory` (Foundry 2) | `PersistentObjectFactory` / `ObjectFactory` |

## How to Write Version-Aware Answers

1. State which version you targeted when it matters: "Targets Symfony 7.4 (detected). On 6.4, replace X with Y."
2. Prefer code that works on all supported versions when the cost is low (named constraint args, `?Vote $vote = null`, `(new Schedule())` instead of `new Schedule()->...`).
3. Gate PHP 8.4/8.5 syntax (`private(set)`, property hooks, `new Foo()->bar()`, pipe operator, `clone with`) behind the detected PHP constraint.
4. When a project is on an unsupported version (Symfony < 6.4, PHP < 8.1), say so and generate 6.4-compatible code.
