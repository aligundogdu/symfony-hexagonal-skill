# Changelog

## 2.0.0 - 2026-10-09

### Installation
- Restored the Claude Code plugin packaging: `.claude-plugin/plugin.json` + `marketplace.json`. Install with `/plugin marketplace add aligundogdu/symfony-hexagonal-skill` and `/plugin install symfony-hexagonal@symfony-hexagonal-skill`.
- Architecture rules moved from `CLAUDE.md` to `rules/hexagonal-rules.md` and are injected by a SessionStart hook, **only in Symfony projects**, together with the detected Symfony / PHP / Doctrine / PHPUnit versions.
- README: plugin, team (`.claude/settings.json`), copy and symlink installation paths.

### Multi-version support (Symfony 6.4 LTS, 7.4 LTS, 8.x)
- New `version-compatibility.md`: support matrix, per-feature minimum versions with fallbacks, list of APIs removed in Symfony 8.
- Every skill has a "Version Notes" table; code samples default to APIs that run on all supported versions.
- Covered: `#[AsMessage]` (7.2), `DeduplicateStamp` (7.3), voter `?Vote` reasons (7.3), `#[ExtendsValidationFor]` (7.4), UUIDv7 default (7.4), message signing (7.4), 8.1 additions, PHP 8.4/8.5 modeling features, Doctrine ORM 3.x (native lazy objects, `OffsetPaginator`), DBAL 4 types, PHPUnit 12/13, PHPStan 2, Foundry 2.

### Fixes in existing skills
- Agents: the Domain dependency `grep` patterns never matched anything (escaping bug); all checks rewritten and tested.
- API: domain exceptions thrown in Messenger handlers became HTTP 500 (wrapped in `HandlerFailedException`); the subscriber and new `CommandBus`/`QueryBus` wrappers unwrap them. `#[MapRequestPayload]` violations are formatted; 5xx messages no longer leak in production; no more 204 responses with a body.
- Controllers used `json_decode` + `Request`, and one example returned the `Envelope` as the user ID; all use `#[MapRequestPayload]` / bus wrappers now.
- A query example used native SQL (violating the plugin's own rule) and a Domain port imported an Application DTO; replaced by Domain read models, generic `Page<T>` and DBAL QueryBuilder.
- Domain events were dispatched inside the command transaction; repositories now use `DispatchAfterCurrentBusStamp`.
- Doctrine XML: comment before `<?xml ?>` (invalid), `enumType` instead of `enum-type`, file names not matching DoctrineBundle's prefix convention, `OrderItem` mapping without matching domain properties, custom type using DBAL 4-removed `getName()`.
- Security: voter used non-existent `UserInterface::getId()` and ignored the role hierarchy; entity user provider pointed to an unmapped class; voters now receive IDs and use read ports.
- Validation: custom constraint used the option-array style removed in Symfony 8 and lived in Presentation while importing a Domain port.
- Messenger/Scheduler: idempotency key fell back to `uniqid()`; scheduler transports were declared manually; schedules now stateful + locked.
- Testing: PHPUnit `<coverage>` config replaced by `<source>`; PHPStan 2-incompatible parameter removed; Foundry 1 `ModelFactory` replaced; stubs vs mocks for PHPUnit 13; handler tests matched handler constructors.
- Domain: ID generation and password hashing moved behind ports (no `uuid_create()` / Symfony hasher in Domain/Application).
- All `SKILL.md` files now declare `name`; descriptions rewritten for better auto-activation.

## 1.1.0
- No-native-SQL rule: QueryBuilder/DQL only, migrations excepted.

## 1.0.0
- Initial skills and agents.
