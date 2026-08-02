#!/bin/bash

set -euo pipefail 
source $1     # takes the user configuration file as argument
source "$(dirname "$0")/../../common/lib.sh"
require_root
trap trap_cleanup EXIT


# Checking if user already exists
if id "$USERNAME" &>/dev/null; then
    die "User already exisits."
fi

# Creating the user
useradd -m \ 
        -d "$HOME_DIR" \
        -s "$SHELL" \
        -c "$FULLNAME" \ 
        -G "$GROUPS" \
        "$USERNAME"

if [[ $TEMP_PASSWD == "yes" ]]; then
    # Setting a temporary password, force change on first login
    echo "$USERNAME:ChangeMe123!" | chpasswd
    chage -d 0 "$USERNAME"            
fi

if [[ $SET_SSH == "yes" ]]; then
    # 4. Set up SSH access (key-based, not password)
    mkdir -p "$HOME_DIR/.ssh"
    cp /path/to/authorized_keys "$HOME_DIR/.ssh/authorized_keys"
    chmod 700 "$HOME_DIR/.ssh"
    chmod 600 "$HOME_DIR/.ssh/authorized_keys"
    chown -R "$USERNAME:$USERNAME" "$HOME_DIR/.ssh"
fi


# 6. Set permissions on home directory
chmod 750 "$HOME_DIR"

