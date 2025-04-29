resource "aws_ssm_parameter" "DOMAIN" {
  name  = "DOMAIN"
  type  = "String"
  value = "your_domain"
}

resource "aws_ssm_parameter" "DOMAIN_USER" {
  name  = "DOMAIN_USER"
  type  = "String"
  value = "user"
}

resource "aws_ssm_parameter" "DOMAIN_PASS" {
  name  = "DOMAIN_PASS"
  type  = "SecureString"
  value = "userpassword"
}

resource "aws_ssm_parameter" "DOMAIN_GROUP" {
  name  = "DOMAIN_PASS"
  type  = "SecureString"
  value = "ad_group"
}