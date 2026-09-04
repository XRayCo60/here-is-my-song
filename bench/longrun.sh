#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  ران بلند قطعه‌قطعه — منحنی یادگیری در طول زمان
#
#  مغز را در چند قطعه‌ی پشت‌سرهم اجرا می‌کند و بین قطعه‌ها از چک‌پوینت
#  ادامه می‌دهد. خروجی هر قطعه یک خط RESULT است؛ با کنار هم گذاشتنشان
#  منحنی «آیا با گذر زمان بهتر می‌شود؟» ساخته می‌شود.
#
#  استفاده:
#     bench/longrun.sh [SEED] [SEGS] [SEG_SECS] [NEURONS]
#  مثال — ۳ ساعت مجازی (۹ قطعه‌ی ۲۰ دقیقه‌ای):
#     bench/longrun.sh 1 9 1200 1000
#
#  فلگ‌ها با متغیر محیطی FLAGS (پیش‌فرض: درد خالص — بند ۳۷؛ teach-feed حذف شد،
#  مغز نباید واژه‌ها را بشنود، باید با درد کشفشان کند):
#     FLAGS='--silence --mutate --sprout 5' bench/longrun.sh 1 9 1200 1000
# ---------------------------------------------------------------------------
set -u
cd "$(dirname "$0")/.."

SEED=${1:-1}
SEGS=${2:-9}
SECS=${3:-1200}
NEUR=${4:-1000}
STRENGTH=${STRENGTH:-60}
HOLDOUT=${HOLDOUT:-10}
TALK=${TALK:-400}
FLAGS=${FLAGS:---silence --mutate --sprout 5}

BIN=${BIN:-./bench/smile-bench}
if [ ! -x "$BIN" ]; then
  echo "build: $BIN"
  g++ -O2 -std=c++17 -pthread smile.cpp -o "$BIN" || exit 1
fi
# BIN باید مطلق باشد — زیر‌پوسته به پوشه‌ی موقت cd می‌کند
case $BIN in /*) ;; *) BIN="$PWD/$BIN" ;; esac

d=$(mktemp -d)
echo "seed=$SEED segs=$SEGS x${SECS}s neurons=$NEUR flags=[$FLAGS] strength=$STRENGTH"
for ((i=0; i<SEGS; i++)); do
  LOAD=""
  [ "$i" -gt 0 ] && LOAD="--load $d/brain.dat"
  ( cd "$d" && "$BIN" --neurons "$NEUR" --headless "$SECS" --seed "$SEED" \
      --teacher-strength "$STRENGTH" --holdout "$HOLDOUT" --talk "$TALK" $LOAD $FLAGS \
      --words "$OLDPWD/persian_words.tsv" --user-words "$OLDPWD/my_words.tsv" \
      --no-browser 2>/dev/null ) | grep '^RESULT' | sed "s/^RESULT /seg=$i /"
done
rm -rf "$d"
