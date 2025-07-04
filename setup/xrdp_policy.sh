#!/bin/bash

POLICY_FILE="/etc/policy.txt"
ACCEPT_FILE="$HOME/.xrdp_policy_accepted"

if [[ -f "$ACCEPT_FILE" ]]; then
    # Policy already accepted, continue
    logger -t SECURITY "$USER already accepted XRDP policy, skipping prompt at $(date)"
    exit 0
fi

yad --text-info --center --title="Regulamin" --width=700 --height=800 \
    --filename="$POLICY_FILE" --button="Anuluj:0" --button="Akceptuję:1"

if [ $? -ne 1 ]; then
    echo "Odmowa dostępu. Regulamin nie został zaakceptowany."
    logger -t SECURITY "$USER rejected XRDP policy at $(date)"

    pkill -u "$USER" -f "xrdp"
    pkill -u "$USER" -f "xorgxrdp"
    
    exit 1
fi

echo "accepted at $(date)" > "$ACCEPT_FILE"
chmod 600 "$ACCEPT_FILE"

logger -t SECURITY "$USER accepted XRDP policy on $(date) from ${DISPLAY:-unknown}"
