resource "aws_ssm_parameter" "DOMAIN" {
  name  = "DOMAIN"
  type  = "String"
  value = "seu_dominio"
}

resource "aws_ssm_parameter" "DOMAIN_USER" {
  name  = "DOMAIN_USER"
  type  = "String"
  value = "user"
}

resource "aws_ssm_parameter" "DOMAIN_PASS" {
  name  = "DOMAIN_PASS"
  type  = "SecureString"
  value = "senha_user"
}