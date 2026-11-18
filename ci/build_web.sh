#!/usr/bin/env bash
# Изгражда сайта от папка с кода.  ci/build_web.sh <папка> <base-href> <номер>
# Нужни са SUPABASE_URL и SUPABASE_PUBLISHABLE_KEY в средата.
set -euo pipefail
SRC="$1"; BASE="$2"; NUM="$3"
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$SRC"
flutter create . --platforms=web --org bg.kairos --project-name kairos >/dev/null
rm -f test/widget_test.dart
sed -i 's#<title>[^<]*</title>#<title>Кайрос</title>#' web/index.html
sed -i 's#name="apple-mobile-web-app-title" content="[^"]*"#name="apple-mobile-web-app-title" content="Кайрос"#' web/index.html
sed -i 's#name="apple-mobile-web-app-status-bar-style" content="[^"]*"#name="apple-mobile-web-app-status-bar-style" content="black-translucent"#' web/index.html
sed -i 's#href="icons/Icon-192.png"#href="icons/apple-touch-icon.png"#' web/index.html
# Иконките на Кайрос (началният екран на телефона, разделът в браузъра)
if [ -d "$HERE/web_icons" ]; then
  cp "$HERE"/web_icons/Icon-*.png "$HERE"/web_icons/apple-touch-icon.png web/icons/
  cp "$HERE"/web_icons/favicon.png web/favicon.png
fi
python3 - <<'PY'
import json
p = 'web/manifest.json'
m = json.load(open(p))
m.update(name='Кайрос', short_name='Кайрос', description='Кайрос – приложение за свещеници',
         background_color='#12161C', theme_color='#12161C')
json.dump(m, open(p, 'w'), ensure_ascii=False, indent=2)
PY
flutter pub get >/dev/null
flutter build web --release --base-href "$BASE" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY" \
  --dart-define=BUILD_NUMBER="$NUM" \
  --dart-define=TEST_BUILD=true
