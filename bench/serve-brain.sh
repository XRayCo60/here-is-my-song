#!/bin/bash
# ---------------------------------------------------------------------------
# serve-brain — مغز دائمی (بند ۴۲)
#
# همان یک مغز، برای همیشه:
#   · بار اول (بدون brain.dat): تولد — شناسنامه در brain.birth ثبت می‌شود
#   · بعد از آن: ادامه‌ی همان مغز با --load brain.dat
#   · ذخیره‌ی خودکار هر ۶۰۰ ثانیه‌ی مجازی (--autosave 600)
#   · داشبورد روی 0.0.0.0:8420 — از لپ‌تاپ: http://<IP-سرور>:8420
#
# سرویس systemd این اسکریپت را اجرا می‌کند (bench/install-service.sh).
# بذر فقط روز تولد معنا دارد؛ بعد از آن مغز از چک‌پوینت ادامه می‌یابد.
#
# متغیرها: NEURONS (۳۲۰۰۰) · PORT (۸۴۲۰) · SEED (۱۲۳۴۵، فقط روز تولد)
# ---------------------------------------------------------------------------
set -u
cd "$(dirname "$0")/.."

NEURONS=${NEURONS:-32000}
PORT=${PORT:-8420}
SEED=${SEED:-12345}

BIN=./bench/smile-bench
if [ ! -x "$BIN" ]; then
  echo "[serve-brain] بیلد: $BIN"
  g++ -O2 -march=native -std=c++17 -pthread smile.cpp -o "$BIN" || exit 1
fi

FLAGS="--neurons $NEURONS --seed $SEED --port $PORT --no-browser \
  --teacher-strength 60 --holdout 10 --talk 400 \
  --silence --mutate --sprout 5 --autosave 600"

if [ -f brain.dat ]; then
  echo "[serve-brain] ادامه‌ی مغز موجود — brain.dat"
  exec "$BIN" $FLAGS --load brain.dat
else
  echo "[serve-brain] تولد مغز تازه — شناسنامه در brain.birth"
  exec "$BIN" $FLAGS
fi
