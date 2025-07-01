POLICY_FILE="/etc/policy.txt"
ACCEPT_FILE="/etc/policy_accepted-$USER"

# Show policy prompt only if not already accepted
if [ ! -f "$ACCEPT_FILE" ]; then
    yad --text-info --center --title="Regulamin" --width=700 --height=800 \
        --filename="$POLICY_FILE" --button="Anuluj:0" --button="Akceptuję:1"

    if [ $? -ne 1 ]; then
        echo "Policy not accepted. Exiting..."
        exit 1
    fi

    echo "Accepted by $USER on $(date)" > "$ACCEPT_FILE"
    chmod 644 "$ACCEPT_FILE"
fi

