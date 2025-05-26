#!/bin/bash

# -----------------------------------------------------------------------------
# Author      : Diego Broetto
# Date        : 2025-03-25
# Description : Script to automate domain join for Linux AWS EC2 instances
# Version     : 1.1
# License     : Apache 2.0
# -----------------------------------------------------------------------------

set -e

# === 1. FETCH VARIABLES FROM SSM ===
echo "[1/9] Fetching variables from AWS SSM..."
DOMAIN=$(aws ssm get-parameter --name DOMAIN --query "Parameter.Value" --output text)
DOMAIN_USER=$(aws ssm get-parameter --name DOMAIN_USER --query "Parameter.Value" --output text)
DOMAIN_PASS=$(aws ssm get-parameter --name DOMAIN_PASS --with-decryption --query "Parameter.Value" --output text)
DOMAIN_GROUP=$(aws ssm get-parameter --name DOMAIN_GROUP --query "Parameter.Value" --output text)
SSHD_CONFIG="/etc/ssh/sshd_config"
SSSD_CONFIG="/etc/sssd/sssd.conf"
REALM_UPPER=$(echo "$DOMAIN" | tr '[:lower:]' '[:upper:]')

# === 2. INSTALL REQUIRED PACKAGES ===
echo "[2/9] Installing required packages..."
dnf install -y realmd sssd oddjob oddjob-mkhomedir adcli samba-common samba-common-tools krb5-workstation openldap-clients

# === 3. JOIN DOMAIN ===
echo "[3/9] Joining domain $DOMAIN as $DOMAIN_USER..."
echo "$DOMAIN_PASS" | realm join --user="$DOMAIN_USER" "$DOMAIN"

# === 4. BACKUP CONFIGURATION FILES ===
echo "[4/9] Backing up current configuration files..."
cp "$SSSD_CONFIG" "${SSSD_CONFIG}.bak_$(date +%F_%H%M%S)" 2>/dev/null || true
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak_$(date +%F_%H%M%S)" 2>/dev/null || true

# === 5. GENERATE NEW sssd.conf ===
echo "[6/9] Creating new sssd.conf..."
cat > "$SSSD_CONFIG" <<EOF
[sssd]
domains = $DOMAIN
config_file_version = 2
services = nss, pam

[domain/$DOMAIN]
default_shell = /bin/bash
krb5_store_password_if_offline = True
cache_credentials = True
krb5_realm = $REALM_UPPER
realmd_tags = manages-system joined-with-adcli
id_provider = ad
fallback_homedir = /home/%u
ad_domain = $DOMAIN
use_fully_qualified_names = False
ldap_id_mapping = True
access_provider = simple
simple_allow_groups = $DOMAIN_GROUP@$DOMAIN

[pam]
pam_mkhomedir = true
EOF

chmod 600 "$SSSD_CONFIG"

# === 6. RESTART SSSD TO APPLY NEW CONFIGURATION ===
echo "[6/9] Restarting SSSD to apply new configuration..."
systemctl restart sssd
systemctl enable sssd

# === 7. CONFIGURE SSH ===
echo "[7/9] Updating SSH configuration..."
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD_CONFIG"

if grep -q "^AllowGroups" "$SSHD_CONFIG"; then
    sed -i "s/^AllowGroups.*/AllowGroups $DOMAIN_GROUP/" "$SSHD_CONFIG"
else
    echo "AllowGroups $DOMAIN_GROUP" >> "$SSHD_CONFIG"
fi

grep -q "^ChallengeResponseAuthentication" "$SSHD_CONFIG" || echo "ChallengeResponseAuthentication yes" >> "$SSHD_CONFIG"
grep -q "^UsePAM" "$SSHD_CONFIG" || echo "UsePAM yes" >> "$SSHD_CONFIG"

# === 8. RESTART SSH TO APPLY CONFIGURATION ===
echo "[9/9] Restarting SSH to apply configuration..."
systemctl restart sshd
systemctl enable sshd

# === 9. CONFIGURE SUDOERS FOR AD GROUP ===
echo "[9/9] Granting sudo permissions to AD group '$DOMAIN_GROUP'..."
echo "%$DOMAIN_GROUP ALL=(ALL) ALL" > /etc/sudoers.d/$DOMAIN_GROUP
chmod 440 /etc/sudoers.d/$DOMAIN_GROUP

echo "Domain join completed. SSH and sudo access configured for AD group: $DOMAIN_GROUP"
