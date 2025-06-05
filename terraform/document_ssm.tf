resource "aws_ssm_document" "aws_join_linux" {
  name          = "aws_join_linux"
  document_type = "Command"

  content = <<DOC
{
  "schemaVersion": "2.2",
  "description": "Automate domain join for Linux AWS EC2 instances with SSH configuration - Converted from join_ad.sh",
  "parameters": {},
  "mainSteps": [
    {
      "action": "aws:runShellScript",
      "name": "FetchSSMParameters",
      "description": "Fetch variables from AWS SSM Parameter Store",
      "inputs": {
        "timeoutSeconds": "300",
        "runCommand": [
          "#!/bin/bash",
          "echo \"[1/9] Fetching variables from AWS SSM...\"",
          "DOMAIN=$(aws ssm get-parameter --name DOMAIN --query 'Parameter.Value' --output text)",
          "DOMAIN_USER=$(aws ssm get-parameter --name DOMAIN_USER --query 'Parameter.Value' --output text)",
          "DOMAIN_PASS=$(aws ssm get-parameter --name DOMAIN_PASS --with-decryption --query 'Parameter.Value' --output text)",
          "DOMAIN_GROUP=$(aws ssm get-parameter --name DOMAIN_GROUP --query 'Parameter.Value' --output text)",
          "REALM_UPPER=$(echo \"$DOMAIN\" | tr '[:lower:]' '[:upper:]')",
          "echo \"Domain: $DOMAIN\"",
          "echo \"User: $DOMAIN_USER\"",
          "echo \"Group: $DOMAIN_GROUP\"",
          "echo \"Realm: $REALM_UPPER\"",
          "# Export variables for next steps",
          "echo \"export DOMAIN='$DOMAIN'\" > /tmp/domain_vars.sh",
          "echo \"export DOMAIN_USER='$DOMAIN_USER'\" >> /tmp/domain_vars.sh",
          "echo \"export DOMAIN_PASS='$DOMAIN_PASS'\" >> /tmp/domain_vars.sh", 
          "echo \"export DOMAIN_GROUP='$DOMAIN_GROUP'\" >> /tmp/domain_vars.sh",
          "echo \"export REALM_UPPER='$REALM_UPPER'\" >> /tmp/domain_vars.sh"
        ]
      }
    },
    {
      "action": "aws:runShellScript",
      "name": "InstallRequiredPackages",
      "description": "Install required packages for domain join",
      "inputs": {
        "timeoutSeconds": "600",
        "runCommand": [
          "#!/bin/bash",
          "set -e",
          "source /tmp/domain_vars.sh",
          "echo \"[2/9] Installing required packages...\"",
          "dnf install -y realmd sssd oddjob oddjob-mkhomedir adcli samba-common samba-common-tools krb5-workstation openldap-clients",
          "echo \"Packages installed successfully\""
        ]
      }
    },
    {
      "action": "aws:runShellScript",
      "name": "JoinDomain",
      "description": "Join the Linux instance to Active Directory domain",
      "inputs": {
        "timeoutSeconds": "300",
        "runCommand": [
          "#!/bin/bash",
          "set -e",
          "source /tmp/domain_vars.sh",
          "echo \"[3/9] Joining domain $DOMAIN as $DOMAIN_USER...\"",
          "echo \"$DOMAIN_PASS\" | realm join --user=\"$DOMAIN_USER\" \"$DOMAIN\"",
          "echo \"Domain join completed\""
        ]
      }
    },
    {
      "action": "aws:runShellScript",
      "name": "BackupConfigFiles",
      "description": "Backup current configuration files",
      "inputs": {
        "timeoutSeconds": "60",
        "runCommand": [
          "#!/bin/bash",
          "set -e",
          "echo \"[4/9] Backing up current configuration files...\"",
          "SSHD_CONFIG='/etc/ssh/sshd_config'",
          "SSSD_CONFIG='/etc/sssd/sssd.conf'",
          "cp \"$SSSD_CONFIG\" \"$SSSD_CONFIG.bak_$(date +%F_%H%M%S)\" 2>/dev/null || true",
          "cp \"$SSHD_CONFIG\" \"$SSHD_CONFIG.bak_$(date +%F_%H%M%S)\" 2>/dev/null || true",
          "echo \"Configuration files backed up\""
        ]
      }
    },
    {
      "action": "aws:runShellScript",
      "name": "ConfigureSSSD",
      "description": "Generate new SSSD configuration",
      "inputs": {
        "timeoutSeconds": "120",
        "runCommand": [
          "#!/bin/bash",
          "set -e",
          "source /tmp/domain_vars.sh",
          "echo \"[5/9] Creating new sssd.conf...\"",
          "SSSD_CONFIG='/etc/sssd/sssd.conf'",
          "cat > \"$SSSD_CONFIG\" <<EOF",
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
          "chmod 600 \"$SSSD_CONFIG\"",
          "echo \"SSSD configuration created\""
        ]
      }
    },
    {
      "action": "aws:runShellScript",
      "name": "RestartSSSD",
      "description": "Restart SSSD service to apply new configuration",
      "inputs": {
        "timeoutSeconds": "120",
        "runCommand": [
          "#!/bin/bash",
          "set -e",
          "echo \"[6/9] Restarting SSSD to apply new configuration...\"",
          "systemctl restart sssd",
          "systemctl enable sssd",
          "echo \"SSSD restarted and enabled\""
        ]
      }
    },
    {
      "action": "aws:runShellScript",
      "name": "ConfigureSSH",
      "description": "Configure SSH for domain authentication",
      "inputs": {
        "timeoutSeconds": "180",
        "runCommand": [
          "#!/bin/bash",
          "set -e",
          "source /tmp/domain_vars.sh",
          "echo \"[7/9] Updating SSH configuration...\"",
          "SSHD_CONFIG='/etc/ssh/sshd_config'",
          "# Enable password authentication",
          "sed -i 's/^#\\\\?PasswordAuthentication.*/PasswordAuthentication yes/' \"$SSHD_CONFIG\"",
          "# Configure AllowGroups",
          "if grep -q '^AllowGroups' \"$SSHD_CONFIG\"; then",
          "    sed -i \"s/^AllowGroups.*/AllowGroups $DOMAIN_GROUP/\" \"$SSHD_CONFIG\"",
          "else",
          "    echo \"AllowGroups $DOMAIN_GROUP\" >> \"$SSHD_CONFIG\"",
          "fi",
          "# Configure other SSH settings",
          "grep -q '^ChallengeResponseAuthentication' \"$SSHD_CONFIG\" || echo \"ChallengeResponseAuthentication yes\" >> \"$SSHD_CONFIG\"",
          "grep -q '^UsePAM' \"$SSHD_CONFIG\" || echo \"UsePAM yes\" >> \"$SSHD_CONFIG\"",
          "echo \"SSH configuration updated\""
        ]
      }
    },
    {
      "action": "aws:runShellScript",
      "name": "RestartSSH",
      "description": "Restart SSH service to apply configuration",
      "inputs": {
        "timeoutSeconds": "60",
        "runCommand": [
          "#!/bin/bash",
          "set -e",
          "echo \"[8/9] Restarting SSH to apply configuration...\"",
          "systemctl restart sshd",
          "systemctl enable sshd",
          "echo \"SSH restarted and enabled\""
        ]
      }
    },
    {
      "action": "aws:runShellScript",
      "name": "ConfigureSudoers",
      "description": "Configure sudo access for domain group",
      "inputs": {
        "timeoutSeconds": "60",
        "runCommand": [
          "#!/bin/bash",
          "set -e",
          "source /tmp/domain_vars.sh",
          "echo \"[9/9] Granting sudo permissions to AD group $DOMAIN_GROUP...\"",
          "echo \"%$DOMAIN_GROUP ALL=(ALL) ALL\" > \"/etc/sudoers.d/$DOMAIN_GROUP\"",
          "chmod 440 \"/etc/sudoers.d/$DOMAIN_GROUP\"",
          "echo \"Sudo access configured for group: $DOMAIN_GROUP\"",
          "# Cleanup temporary files",
          "rm -f /tmp/domain_vars.sh",
          "echo \"Domain join completed. SSH and sudo access configured for AD group: $DOMAIN_GROUP\""
        ]
      }
    }
  ]
}
DOC
}