#!/usr/bin/env bats
load test_helper/common-setup

setup() { _common_setup; }
teardown() { _common_teardown; }

@test "db_init creates database file" {
  run bash "$PROJECT_ROOT/shared/tools/db-utils.sh" init
  assert_success
  assert_output "OK"
  [ -f "$SPECTRA_HOME/spectra.db" ]
}

@test "db_init creates sessions table with correct columns" {
  bash "$PROJECT_ROOT/shared/tools/db-utils.sh" init

  run bash "$PROJECT_ROOT/shared/tools/db-utils.sh" query \
    "SELECT sql FROM sqlite_master WHERE type='table' AND name='sessions'"
  assert_success
  assert_output --partial "session_id TEXT PRIMARY KEY"
  assert_output --partial "skill TEXT NOT NULL"
  assert_output --partial "tier TEXT NOT NULL"
  assert_output --partial "specialist_count INTEGER DEFAULT 0"
  assert_output --partial "convergence_rate REAL"
}

@test "db_init creates schema_migrations table" {
  bash "$PROJECT_ROOT/shared/tools/db-utils.sh" init

  run bash "$PROJECT_ROOT/shared/tools/db-utils.sh" query \
    "SELECT sql FROM sqlite_master WHERE type='table' AND name='schema_migrations'"
  assert_success
  assert_output --partial "version INTEGER PRIMARY KEY"
  assert_output --partial "applied_at TEXT NOT NULL"
}

@test "WAL mode enabled after init" {
  bash "$PROJECT_ROOT/shared/tools/db-utils.sh" init

  run python3 -c "
import sqlite3, os
conn = sqlite3.connect(os.environ['HOME'] + '/.spectra/spectra.db')
mode = conn.execute('PRAGMA journal_mode').fetchone()[0]
print(mode)
conn.close()
"
  assert_success
  assert_output "wal"
}

@test "file permissions are 0600" {
  bash "$PROJECT_ROOT/shared/tools/db-utils.sh" init

  local perms
  perms="$(stat -f '%Lp' "$SPECTRA_HOME/spectra.db" 2>/dev/null || stat -c '%a' "$SPECTRA_HOME/spectra.db" 2>/dev/null)"
  [ "$perms" = "600" ]
}

@test "db_init is idempotent" {
  run bash "$PROJECT_ROOT/shared/tools/db-utils.sh" init
  assert_success
  run bash "$PROJECT_ROOT/shared/tools/db-utils.sh" init
  assert_success
  assert_output "OK"

  # Only one migration row
  run bash "$PROJECT_ROOT/shared/tools/db-utils.sh" query \
    "SELECT COUNT(*) as cnt FROM schema_migrations WHERE version = 1"
  assert_success
  assert_output --partial '"cnt": 1'
}

@test "db_execute inserts a session row" {
  bash "$PROJECT_ROOT/shared/tools/db-utils.sh" init

  run bash "$PROJECT_ROOT/shared/tools/db-utils.sh" execute \
    "INSERT INTO sessions (session_id, skill, tier) VALUES (?, ?, ?)" \
    "test-001" "deep-design" "standard"
  assert_success
  assert_output "OK"

  run bash "$PROJECT_ROOT/shared/tools/db-utils.sh" query \
    "SELECT session_id, skill, tier FROM sessions WHERE session_id = ?" \
    "test-001"
  assert_success
  assert_output --partial '"session_id": "test-001"'
  assert_output --partial '"skill": "deep-design"'
}

@test "db_query returns JSON array of results" {
  bash "$PROJECT_ROOT/shared/tools/db-utils.sh" init
  bash "$PROJECT_ROOT/shared/tools/db-utils.sh" execute \
    "INSERT INTO sessions (session_id, skill, tier) VALUES (?, ?, ?)" \
    "s1" "deep-design" "quick"
  bash "$PROJECT_ROOT/shared/tools/db-utils.sh" execute \
    "INSERT INTO sessions (session_id, skill, tier) VALUES (?, ?, ?)" \
    "s2" "decision-board" "deep"

  run bash "$PROJECT_ROOT/shared/tools/db-utils.sh" query \
    "SELECT session_id FROM sessions ORDER BY session_id"
  assert_success

  # Validate it's a JSON array with 2 elements
  run python3 -c "
import json, sys
data = json.loads(sys.argv[1])
assert isinstance(data, list), 'not a list'
assert len(data) == 2, f'expected 2, got {len(data)}'
print('OK')
" "$output"
  assert_success
  assert_output "OK"
}

@test "db_query with parameters filters correctly" {
  bash "$PROJECT_ROOT/shared/tools/db-utils.sh" init
  bash "$PROJECT_ROOT/shared/tools/db-utils.sh" execute \
    "INSERT INTO sessions (session_id, skill, tier) VALUES (?, ?, ?)" \
    "s1" "deep-design" "quick"
  bash "$PROJECT_ROOT/shared/tools/db-utils.sh" execute \
    "INSERT INTO sessions (session_id, skill, tier) VALUES (?, ?, ?)" \
    "s2" "decision-board" "deep"

  run bash "$PROJECT_ROOT/shared/tools/db-utils.sh" query \
    "SELECT session_id FROM sessions WHERE skill = ?" "deep-design"
  assert_success
  assert_output --partial '"s1"'
  refute_output --partial '"s2"'
}

@test "parameterized queries handle special characters" {
  bash "$PROJECT_ROOT/shared/tools/db-utils.sh" init

  # Attempt SQL injection as a value — should be safely parameterized
  run bash "$PROJECT_ROOT/shared/tools/db-utils.sh" execute \
    "INSERT INTO sessions (session_id, skill, tier) VALUES (?, ?, ?)" \
    "'; DROP TABLE sessions; --" "deep-design" "standard"
  assert_success

  # Table should still exist with the injected string as a literal value
  run bash "$PROJECT_ROOT/shared/tools/db-utils.sh" query \
    "SELECT session_id FROM sessions"
  assert_success
  assert_output --partial "DROP TABLE"
}

@test "db_check_integrity passes on valid database" {
  bash "$PROJECT_ROOT/shared/tools/db-utils.sh" init

  run bash "$PROJECT_ROOT/shared/tools/db-utils.sh" integrity
  assert_success
  assert_output --partial '"integrity": "ok"'
  assert_output --partial '"schema_version": 1'
}

@test "db_check_integrity fails on corrupted database" {
  bash "$PROJECT_ROOT/shared/tools/db-utils.sh" init

  # Corrupt the database by overwriting with garbage
  echo "corrupt data" > "$SPECTRA_HOME/spectra.db"

  run bash "$PROJECT_ROOT/shared/tools/db-utils.sh" integrity
  assert_failure
}

@test "schema version 1 is tracked in schema_migrations after init" {
  bash "$PROJECT_ROOT/shared/tools/db-utils.sh" init

  run bash "$PROJECT_ROOT/shared/tools/db-utils.sh" query \
    "SELECT version, description FROM schema_migrations WHERE version = 1"
  assert_success
  assert_output --partial '"version": 1'
  assert_output --partial "Initial schema"
}

@test "db_query on empty table returns empty JSON array" {
  bash "$PROJECT_ROOT/shared/tools/db-utils.sh" init

  run bash "$PROJECT_ROOT/shared/tools/db-utils.sh" query \
    "SELECT * FROM sessions"
  assert_success
  assert_output "[]"
}

@test "db_execute with wrong column count fails gracefully" {
  bash "$PROJECT_ROOT/shared/tools/db-utils.sh" init

  # 3 placeholders but only 2 params
  run bash "$PROJECT_ROOT/shared/tools/db-utils.sh" execute \
    "INSERT INTO sessions (session_id, skill, tier) VALUES (?, ?, ?)" \
    "s1" "deep-design"
  assert_failure
  assert_output --partial "ERROR"
}

@test "db_query on nonexistent database returns empty array" {
  # Don't run init — database doesn't exist
  run bash "$PROJECT_ROOT/shared/tools/db-utils.sh" query \
    "SELECT * FROM sessions"
  assert_success
  assert_output "[]"
}

@test "DB_PATH env var overrides default database location" {
  export DB_PATH="$TEST_TEMP/custom.db"

  run bash "$PROJECT_ROOT/shared/tools/db-utils.sh" init
  assert_success
  [ -f "$TEST_TEMP/custom.db" ]
  [ ! -f "$SPECTRA_HOME/spectra.db" ]
}
