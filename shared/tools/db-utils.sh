#!/usr/bin/env bash
# db-utils.sh — SQLite database utility for cross-session metadata
# Usage: bash db-utils.sh <command> [args...]
# No external dependencies beyond python3 (available on macOS and most Linux).

set -euo pipefail

DB_PATH="${DB_PATH:-$HOME/.spectra/spectra.db}"

usage() {
  cat <<'EOF'
Usage: bash db-utils.sh <command> [args...]

Commands:
  init                              Create database with schema (idempotent)
  query <sql> [param...]            Run SELECT, return JSON array
  execute <sql> [param...]          Run INSERT/UPDATE/DELETE
  integrity                         Check database integrity and schema version
EOF
  exit 1
}

[ $# -lt 1 ] && usage
COMMAND="$1"
shift

case "$COMMAND" in
  init)
    mkdir -p "$(dirname "$DB_PATH")"
    python3 -c "
import sqlite3, os, datetime

db_path = os.environ.get('DB_PATH', os.path.expanduser('~/.spectra/spectra.db'))
conn = sqlite3.connect(db_path)
conn.execute('PRAGMA journal_mode=WAL')
conn.execute('''CREATE TABLE IF NOT EXISTS sessions (
  session_id TEXT PRIMARY KEY,
  skill TEXT NOT NULL,
  project TEXT,
  tier TEXT NOT NULL,
  agent_count INTEGER,
  specialist_count INTEGER DEFAULT 0,
  quality TEXT,
  duration_seconds INTEGER,
  feedback_rating TEXT,
  has_handoff INTEGER DEFAULT 0,
  session_dirname TEXT,
  started_at TEXT,
  completed_at TEXT,
  completion_rate REAL,
  phase_completion_rate REAL,
  security_violations_count INTEGER,
  topics_total INTEGER,
  topics_resolved INTEGER,
  convergence_rate REAL,
  specialist_utilization REAL,
  escalations_count INTEGER,
  concessions_count INTEGER,
  consensus_strength REAL,
  rounds_debated INTEGER
)''')
conn.execute('''CREATE TABLE IF NOT EXISTS schema_migrations (
  version INTEGER PRIMARY KEY,
  applied_at TEXT NOT NULL,
  description TEXT
)''')
now = datetime.datetime.now(datetime.timezone.utc).isoformat()
cursor = conn.execute('SELECT COUNT(*) FROM schema_migrations WHERE version = 1')
if cursor.fetchone()[0] == 0:
    conn.execute(
        'INSERT INTO schema_migrations (version, applied_at, description) VALUES (?, ?, ?)',
        (1, now, 'Initial schema: sessions + schema_migrations')
    )
cursor = conn.execute('SELECT COUNT(*) FROM schema_migrations WHERE version = 2')
if cursor.fetchone()[0] == 0:
    conn.execute(
        'INSERT INTO schema_migrations (version, applied_at, description) VALUES (?, ?, ?)',
        (2, now, 'Phase 2: context budget events, quality KPIs — event schema 1.1.0')
    )
conn.commit()
conn.close()
os.chmod(db_path, 0o600)
print('OK')
"
    ;;

  query)
    SQL="${1:?Missing SQL argument}"
    shift
    DB_PATH="$DB_PATH" SQL="$SQL" python3 -c "
import sqlite3, json, sys, os

db_path = os.environ['DB_PATH']
if not os.path.isfile(db_path):
    print('[]')
    sys.exit(0)

sql = os.environ['SQL']
params = sys.argv[1:]
conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
cursor = conn.execute(sql, params)
rows = [dict(row) for row in cursor.fetchall()]
conn.close()
print(json.dumps(rows))
" "$@"
    ;;

  execute)
    SQL="${1:?Missing SQL argument}"
    shift
    DB_PATH="$DB_PATH" SQL="$SQL" python3 -c "
import sqlite3, sys, os

db_path = os.environ['DB_PATH']
if not os.path.isfile(db_path):
    print('ERROR: database not initialized (run: bash db-utils.sh init)', file=sys.stderr)
    sys.exit(1)

sql = os.environ['SQL']
params = sys.argv[1:]
conn = sqlite3.connect(db_path)
try:
    conn.execute(sql, params)
    conn.commit()
    print('OK')
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
finally:
    conn.close()
" "$@"
    ;;

  integrity)
    DB_PATH="$DB_PATH" python3 -c "
import sqlite3, json, sys, os

db_path = os.environ['DB_PATH']
if not os.path.isfile(db_path):
    print('ERROR: database not found', file=sys.stderr)
    sys.exit(1)

conn = sqlite3.connect(db_path)

# Integrity check
result = conn.execute('PRAGMA integrity_check').fetchone()[0]
if result != 'ok':
    print(f'INTEGRITY FAIL: {result}', file=sys.stderr)
    conn.close()
    sys.exit(1)

# Schema version
cursor = conn.execute('SELECT MAX(version) FROM schema_migrations')
version = cursor.fetchone()[0]
conn.close()

if version is None:
    print('ERROR: no schema version found', file=sys.stderr)
    sys.exit(1)

print(json.dumps({'integrity': 'ok', 'schema_version': version}))
"
    ;;

  *)
    echo "Unknown command: $COMMAND" >&2
    usage
    ;;
esac
