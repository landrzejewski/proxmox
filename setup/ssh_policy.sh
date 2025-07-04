#!/bin/bash

POLICY_FILE="/etc/policy.txt"

# Run only for interactive shells with a TTY
if [[ -t 0 && -z "$POLICY_ACCEPTED" ]]; then
    # Trap signals to prevent bypassing the policy
    trap '' INT TERM QUIT TSTP

    # Function to handle policy acceptance
    accept_policy() {
        local response=""
        local attempts=0
        local max_attempts=3

        while [[ $attempts -lt $max_attempts ]]; do
            clear
            cat "$POLICY_FILE"
            echo

            # Use -r to prevent backslash escaping
            if read -r -p "Czy akceptujesz regulamin? Wpisz 'tak', aby kontynuować: " response; then
                if [[ "$response" == "tak" ]]; then
                    logger -t SECURITY "$(whoami) accepted policy from $(tty) at $(date)"
                    export POLICY_ACCEPTED=1
                    # Restore signal handling
                    trap - INT TERM QUIT TSTP
                    return 0
                else
                    ((attempts++))
                    if [[ $attempts -lt $max_attempts ]]; then
                        echo "Nieprawidłowa odpowiedź. Pozostało prób: $((max_attempts - attempts))"
                        sleep 2
                    fi
                fi
            else
                # Handle EOF (Ctrl+D)
                echo
                ((attempts++))
                if [[ $attempts -lt $max_attempts ]]; then
                    echo "Musisz zaakceptować regulamin. Pozostało prób: $((max_attempts - attempts))"
                    sleep 2
                fi
            fi
        done

        # If we get here, user failed to accept after max attempts
        echo "Odmowa dostępu. Regulamin nie został zaakceptowany."
        logger -t SECURITY "$(whoami) failed to accept policy after $max_attempts attempts from $(tty) at $(date)"

        # Force logout
        if [[ -n "$SSH_TTY" ]]; then
            # For SSH sessions, kill the parent sshd process
            kill -HUP $PPID 2>/dev/null
        fi

        # Exit the shell
        exit 1
    }

    # Call the acceptance function
    accept_policy
fi