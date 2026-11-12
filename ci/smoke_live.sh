#!/usr/bin/env bash
# Безопасна проверка на живия Supabase: само заявки без вход или с грешни
# данни. Не създава и не променя нищо.
# Нужни: SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY
set -uo pipefail
: "${SUPABASE_URL:?}" "${SUPABASE_PUBLISHABLE_KEY:?}"
fail=0
check() { # име, очакван код, действителен код, [тяло, очакван текст]
  local name=$1 want=$2 got=$3 body=${4:-} needle=${5:-}
  if [[ "$got" == "$want" && ( -z "$needle" || "$body" == *"$needle"* ) ]]; then
    echo "OK  $name ($got)"
  else
    echo "FAIL $name: очаквано $want${needle:+ с „$needle“}, получено $got: ${body:0:200}"
    fail=1
  fi
}
req() { # метод, път, [тяло], [допълнителни заглавки…]
  local method=$1 path=$2 data=${3:-}; shift 3 || shift $#
  local out
  out=$(curl -sS -m 30 -X "$method" "$SUPABASE_URL$path" \
    -H "apikey: $SUPABASE_PUBLISHABLE_KEY" -H "Content-Type: application/json" "$@" \
    ${data:+--data "$data"} -w $'\n%{http_code}')
  BODY=${out%$'\n'*}; CODE=${out##*$'\n'}
}

req POST /functions/v1/login '{"username":"__kairos_smoke__","password":"wrong"}'
check "вход с непознато име се отказва" 401 "$CODE" "$BODY" wrong_credentials

req POST /functions/v1/login '{}'
check "вход без данни се отказва" 400 "$CODE" "$BODY" bad_request

req POST /functions/v1/notify '{"type":"event","event_id":"x"}'
check "известия без вход се отказват" 401 "$CODE" "$BODY" not_authenticated

req POST /rest/v1/rpc/username_available '{"p_username":"__kairos_smoke__"}'
check "проверка за свободно име работи без вход" 200 "$CODE" "$BODY" true

for table in events profiles churches church_members profile_details device_tokens; do
  req GET "/rest/v1/$table?select=*&limit=1" ''
  check "без вход таблица $table е празна" 200 "$CODE" "$BODY" '[]'
done

req POST /rest/v1/rpc/create_church '{"p_name":"X","p_settlement":"Y","p_municipality":"Z"}'
[[ "$CODE" == 401 || "$CODE" == 403 || "$CODE" == 404 ]] && echo "OK  без вход не се създава храм ($CODE)" \
  || { echo "FAIL без вход създаване на храм: $CODE $BODY"; fail=1; }

req GET /storage/v1/object/public/avatars/__smoke__.jpg ''
[[ "$CODE" == 400 || "$CODE" == 404 ]] && echo "OK  снимките не са публични ($CODE)" \
  || { echo "FAIL снимките изглеждат публични: $CODE"; fail=1; }

exit $fail
