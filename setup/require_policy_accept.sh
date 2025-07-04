#!/bin/bash

POLICY_FILE="/etc/policy.txt"
ACCEPT_FILE="$HOME/.policy_accepted"

# Run only for interactive shells with a TTY
if [[ -t 0 && -z "$POLICY_ACCEPTED" && ! -f "$ACCEPT_FILE" ]]; then
    clear
    cat "$POLICY_FILE"
    echo
    read -p "Czy akceptujesz regulamin? Wpisz 'tak', aby kontynuować: " response
    if [[ "$response" != "tak" ]]; then
        echo "Odmowa dostępu. Regulamin nie został zaakceptowany."
        exit 1
    fi
    echo "accepted" > "$ACCEPT_FILE"
    logger -t SECURITY "$(whoami) accepted policy via /etc/profile.d at $(date)"
    export POLICY_ACCEPTED=1
fi
