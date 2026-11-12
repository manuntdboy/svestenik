#!/usr/bin/env bash
# Пуска всички миграции и теста на базата върху празна PostgreSQL.
# Връзката е през обичайните PGHOST, PGPORT, PGUSER (и PGPASSWORD).
set -euo pipefail
cd "$(dirname "$0")/.."
DB=kairos_test_$$
psql -d postgres -q -c "drop database if exists $DB" -c "create database $DB"
cleanup() { psql -d postgres -q -c "drop database if exists $DB" >/dev/null 2>&1 || true; }
trap cleanup EXIT
psql -d "$DB" -q -v ON_ERROR_STOP=1 -f supabase/tests/stub.sql
for m in supabase/migrations/*.sql; do
  psql -d "$DB" -q -v ON_ERROR_STOP=1 -f "$m" 2>&1 | { grep -v NOTICE || true; }
  echo "приложено: $(basename "$m")"
done
psql -d "$DB" -v ON_ERROR_STOP=1 -f supabase/tests/rls_test.sql 2>&1 \
  | sed -e 's/^psql:[^:]*:[0-9]*: //' -e 's/^NOTICE:  //'
