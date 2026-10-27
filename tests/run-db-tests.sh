#!/usr/bin/env bash
# Ajaa tietokantatestit paikallisessa Docker-ympäristössä.
#   bash tests/run-db-tests.sh          # käynnistää ympäristön tarvittaessa ja ajaa testit
#   bash tests/run-db-tests.sh --fresh  # luo kannan alusta (migraatio ajetaan uudelleen)
set -euo pipefail
cd "$(dirname "$0")/.."
COMPOSE="docker compose -f tests/local/docker-compose.yml"
if [[ "${1:-}" == "--fresh" ]]; then
  $COMPOSE down -v >/dev/null 2>&1 || true
fi
$COMPOSE up -d --wait >/dev/null 2>&1
MSYS_NO_PATHCONV=1 $COMPOSE exec -T db psql -U postgres -v ON_ERROR_STOP=1 -f /tests/booking_rules_test.sql 2>&1 \
  | sed -E 's/^psql:[^ ]+ (NOTICE|ERROR):  /\1: /; s/^NOTICE: //'
