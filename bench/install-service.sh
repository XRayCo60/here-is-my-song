#!/bin/bash
# ---------------------------------------------------------------------------
# install-service — نصب مغز دائمی به‌صورت سرویس systemd (بند ۴۲)
#
#   bash bench/install-service.sh
#
# بعد از نصب:
#   systemctl status smile-brain       → وضعیت
#   sudo systemctl stop smile-brain    → توقف تمیز (اول ذخیره، بعد خروج)
#   sudo systemctl start smile-brain   → ادامه‌ی همان مغز
#   journalctl -u smile-brain -f       → لاگ زنده
#
# توقف تمیز: ExecStop اول /shutdown را صدا می‌زند (ذخیره‌ی brain.dat) و بعد
# فرایند بسته می‌شود. کرش ناگهانی هم فقط تا آخرین autosave ضرر دارد (≤۱۰
# دقیقه‌ی مجازی). Restart=on-failure یعنی کرش → راه‌اندازی مجدد خودکار از
# همان چک‌پوینت.
# ---------------------------------------------------------------------------
set -e
cd "$(dirname "$0")/.."
ROOT=$(pwd)

BIN=$ROOT/bench/smile-bench
if [ ! -x "$BIN" ]; then
  echo "[install] بیلد: $BIN"
  g++ -O2 -march=native -std=c++17 -pthread smile.cpp -o "$BIN"
fi

SRV=/etc/systemd/system/smile-brain.service
sudo tee "$SRV" >/dev/null <<UNIT
[Unit]
Description=smile - permanent brain
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$ROOT
ExecStart=$ROOT/bench/serve-brain.sh
ExecStop=/bin/sh -c 'curl -s -m 5 http://127.0.0.1:8420/shutdown >/dev/null 2>&1; sleep 3'
Restart=on-failure
RestartSec=5
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now smile-brain
sleep 2

echo
echo "=========================================="
systemctl --no-pager -l status smile-brain | head -8
echo "=========================================="
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
echo
echo "  داشبورد از لپ‌تاپ:   http://$IP:8420"
echo "  اگر فایروال روشن است:   sudo ufw allow 8420"
echo "  لاگ زنده:   journalctl -u smile-brain -f"
echo
