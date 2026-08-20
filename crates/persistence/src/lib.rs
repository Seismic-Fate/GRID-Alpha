//! `grid-persistence` — SQLx, migrations, SQLite. No business logic.
//!
//! Crate boundary is defined in `docs/CLAUDE.md`; see `docs/02-adr/001-repo-bootstrap-decisions.md`.
//!
//! P1-00 establishes only the SQLx toolchain: one infrastructure table, one
//! compile-time-checked query, and the committed offline cache (ADR-002).
//! The durable domain schema is P1-02.

use sqlx::SqlitePool;

/// Key under which the migration bootstrap revision is recorded in `schema_meta`.
pub const SCHEMA_VERSION_KEY: &str = "schema_version";

/// Reads a value from the `schema_meta` table, or `None` when the key is absent.
///
/// Errors are returned as typed [`sqlx::Error`]; a missing key is a legitimate
/// `Ok(None)` and is never conflated with a failure (alpha-spec.md 12.7).
pub async fn schema_meta_value(
    pool: &SqlitePool,
    key: &str,
) -> Result<Option<String>, sqlx::Error> {
    let row = sqlx::query!("SELECT value FROM schema_meta WHERE key = ?", key)
        .fetch_optional(pool)
        .await?;
    Ok(row.map(|record| record.value))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[sqlx::test(migrations = "../../migrations")]
    async fn migrations_apply_to_a_blank_database(pool: SqlitePool) {
        let value = schema_meta_value(&pool, SCHEMA_VERSION_KEY)
            .await
            .expect("query against a freshly migrated database should succeed");
        assert_eq!(value.as_deref(), Some("0001"));
    }

    #[sqlx::test(migrations = "../../migrations")]
    async fn absent_key_is_none_not_an_error(pool: SqlitePool) {
        let value = schema_meta_value(&pool, "no-such-key")
            .await
            .expect("querying an absent key is not a failure");
        assert!(value.is_none());
    }
}
