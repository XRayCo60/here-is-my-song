#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  هارنس A/B برای پله‌های یادگیری
#
#  دو بازو را با بذرهای یکسان اجرا می‌کند و خروجی ماشین‌خوان RESULT را
#  جمع می‌بندد. فلگ‌ها با متغیرهای محیطی قابل تنظیم‌اند:
#
#     COMMON_FLAGS  فلگ‌هایی که به هر دو بازو می‌رسد   (پیش‌فرض: خالی)
#     OFF_FLAGS     فقط بازوی off                       (پیش‌فرض: خالی)
#     ON_FLAGS      فقط بازوی on                        (پیش‌فرض: --rewire)
#
#  مثال‌ها:
#     bench/ab.sh 8 600 1000                       # قدیمی: off در برابر --rewire
#     COMMON_FLAGS='--teach-feed 3' \
#       ON_FLAGS='--rewire --silence --mutate' bench/ab.sh 10 600 1000
#     ON_FLAGS='--teach-feed 3' bench/ab.sh 8 600 1000   # سخن گفتن معلم به تنهایی
#
#  استفاده:
#     bench/ab.sh [SEEDS] [SECONDS] [NEURONS]
# ---------------------------------------------------------------------------
set -u
cd "$(dirname "$0")/.."

SEEDS=${1:-8}
SECS=${2:-600}
NEUR=${3:-1000}
STRENGTH=${STRENGTH:-60}
HOLDOUT=${HOLDOUT:-10}
TALK=${TALK:-400}
JOBS=${JOBS:-$(nproc 2>/dev/null || echo 2)}

COMMON_FLAGS=${COMMON_FLAGS:-}
OFF_FLAGS=${OFF_FLAGS:-}
ON_FLAGS=${ON_FLAGS:---rewire}

BIN=${BIN:-./bench/smile-bench}
OUT=bench/results.tsv

if [ ! -x "$BIN" ]; then
  echo "build: $BIN"
  g++ -O2 -std=c++17 -pthread smile.cpp -o "$BIN" || exit 1
fi
# BIN باید مطلق باشد — زیر‌پوسته به پوشه‌ی موقت cd می‌کند
case $BIN in /*) ;; *) BIN="$PWD/$BIN" ;; esac

echo "seeds=$SEEDS seconds=$SECS neurons=$NEUR strength=$STRENGTH holdout=$HOLDOUT talk=$TALK jobs=$JOBS"
echo "common=[$COMMON_FLAGS] off=[$OFF_FLAGS] on=[$ON_FLAGS]"
: > "$OUT"

run_one() {           # $1=seed  $2=arm(off|on)
  local seed=$1 arm=$2 extra="$COMMON_FLAGS"
  [ "$arm" = on ] && extra="$extra $ON_FLAGS"
  [ "$arm" = off ] && extra="$extra $OFF_FLAGS"
  # هر اجرا در پوشه‌ی خودش، تا brain.dat ها روی هم نیفتند
  local d; d=$(mktemp -d)
  ( cd "$d" && "$BIN" --neurons "$NEUR" --headless "$SECS" --seed "$seed" \
      --teacher-strength "$STRENGTH" --holdout "$HOLDOUT" --talk "$TALK" $extra \
      --words "$OLDPWD/persian_words.tsv" --user-words "$OLDPWD/my_words.tsv" \
      --no-browser 2>/dev/null ) | grep '^RESULT' | sed "s/^RESULT /arm=$arm /"
  rm -rf "$d"
}
export -f run_one
export BIN NEUR SECS STRENGTH HOLDOUT TALK OLDPWD="$PWD" COMMON_FLAGS OFF_FLAGS ON_FLAGS

for arm in off on; do
  for s in $(seq 1 "$SEEDS"); do echo "$s $arm"; done
done | xargs -P "$JOBS" -n 2 bash -c 'run_one "$0" "$1"' | tee "$OUT"

echo
echo "خلاصه:"
awk '
function mean(a,n,  i,s){s=0;for(i=1;i<=n;i++)s+=a[i];return n?s/n:0}
function sd(a,n,m,  i,s){s=0;if(n<2)return 0;for(i=1;i<=n;i++)s+=(a[i]-m)^2;return sqrt(s/(n-1))}
{
  split($0,f," "); arm="";
  for(i=1;i<=NF;i++){split($i,kv,"="); v[kv[1]]=kv[2]}
  a=v["arm"]; n[a]++
  ex[a,n[a]]=v["exactpct"]; q[a,n[a]]=v["avgQ"]; w[a,n[a]]=v["words"]
  hd[a,n[a]]=v["heldpct"]; dd[a,n[a]]=v["dead"]; rw[a,n[a]]=v["rewires"]
  mu[a,n[a]]=v["mutates"]; si[a,n[a]]=v["silence"]; fe[a,n[a]]=v["fed"]
  sp[a,n[a]]=v["sprouts"]; pp[a,n[a]]=v["pop"]; di[a,n[a]]=v["distinct"]
}
END{
  printf "%-5s %3s %14s %14s %10s %8s %8s %8s %8s %8s %8s\n","arm","n","exact%","avgQ","words","held%","distinct","spr","pop","mut","sil"
  for(k=1;k<=2;k++){
    a=(k==1?"off":"on"); if(!n[a])continue
    for(i=1;i<=n[a];i++){E[i]=ex[a,i];Q[i]=q[a,i];W[i]=w[a,i];H[i]=hd[a,i];D[i]=dd[a,i]
                         M[i]=mu[a,i];S[i]=si[a,i];F[i]=fe[a,i];R[i]=rw[a,i]
                         P[i]=sp[a,i];O[i]=pp[a,i];X[i]=di[a,i]}
    me=mean(E,n[a]); mq=mean(Q,n[a]); mw=mean(W,n[a]); mh=mean(H,n[a]); md=mean(D,n[a])
    mm=mean(M,n[a]); ms=mean(S,n[a]); mf=mean(F,n[a]); mr=mean(R,n[a])
    mp=mean(P,n[a]); mo=mean(O,n[a]); mx=mean(X,n[a])
    printf "%-5s %3d %7.2f±%-6.2f %7.2f±%-6.2f %10.1f %8.2f %8.1f %8.1f %8.1f %8.1f %8.1f\n", \
      a,n[a],me,sd(E,n[a],me),mq,sd(Q,n[a],mq),mw,mh,mx,mp,mo,mm,ms
  }
}' "$OUT"
