#!/bin/bash

# Check if required argument is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <number_of_students>"
    echo "Please provide the number of student files to create"
    echo "Script will connect to each server as the student user with existing password"
    exit 1
fi

NUM_STUDENTS="$1"

# Validate that number of students is a positive integer
if ! [[ "$NUM_STUDENTS" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: Number of students must be a positive integer"
    exit 1
fi
BASE_IP="192.168.195"

# Function to generate random password (8 characters: letters and digits)
generate_password() {
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 8
}

# Function to connect and change password (user connects as themselves)
change_user_password() {
    local ip="$1"
    local username="$2"
    local old_password="$3"
    local new_password="$4"

    echo "Connecting to $ip as user $username to change password..."

    # Use sshpass to connect as the user and change their own password
    sshpass -p "$old_password" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=no "$username"@"$ip" << EOF
        # Change own password using passwd
        echo -e "$old_password\n$new_password\n$new_password" | passwd
        echo "Password changed for user $username"
EOF

    local ssh_result=$?
    if [ $ssh_result -eq 0 ]; then
        echo "Successfully updated password for $username on $ip"
        return 0
    else
        echo "Failed to update password for $username on $ip"
        return 1
    fi
}

echo "Starting student password management script..."
echo "Users will connect as themselves to change their passwords..."
echo "Setting up credentials folder..."

# Create credentials folder if it doesn't exist
mkdir -p credentials

# Remove existing student files if they exist (based on the number specified)
for ((i=1; i<=NUM_STUDENTS; i++)); do
    rm -f "credentials/student$i.txt" 2>/dev/null
done
echo "Existing student files removed from credentials folder"

echo "Creating new password files and updating remote servers..."
echo "========================================"

# Generate files and connect to servers
for ((i=1; i<=NUM_STUDENTS; i++)); do
    # Generate filename and new password
    filename="student$i"
    new_password=$(generate_password)

    # Current password is the same as username (student1, student2, etc.)
    current_password="$filename"

    # Calculate IP address (101, 102, 103, ...)
    ip="${BASE_IP}.$((100 + i))"

    # Try to change password on remote server
    if change_user_password "$ip" "$filename" "$current_password" "$new_password"; then
        # Only create file if password change was successful
        echo "$new_password" > "credentials/$filename.txt"
        echo "Created file: credentials/$filename.txt with new password"
    else
        echo "Skipping file creation for $filename.txt due to password change failure"
    fi

    echo "----------------------------------------"

    # Small delay to avoid overwhelming the network
    sleep 1
done
