POLICY_FILE="/etc/policy.txt"

yad --text-info --center --title="Regulamin" --width=700 --height=800 \
    --filename="$POLICY_FILE" --button="Anuluj:0" --button="Akceptuję:1"

if [ $? -ne 1 ]; then
    echo "Odmowa dostępu. Regulamin nie został zaakceptowany."
    exit 1
fi

logger -t SECURITY "$USER accepted policy on xrdp connection level $(date)"