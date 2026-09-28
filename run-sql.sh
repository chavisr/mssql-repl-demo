#!/usr/bin/env bash
# Run one numbered lab script against its managed-service endpoint.
set -euo pipefail

if [[ $# != 1 ]]; then
  echo "Usage: $0 <01..07>" >&2
  exit 2
fi

case "$1" in
  01) script=01_setup_publisher_distributor.sql; role=MI ;;
  02) script=02_setup_subscriber_db.sql; role=RDS ;;
  03) script=03_create_subscription.sql; role=MI ;;
  04) script=04_validate_on_publisher.sql; role=MI ;;
  05) script=05_check_subscriber.sql; role=RDS ;;
  06) script=06_test_edge_cases_on_publisher.sql; role=MI ;;
  07) script=07_check_subscriber_after_tests.sql; role=RDS ;;
  *) echo 'Choose a script number from 01 through 07.' >&2; exit 2 ;;
esac

require() {
  local name
  for name in "$@"; do
    if [[ -z ${!name:-} || ${!name} == *CHANGE_ME* || ${!name} == *$'\n'* || ${!name} == *$'\r'* ]]; then
      echo "Set $name to a nonempty, single-line value before running this script." >&2
      exit 2
    fi
  done
}

# SQLCMD substitution is textual. Escape apostrophes before use in N'...' literals.
sql_literal() {
  local name=$1 value=${!1}
  printf -v "${name}_SQL" '%s' "${value//\'/\'\'}"
  export "${name}_SQL"
}

require "${role}_SERVER" "${role}_LOGIN" "${role}_PASSWORD"
case "$1" in
  01)
    require MI_LOGIN MI_PASSWORD SNAPSHOT_SHARE STORAGE_CONNECTION_STRING DISTRIBUTION_KEY_PASSWORD
    for name in MI_LOGIN MI_PASSWORD SNAPSHOT_SHARE STORAGE_CONNECTION_STRING DISTRIBUTION_KEY_PASSWORD; do
      sql_literal "$name"
    done
    ;;
  03)
    require MI_LOGIN MI_PASSWORD RDS_SERVER RDS_LOGIN RDS_PASSWORD
    for name in MI_LOGIN MI_PASSWORD RDS_SERVER RDS_LOGIN RDS_PASSWORD; do
      sql_literal "$name"
    done
    ;;
esac

server_var=${role}_SERVER
login_var=${role}_LOGIN
password_var=${role}_PASSWORD
export SQLCMDPASSWORD=${!password_var}
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
args=(-S "${!server_var}" -U "${!login_var}" -N -l 30)
# Script 06 intentionally rejects TRUNCATE, then continues with the remaining tests.
if [[ $1 != 06 ]]; then args+=(-b); fi
exec sqlcmd "${args[@]}" -i "$script_dir/$script"
