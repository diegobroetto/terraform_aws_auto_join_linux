resource "aws_ssm_document" "aws_join_linux" {
  name          = "aws_join_linux"
  document_type = "Command"

  content = <<DOC
    {
      "schemaVersion": "2.2",
      "description": "Ingressar Maquina Linux no Dominio",
      "mainSteps": [
        {
          "action": "aws:runShellScript",
          "name": "JoinDomainAndUpdateSSH",
          "inputs": {
            "runCommand": [
              "#!/bin/bash",
              "# Variáveis",
              "DOMAIN=$(aws ssm get-parameter --name DOMAIN --query \"Parameter.Value\" --output text)",
              "DOMAIN_USER=$(aws ssm get-parameter --name DOMAIN_USER --query \"Parameter.Value\" --output text)",
              "DOMAIN_PASS=$(aws ssm get-parameter --name DOMAIN_PASS --with-decryption --query \"Parameter.Value\" --output text)",
              "SSHD_CONFIG='/etc/ssh/sshd_config'",
              "",
              "echo 'Instalando dependências...'",
              "yum install -y realmd sssd oddjob oddjob-mkhomedir adcli samba-common samba-common-tools krb5-workstation openldap-clients",
              "",
              "echo 'Fazendo Join no Domínio...'",
              "echo \"$DOMAIN_PASS\" | realm join --user=\"$DOMAIN_USER\" \"$DOMAIN\"",
              "",
              "echo 'Verificando Join...'",
              "realm discover \"$DOMAIN\"",
              "",
              "echo 'Backup do arquivo $$SSHD_CONFIG...'",
              "cp $$SSHD_CONFIG $$SSHD_CONFIG.bak",
              "",
              "echo 'Parando serviço SSH...'",
              "systemctl stop sshd",
              "",
              "echo 'Modificando parâmetros SSH...'",
              "sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' \"$$SSHD_CONFIG\"",
              "echo 'ChallengeResponseAuthentication yes' >> \"$$SSHD_CONFIG\"",
              "echo 'UsePAM yes' >> \"$$SSHD_CONFIG\"",
              "",
              "echo 'Iniciando serviço SSH...'",
              "systemctl start sshd",
              "",
              "echo 'Serviço iniciado e parâmetros alterados!'"
            ]
          }
        }
      ]
    }
DOC
}
