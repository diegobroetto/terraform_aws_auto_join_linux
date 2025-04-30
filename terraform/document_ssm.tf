resource "aws_ssm_document" "aws_join_linux" {
  name          = "aws_join_linux"
  document_type = "Command"

  content = <<DOC
{
  "schemaVersion": "2.2",
  "description": "Join a Linux instance to Active Directory, configure SSH access and sudo permissions",
  "parameters": {},
  "mainSteps": [
    {
      "action": "aws:runShellScript",
      "name": "JoinDomainAndConfigureSSH",
      "inputs": {
        "runCommand": [
          "set -e",
          "echo \"[1/8] Fetching variables from AWS SSM...\"",
          "DOMAIN=$(aws ssm get-parameter --name DOMAIN --query Parameter.Value --output text)",
          "DOMAIN_USER=$(aws ssm get-parameter --name DOMAIN_USER --query Parameter.Value --output text)",
          "DOMAIN_PASS=$(aws ssm get-parameter --name DOMAIN_PASS --with-decryption --query Parameter.Value --output text)",
          "DOMAIN_GROUP=$(aws ssm get-parameter --name DOMAIN_GROUP --query Parameter.Value --output text)",
          "SSHD_CONFIG=\"/etc/ssh/sshd_config\"",
          "SSSD_CONFIG=\"/etc/sssd/sssd.conf\"",
          "REALM_UPPER=$(echo \"$DOMAIN\" | tr '[:lower:]' '[:upper:]')",
          "",
          "echo \"[2/8] Installing required packages...\"",
          "dnf install -y realmd sssd oddjob oddjob-mkhomedir adcli samba-common samba-common-tools krb5-workstation openldap-clients",
          "",
          "echo \"[3/8] Joining domain $DOMAIN as $DOMAIN_USER...\"",
          "echo \"$DOMAIN_PASS\" | realm join --user=\"$DOMAIN_USER\" \"$DOMAIN\"",
          "realm discover",
          "",
          "echo \"[4/8] Backing up current configuration files...\"",
          "cp \"$SSSD_CONFIG\" \"$SSSD_CONFIG.bak_$(date +%F_%H%M%S)\" 2>/dev/null || true",
          "cp \"$SSHD_CONFIG\" \"$SSHD_CONFIG.bak_$(date +%F_%H%M%S)\" 2>/dev/null || true",
          "",
          "echo \"[5/8] Restarting the services...\"",
          "systemctl restart sssd",
          "systemctl restart sshd",
          "",
          "echo \"[6/8] Creating new sssd.conf...\"",
          "cat <<EOF > \"$SSSD_CONFIG\"",
          "[sssd]",
          "domains = $DOMAIN",
          "config_file_version = 2",
          "services = nss, pam",
          "",
          "[domain/$DOMAIN]",
          "default_shell = /bin/bash",
          "krb5_store_password_if_offline = True",
          "cache_credentials = True",
          "krb5_realm = $REALM_UPPER",
          "realmd_tags = manages-system joined-with-adcli",
          "id_provider = ad",
          "fallback_homedir = /home/%u",
          "ad_domain = $DOMAIN",
          "use_fully_qualified_names = False",
          "ldap_id_mapping = True",
          "access_provider = simple",
          "simple_allow_groups = $DOMAIN_GROUP@$DOMAIN",
          "",
          "[pam]",
          "pam_mkhomedir = true",
          "EOF",
          "",
          "chmod 600 \"$SSSD_CONFIG\"",
          "",
          "echo \"[7/8] Updating SSH configuration...\"",
          "sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' \"$SSHD_CONFIG\"",
          "if grep -q \"^AllowGroups\" \"$SSHD_CONFIG\"; then",
          "  sed -i \"s/^AllowGroups.*/AllowGroups $DOMAIN_GROUP/\" \"$SSHD_CONFIG\"",
          "else",
          "  echo \"AllowGroups $DOMAIN_GROUP\" >> \"$SSHD_CONFIG\"",
          "fi",
          "grep -q \"^ChallengeResponseAuthentication\" \"$SSHD_CONFIG\" || echo \"ChallengeResponseAuthentication yes\" >> \"$SSHD_CONFIG\"",
          "grep -q \"^UsePAM\" \"$SSHD_CONFIG\" || echo \"UsePAM yes\" >> \"$SSHD_CONFIG\"",
          "",
          "echo \"[8/8] Starting services...\"",
          "systemctl start sssd",
          "systemctl start sshd",
          "",
          "echo \"[9/8] Granting sudo permissions to AD group...\"",
          "echo \"%$DOMAIN_GROUP ALL=(ALL) ALL\" > /etc/sudoers.d/$DOMAIN_GROUP",
          "chmod 440 /etc/sudoers.d/$DOMAIN_GROUP",
          "",
          "echo \"Domain join completed. SSH and sudo access granted to AD group: $DOMAIN_GROUP\""
        ]
      }
    }
  ]
}
DOC
}