#!/usr/bin/env bash
# SessionStart hook: inject the hexagonal architecture rules, but only in Symfony projects.
# Also reports the detected stack versions so skills can generate version-compatible code.

project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
composer_json="$project_dir/composer.json"
composer_lock="$project_dir/composer.lock"

# Not a Symfony project: stay silent so the plugin never affects unrelated repos.
[ -f "$composer_json" ] || exit 0
grep -Eq '"symfony/(framework-bundle|http-kernel|console)"' "$composer_json" || exit 0

# Print the installed version of a package from composer.lock (empty if missing).
pkg_version() {
    [ -f "$composer_lock" ] || return 0
    awk -v pkg="\"name\": \"$1\"" '
        index($0, pkg) { found = 1; next }
        found && /"version":/ { sub(/.*"version": *"v?/, ""); sub(/".*/, ""); print; exit }
    ' "$composer_lock"
}

php_constraint="$(grep -o '"php": *"[^"]*"' "$composer_json" | head -n1 | sed 's/.*: *"\(.*\)"/\1/')"
symfony="$(pkg_version symfony/framework-bundle)"
[ -n "$symfony" ] || symfony="$(pkg_version symfony/http-kernel)"

cat "${CLAUDE_PLUGIN_ROOT}/rules/hexagonal-rules.md"

echo
echo "## Detected Stack (from composer.json / composer.lock)"
echo
echo "- Symfony: ${symfony:-unknown (no composer.lock, read composer.json constraints)}"
echo "- PHP constraint: ${php_constraint:-unknown}"
for pkg in doctrine/orm doctrine/dbal doctrine/doctrine-bundle phpunit/phpunit phpstan/phpstan symfony/scheduler symfony/object-mapper; do
    v="$(pkg_version "$pkg")"
    [ -n "$v" ] && echo "- $pkg: $v"
done
echo
echo "Generate code that is valid for THESE versions. Consult the compatibility matrix in the"
echo "symfony-hexagonal-architecture skill (references/version-compatibility.md) before using any"
echo "feature marked with a minimum version; fall back to the documented alternative when the project is older."
exit 0
