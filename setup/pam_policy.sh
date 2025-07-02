#!/bin/bash

POLICY_FILE="/etc/policy.txt"

# Run only for interactive SSH sessions (has tty)
if [ -t 0 ]; then
    clear
    cat "$POLICY_FILE"
    echo
    echo -n "Czy akceptujesz poniższy regulamin korzystania z maszyn wirtualnych? Wpisz 'tak', aby kontynuować: "
        read response
        if [ "$response" != "tak" ]; then
            echo "Odmowa dostępu. Regulamin nie został zaakceptowany."
            exit 1
        fi
        logger -t SECURITY "$PAM_USER accepted policy on ssh connection level $(date)"
fi
exit 0