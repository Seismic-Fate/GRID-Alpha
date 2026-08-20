-- P1-00 / ADR-002: infrastructure-only bootstrap table.
--
-- This exists so the SQLx toolchain (migrations, compile-time-checked queries,
-- committed offline cache) is proven end-to-end from the first work package,
-- per final-build-spec.md 8.2: "Use `sqlx migrate` from day one."
--
-- It is deliberately NOT a domain table. Games, teams, players, drives, plays,
-- raw_data, jobs, model_versions and every other domain schema group remain
-- P1-02's scope (alpha-spec.md 8.5, 9.5).
--
-- Migrations are append-only from here; enforced by scripts/check-migrations.sh.

CREATE TABLE schema_meta (
    key   TEXT PRIMARY KEY NOT NULL,
    value TEXT NOT NULL
);

INSERT INTO schema_meta (key, value) VALUES ('schema_version', '0001');
