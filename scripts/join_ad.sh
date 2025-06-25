#!/bin/bash

# -----------------------------------------------------------------------------
# Author      : Diego Broetto
# Date        : 2025-06-25
# Description : Script to automate domain join for Linux AWS EC2 instances
# Version     : 2.0
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
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
REALM_UPPER=$(echo "$DOMAIN" | tr '[:lower:]' '[:upper:]')

echo "Domain: $DOMAIN"
echo "Domain User: $DOMAIN_USER"
echo "Domain Group: $DOMAIN_GROUP"
echo "Instance ID: $INSTANCE_ID"

# === 2. CHANGE INSTANCE HOSTNAME ===
echo "[2/9] Changing instance hostname..."
NEW_HOSTNAME=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=Name" --query "Tags[0].Value" --output text)

if [ ! -z "$NEW_HOSTNAME" ] && [ "$NEW_HOSTNAME" != "None" ]; then
    hostnamectl set-hostname "$NEW_HOSTNAME"
    echo "Hostname changed to: $NEW_HOSTNAME"
else
    echo "No Name tag found for this instance, keeping current hostname"
fi

# === 3. INSTALL REQUIRED PACKAGES ===
echo "[3/9] Installing required packages..."
dnf install -y sssd realmd krb5-workstation adcli samba-common-tools oddjob oddjob-mkhomedir samba-common openldap-clients

# === 4. JOIN DOMAIN ===
echo "[4/9] Joining domain $DOMAIN as $DOMAIN_USER..."
echo "$DOMAIN_PASS" | realm join --user="$DOMAIN_USER" "$DOMAIN"

echo "Verifying domain join:"
realm list

# === 5. BACKUP CONFIGURATION FILES ===
echo "[5/9] Backing up current configuration files..."
cp "$SSSD_CONFIG" "${SSSD_CONFIG}.bak_$(date +%F_%H%M%S)" 2>/dev/null || true
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak_$(date +%F_%H%M%S)" 2>/dev/null || true

# === 6. CREATE NEW SSSD.CONF ===
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

# === 7. RESTART SSSD TO APPLY NEW CONFIGURATION ===
echo "[7/9] Restarting SSSD to apply new configuration..."
systemctl restart sssd
systemctl enable sssd

echo "Waiting for SSSD to initialize..."
sleep 10

# === 8. CONFIGURE SSH ===
echo "[8/9] Updating SSH configuration..."
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD_CONFIG"

if grep -q "^AllowGroups" "$SSHD_CONFIG"; then
    sed -i "s/^AllowGroups.*/AllowGroups $DOMAIN_GROUP/" "$SSHD_CONFIG"
else
    echo "AllowGroups $DOMAIN_GROUP" >> "$SSHD_CONFIG"
fi

grep -q "^ChallengeResponseAuthentication" "$SSHD_CONFIG" || echo "ChallengeResponseAuthentication yes" >> "$SSHD_CONFIG"
grep -q "^UsePAM" "$SSHD_CONFIG" || echo "UsePAM yes" >> "$SSHD_CONFIG"

# === 9. RESTART SSH TO APPLY CONFIGURATION ===
echo "[9/9] Restarting SSH to apply configuration..."
systemctl restart sshd
systemctl enable sshd

# === 10. CONFIGURE SUDOERS FOR AD GROUP ===
echo "Configuring sudoers for AD group..."
echo "%$DOMAIN_GROUP ALL=(ALL) ALL" > /etc/sudoers.d/$DOMAIN_GROUP
chmod 440 /etc/sudoers.d/$DOMAIN_GROUP

echo "=== DOMAIN JOIN COMPLETED SUCCESSFULLY ==="
echo "Domain: $DOMAIN"
echo "Hostname: $(hostname)"
echo "SSH access granted to group: $DOMAIN_GROUP"
echo "Sudo access granted to group: $DOMAIN_GROUP"

echo "Final verification:"
systemctl status sssd --no-pager
systemctl status sshd --no-pager

echo "Domain join completed successfully!"