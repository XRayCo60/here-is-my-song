#!/bin/bash
# ---------------------------------------------------------------------------
# multirun — چند مغز هم‌زمان روی سرور چندهسته‌ای (بند ۳۸/۴۱)
#
# هر بذر یک فرایند مستقل با استخر کارگر خودش (--threads) و زنجیره‌ی
# brain.dat خودش در پوشه‌ی موقت خودش — کاملاً تکرارپذیر و قابل مقایسه
# با ران‌های تک‌بذری قبلی.
#
# مثال‌ها:
#   bench/multirun.sh 1 2 3 4                 # ۴ مغز × ۶ نخ، ۹×۱۲۰۰s، ۳۲k نورون
#   THREADS=12 SEGS=3 SECS=600 bench/multirun.sh 1 2   # تست سریع شب اول
#   NEURONS=100000 bench/multirun.sh 1        # محور مقیاس
#
# متغیرها: THREADS (نخِ هر مغز، پیش‌فرض ۶) · NEURONS (۳۲۰۰۰) · SEGS (۹) ·
#          SECS (۱۲۰۰) · STRENGTH (۶۰) · FLAGS (پیش‌فرض: درد خالص بند ۳۷)
# خروجی: multirun_seed<N>.txt برای هر بذر + جدول خلاصه در پایان
# ---------------------------------------------------------------------------
set -u
cd "$(dirname "$0")/.."

SEEDS=("$@")
[ ${#SEEDS[@]} -ge 1 ] || { echo "usage: bench/multirun.sh SEED [SEED...]" >&2; exit 1; }

THREADS=${THREADS:-6}
NEURONS=${NEURONS:-32000}
SEGS=${SEGS:-9}
SECS=${SECS:-1200}
STRENGTH=${STRENGTH:-60}
BASE_FLAGS=${FLAGS:---silence --mutate --sprout 5}

# بیلد مشترک — یک بار، قبل از اینکه فرایندها هم‌زمان سراغش بروند
BIN=./bench/smile-bench
if [ ! -x "$BIN" ]; then
  echo "build: $BIN"
  g++ -O2 -std=c++17 -pthread -march=native smile.cpp -o "$BIN" || exit 1
fi

N=${#SEEDS[@]}
echo "multirun: $N مغز × $THREADS نخ × $NEURONS نورون · $SEGS×${SECS}s · flags=[$BASE_FLAGS]"
pids=()
for s in "${SEEDS[@]}"; do
  LOG="multirun_seed$s.txt"
  echo "seed=$s → $LOG"
  FLAGS="--threads $THREADS $BASE_FLAGS" STRENGTH="$STRENGTH" \
    bench/longrun.sh "$s" "$SEGS" "$SECS" "$NEURONS" > "$LOG" 2>&1 &
  pids+=($!)
done
rc=0
for i in "${!pids[@]}"; do
  wait "${pids[$i]}" || { echo "seed=${SEEDS[$i]} FAILED" >&2; rc=1; }
done

python3 - "$@" <<'PY'
import re, sys
print(f"\n{'seed':>4} {'words':>6} {'exact%':>7} {'avgQ':>6} {'distinct':>8}")
for seed in sys.argv[1:]:
    ws=[]; exs=[]; qs=[]; ds=[]
    try: lines = open(f"multirun_seed{seed}.txt").read().splitlines()
    except FileNotFoundError: continue
    for L in lines:
        m = re.search(r'words=(\d+) exact=\d+ exactpct=([\d.]+).*?avgQ=([\d.]+).*?distinct=(\d+)', L)
        if m:
            ws.append(int(m.group(1))); exs.append(float(m.group(2)))
            qs.append(float(m.group(3))); ds.append(int(m.group(4)))
    if ws:
        n=len(ws)
        print(f"{seed:>4} {sum(ws)/n:6.0f} {sum(exs)/n:7.2f} {sum(qs)/n:6.1f} {sum(ds)/n:8.0f}")
    else:
        print(f"{seed:>4}  — بدون RESULT")
PY
exit $rc
