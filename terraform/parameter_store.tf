resource "aws_ssm_parameter" "DOMAIN" {
  name  = "DOMAIN"
  type  = "String"
  overwrite = true
  value = "your_domain"
}

resource "aws_ssm_parameter" "DOMAIN_USER" {
  name  = "DOMAIN_USER"
  type  = "String"
  overwrite = true
  value = "user"
}

resource "aws_ssm_parameter" "DOMAIN_PASS" {
  name  = "DOMAIN_PASS"
  type  = "SecureString"
  overwrite = true
  value = "userpassword"
}

resource "aws_ssm_parameter" "DOMAIN_GROUP" {
  name  = "DOMAIN_GROUP"
  type  = "SecureString"
  overwrite = true
  value = "ad_group"
}