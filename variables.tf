variable "subnet_lambda" {
  description = "subnet onde esta alocado o AD"
  type        = list(string)
}

variable "security_group_lambda" {
  description = "sg com liberacoes necessarias"
  type        = list(string)
}