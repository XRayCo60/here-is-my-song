#!/bin/bash
# ---------------------------------------------------------------------------
# gpu-validate — اندازه‌گیری واقعی سرعت GPU در برابر CPU (پیش‌نیاز پورت کامل)
#
#   STOP_SERVICE=1 bash bench/gpu-validate.sh
#
# چه می‌کند:
#   ۱) CPU مرجع: همان مغز ۳۲هزارتایی با فلگ‌های سرویس، یک‌بار تک‌نخ و یک‌بار
#      همه‌ی نخ‌ها → «ثانیه‌ی مجازی به ازای ثانیه‌ی واقعی»
#   ۲) GPU: هسته‌ی اعتبارسنجی (موتور محرک) روی هر کارت → همان واحد
#   ۳) جدول مقایسه — این اعداد تصمیم معماری پورت کامل را می‌گیرند
#
# متغیرها: SECS (۱۲۰) · NEURONS (۳۲۰۰۰) · ARCH (خودکار از compute_cap)
#          CPU_ONLY=1 (فقط مرجع CPU) · STOP_SERVICE=1 (توقف موقت سرویس برای
#          اندازه‌گیری منصفانه — آخر کار خودش برمی‌گرداند)
# ---------------------------------------------------------------------------
set -u
cd "$(dirname "$0")/.."
ROOT="$PWD"
SECS=${SECS:-120}
NEURONS=${NEURONS:-32000}
ARCH=${ARCH:-}
CPU_ONLY=${CPU_ONLY:-0}
STOP_SERVICE=${STOP_SERVICE:-0}

say(){ printf '\n=== %s ===\n' "$*"; }

# --- سرویس مغز دائمی: برای عدد منصفانه باید موقتاً خاموش شود -------------
SVC_WAS_ACTIVE=0
if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet smile-brain 2>/dev/null; then
  SVC_WAS_ACTIVE=1
  if [ "$STOP_SERVICE" = "1" ]; then
    say "توقف موقت smile-brain (آخر کار برمی‌گردد)"
    sudo systemctl stop smile-brain || true
  else
    echo "[!] سرویس smile-brain در حال اجراست — اعداد CPU منصفانه نیستند."
    echo "    برای اندازه‌گیری تمیز:  STOP_SERVICE=1 bash bench/gpu-validate.sh"
  fi
fi
restore_service(){
  if [ "$SVC_WAS_ACTIVE" = "1" ] && [ "$STOP_SERVICE" = "1" ]; then
    say "راه‌اندازی مجدد smile-brain"
    sudo systemctl start smile-brain || true
  fi
}
trap restore_service EXIT

# --- پیش‌نیاز GPU (قبل از صرف وقت روی بنچمارک CPU) ---
if ! command -v nvidia-smi >/dev/null 2>&1; then
  say "nvidia-smi نیست — درایور NVIDIA نصب نیست"
  echo "  sudo ubuntu-drivers install && sudo reboot"
  exit 1
fi
ND=$(nvidia-smi -L 2>/dev/null | wc -l)
if [ "$ND" -eq 0 ]; then say "کارت NVIDIA دیده نمی‌شود"; exit 1; fi
if ! command -v nvcc >/dev/null 2>&1; then
  say "nvcc نیست — CUDA Toolkit نصب نیست"
  echo "  sudo apt install -y nvidia-cuda-toolkit"
  exit 1
fi

# --- CPU: مرجع ------------------------------------------------------------
BIN=bench/smile-bench
if [ ! -x "$BIN" ]; then
  say "بیلد $BIN (CPU)"
  g++ -O2 -march=native -std=c++17 -pthread smile.cpp -o "$BIN" || exit 1
fi
BINABS="$ROOT/$BIN"

run_cpu(){   # $1=نخ (۰=خودکار) · $2=برچسب
  local thr="$1" tag="$2" d t0 t1 ms
  d=$(mktemp -d)
  t0=$(date +%s%N)
  ( cd "$d" && "$BINABS" --neurons "$NEURONS" --headless "$SECS" --seed 7 \
      --threads "$thr" --teacher-strength 60 --holdout 10 --talk 400 \
      --silence --mutate --sprout 5 \
      --words "$ROOT/persian_words.tsv" --user-words "$ROOT/my_words.tsv" \
      --no-browser >/dev/null 2>&1 )
  t1=$(date +%s%N)
  ms=$(( (t1 - t0) / 1000000 ))
  rm -rf "$d"
  awk -v s="$SECS" -v ms="$ms" -v tag="$tag" \
      'BEGIN{printf "%-26s %8.1f×  (%.0fs wall)\n", tag, (ms>0 ? s*1000/ms : 0), ms/1000}'
}

say "مرجع CPU — $NEURONS نورون · $SECS ثانیه‌ی مجازی · فلگ‌های سرویس"
run_cpu 1 "CPU · ۱ نخ"
run_cpu 0 "CPU · همه‌ی نخ‌ها"

if [ "$CPU_ONLY" = "1" ]; then say "تمام (CPU_ONLY=1)"; exit 0; fi

# --- GPU: هسته‌ی اعتبارسنجی ------------------------------------------------
if [ -z "$ARCH" ]; then
  CC=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d '. ')
  case "$CC" in
    61|62) ARCH=sm_61;;      # GTX 1070
    60)    ARCH=sm_60;;
    50|52) ARCH=sm_52;;
    70)    ARCH=sm_70;;
    75)    ARCH=sm_75;;
    *)     ARCH=sm_61; echo "[!] compute_cap=«$CC» خوانده نشد — sm_61 پیش‌فرض";;
  esac
fi
say "بیلد هسته‌ی اعتبارسنجی CUDA (-arch=$ARCH)"
nvcc -O3 -std=c++17 -arch="$ARCH" smile_cuda.cu -o bench/smile-gpu || exit 1

ND=$(nvidia-smi -L 2>/dev/null | wc -l)
say "اجرای اعتبارسنجی روی $ND کارت — هر کدام $SECS ثانیه‌ی واقعی"
i=0
while [ "$i" -lt "$ND" ]; do
  out=$(./bench/smile-gpu --device "$i" --neurons "$NEURONS" --seconds "$SECS" 2>&1)
  speed=$(printf '%s\n' "$out" | grep -oE '\([[:space:]]*[0-9]+\.[0-9]+x\)' | tail -1 | tr -d '() ')
  temp=$(printf '%s\n' "$out" | grep -oE '\| [0-9]+C ' | tail -1 | tr -d '|C ')
  drop=$(printf '%s\n' "$out" | grep -oE 'drop [0-9]+' | tail -1 | cut -d' ' -f2)
  if [ -n "$speed" ]; then
    awk -v d="$i" -v sp="$speed" -v t="$temp" -v dr="$drop" \
        'BEGIN{printf "%-26s %8s×  (دما %s°C · سیگنال‌های افتاده %s)\n", "GPU · کارت "d, sp, t, dr}'
  else
    echo "[!] کارت $i: خروجی سرعت خوانده نشد — خروجی:"
    printf '%s\n' "$out" | tail -5
  fi
  i=$((i+1))
done

say "یادآوری: عدد GPU فقط «موتور محرک» است (بدون معلم/یادگیری). مقایسه با CPU همه‌نخ،"
echo "  تصمیم معماری پورت کامل را می‌دهد: اگر GPU همه‌نخ را شکست، موتور به GPU می‌رود و"
echo "  معلم/تصمیم‌ها روی CPU می‌مانند — همگامی در مرز بسته‌شدن واژه‌ها."
