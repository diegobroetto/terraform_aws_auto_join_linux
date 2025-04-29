variable "subnet_lambda" {
  description = "Subnet to allocate AWS Lambda"
  type        = list(string)
}

variable "security_group_lambda" {
  description = "Security Group For Lambda"
  type        = list(string)
}

variable "region" {
  description = "Region to deploy"
  type        = string
}