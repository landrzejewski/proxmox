# Function to display usage
show_usage() {
    echo "Usage: $0 [--lang pl|en] <number_of_students> OR $0 [--lang pl|en] <start> <end>"
    echo "Examples:"
    echo "  $0 10                    # Process students 1-10 with Polish template"
    echo "  $0 --lang en 10          # Process students 1-10 with English template"
    echo "  $0 5 9                   # Process students 5-9 with Polish template"
    echo "  $0 --lang en 5 9         # Process students 5-9 with English template"
    echo ""
    echo "Options:"
    echo "  --lang pl|en    Choose template language (default: pl)"
    echo ""
    echo "Script will connect to each server via sages.link using port 2000x"
    exit 1
}

# Default language
LANGUAGE="pl"

# Parse language option if present
if [ "$1" = "--lang" ]; then
    if [ "$2" = "pl" ] || [ "$2" = "en" ]; then
        LANGUAGE="$2"
        shift 2
    else
        echo "Error: Invalid language. Use 'pl' or 'en'"
        show_usage
    fi
fi

# Parse arguments
if [ $# -eq 1 ]; then
    # Single argument: process from 1 to N
    if ! [[ "$1" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: Number of students must be a positive integer"
        show_usage
    fi
    START_NUM=1
    END_NUM="$1"
elif [ $# -eq 2 ]; then
    # Two arguments: process from START to END
    if ! [[ "$1" =~ ^[1-9][0-9]*$ ]] || ! [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: Start and end must be positive integers"
        show_usage
    fi
    if [ "$1" -gt "$2" ]; then
        echo "Error: Start number must be less than or equal to end number"
        show_usage
    fi
    START_NUM="$1"
    END_NUM="$2"
else
    show_usage
fi

# X-Tunnel configuration
XTUNNEL_HOST="sages.link"

# Function to generate random password (8 characters: letters and digits)
generate_password() {
    # Fix for macOS "Illegal byte sequence" error
    LC_ALL=C tr -dc 'A-Za-z0-9!&@%()$' < /dev/urandom | head -c 8
}

# Function to read current password from file
read_current_password() {
    local student_num="$1"
    local password_file="credentials/student${student_num}.html"

    if [ -f "$password_file" ]; then
        # Read password from HTML file - look specifically for the password field
        # Debug: Let's see what we're finding
        # echo "Debug: Reading from $password_file" >&2

        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS version - extract password from the config-password span
            # First, let's get the entire line with the password
            local password_line=$(grep 'class="config-value config-password' "$password_file")
            # echo "Debug: Found line: $password_line" >&2

            # Extract content between > and < after the class definition
            local extracted_password=$(echo "$password_line" | sed -E 's/.*class="config-value config-password[^>]*>([^<]+)<.*/\1/')
            # echo "Debug: Extracted password: '$extracted_password'" >&2

            echo "$extracted_password"
        else
            # Linux version - use grep with Perl regex
            local extracted_password=$(grep -oP 'class="config-value config-password[^>]*>\K[^<]+' "$password_file" | head -1)
            # echo "Debug: Extracted password: '$extracted_password'" >&2
            echo "$extracted_password"
        fi
    else
        # If file doesn't exist, assume default password is studentX
        echo "student${student_num}"
    fi
}

# Function to update password in file with full format
update_password_file() {
    local student_num="$1"
    local new_password="$2"
    local password_file="credentials/student${student_num}.html"
    local ssh_port="1$(printf "%04d" ${student_num})"
    local rdp_port="2$(printf "%04d" ${student_num})"
    local username="student${student_num}"
    local template_file=""

    # Select template based on language
    if [ "$LANGUAGE" = "en" ]; then
        template_file="student-template-en.html"
    else
        template_file="student-template-pl.html"
    fi

    # Check if template file exists
    if [ ! -f "$template_file" ]; then
        echo "Error: Template file '$template_file' not found!"
        echo "Please ensure the HTML template file is in the same directory as this script."
        return 1
    fi

    # Copy template to destination and replace placeholders
    cp "$template_file" "$password_file"

    # Replace placeholders with actual values - macOS compatible
    # Need to escape special characters in passwords for sed
    local escaped_password=$(printf '%s\n' "$new_password" | sed 's/[[\.*^$()+?{|]/\\&/g')

    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/{{USERNAME}}/${username}/g" "$password_file"
        sed -i '' "s/{{PASSWORD}}/${escaped_password}/g" "$password_file"
        sed -i '' "s/{{SSH_PORT}}/${ssh_port}/g" "$password_file"
        sed -i '' "s/{{RDP_PORT}}/${rdp_port}/g" "$password_file"
    else
        # Linux
        sed -i "s/{{USERNAME}}/${username}/g" "$password_file"
        sed -i "s/{{PASSWORD}}/${escaped_password}/g" "$password_file"
        sed -i "s/{{SSH_PORT}}/${ssh_port}/g" "$password_file"
        sed -i "s/{{RDP_PORT}}/${rdp_port}/g" "$password_file"
    fi

    echo "Updated password file: $password_file"
}

# Function to connect and change password (user connects as themselves)
change_user_password() {
    local student_num="$1"
    local username="$2"
    local old_password="$3"
    local new_password="$4"
    local ssh_port="1$(printf "%04d" ${student_num})"

    echo "Connecting to $XTUNNEL_HOST:$ssh_port as user $username to change password..."

    # First, remove any existing known_hosts entry for this host:port combination
    ssh-keygen -f "$HOME/.ssh/known_hosts" -R "[$XTUNNEL_HOST]:$ssh_port" 2>/dev/null

    # Use sshpass to connect as the user and change their own password
    # Added more SSH options to handle host key issues
    sshpass -p "$old_password" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o CheckHostIP=no \
        -o ConnectTimeout=10 \
        -o BatchMode=no \
        -o PasswordAuthentication=yes \
        -o PreferredAuthentications=password \
        -p "$ssh_port" \
        "$username"@"$XTUNNEL_HOST" \
        "printf '%s\n%s\n%s\n' '$old_password' '$new_password' '$new_password' | passwd"

    local ssh_result=$?
    if [ $ssh_result -eq 0 ]; then
        echo "Successfully updated password for $username via $XTUNNEL_HOST:$ssh_port"
        return 0
    else
        echo "Failed to update password for $username via $XTUNNEL_HOST:$ssh_port"
        return 1
    fi
}

echo "Starting student password management script..."
echo "Using language: $LANGUAGE"
echo "Processing students from $START_NUM to $END_NUM"
echo "Connecting via sages.link host with port 1000x..."
echo "Setting up credentials folder..."

# Create credentials folder if it doesn't exist
mkdir -p credentials

echo "Processing student passwords..."
echo "========================================"

# Track statistics
SUCCESSFUL=0
FAILED=0

# Generate files and connect to servers
for ((i=START_NUM; i<=END_NUM; i++)); do
    # Generate filename and new password
    filename="student$i"
    new_password=$(generate_password)

    # Read current password from file (or use default)
    current_password=$(read_current_password "$i")
    echo "Read current password for $filename from file (or using default)"

    # Try to change password on remote server via x-tunnel
    if change_user_password "$i" "$filename" "$current_password" "$new_password"; then
        # Update the password file with the new password and full format
        update_password_file "$i" "$new_password"
        echo "Password successfully changed and file updated for $filename"
        ((SUCCESSFUL++))
    else
        echo "Failed to change password for $filename - keeping existing password"
        # Always create/update the file with the current password
        update_password_file "$i" "$current_password"
        echo "Created/updated credential file with existing password for $filename"
        ((FAILED++))
    fi

    echo "----------------------------------------"

    # Small delay to avoid overwhelming the network
    sleep 1
done

echo ""
echo "Script completed!"
echo "Summary:"
echo "  Successful password changes: $SUCCESSFUL"
echo "  Failed password changes: $FAILED"
echo "  Total processed: $((SUCCESSFUL + FAILED))"
echo ""
echo "Check the credentials/ directory for password files"