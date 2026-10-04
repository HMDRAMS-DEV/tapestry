#!/bin/zsh
# Renders the README banner in light and dark with headless Chrome.
#
#     scripts/render-banner.sh
set -euo pipefail

cd "$(dirname "$0")/.."
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
page="file://$PWD/scripts/readme-banner.html"

for theme in light dark; do
  "$chrome" --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 \
    --force-device-scale-factor=2 --window-size=1280,640 --virtual-time-budget=4000 \
    --allow-file-access-from-files --screenshot="$PWD/docs/banner-$theme.png" "$page?$theme" 2>/dev/null
done
echo "Wrote docs/banner-light.png and docs/banner-dark.png"
