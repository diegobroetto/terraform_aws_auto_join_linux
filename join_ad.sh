#!/bin/bash

# -----------------------------------------------------------------------------
# Author      : Diego Broetto
# Date        : 2025-03-25
# Description : Script to automate domain join for Linux EC2 instances
# Version     : 1.0
# License     : Apache 2.0
# -----------------------------------------------------------------------------

DOMAIN=$(aws ssm get-parameter --name DOMAIN --query "Parameter.Value" --output text)
DOMAIN_USER=$(aws ssm get-parameter --name DOMAIN_USER --query "Parameter.Value" --output text)
DOMAIN_PASS=$(aws ssm get-parameter --name DOMAIN_PASS --with-decryption --query "Parameter.Value" --output text)
DOMAIN_GROUP=$(aws ssm get-parameter --name DOMAIN_GROUP --query "Parameter.Value" --output text)
SSHD_CONFIG="/etc/ssh/sshd_config"

echo "Installing dependencies..."
yum install -y realmd sssd oddjob oddjob-mkhomedir adcli samba-common samba-common-tools krb5-workstation openldap-clients

echo "Joining the domain..."
echo $DOMAIN_PASS | realm join --user=$DOMAIN_USER $DOMAIN
realm discover $DOMAIN

echo "Creating backup of sshd configuration..."
cp $SSHD_CONFIG ${SSHD_CONFIG}.bak
systemctl stop sshd

echo "Updating SSH configuration parameters..."
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' $SSHD_CONFIG
{
    echo "ChallengeResponseAuthentication yes"
    echo "UsePAM yes"
    echo dyndns_update = true
    echo dyndns_refresh_interval = 43200
    echo dyndns_update_ptr = true 
    echo dyndns_ttl = 3600
} >> $SSHD_CONFIG

systemctl start sshd

echo "Granting sudo access to domain group..."
realm permit -g '${DOMAIN_GROUP}'
echo "%${DOMAIN_GROUP}@${DOMAIN} ALL=(ALL) ALL" >> /etc/sudoers.d/${DOMAIN_GROUP}
chmod 440 /etc/sudoers.d/${DOMAIN_GROUP}
chown root:root /etc/sudoers.d/${DOMAIN_GROUP}
