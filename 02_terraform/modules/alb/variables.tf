variable "name" {}
variable "vpc_id" {}
variable "subnets" { type = list(string) }
variable "security_groups" { type = list(string) }

variable "target_port" {
  default = 80
}

variable "health_check_path" {
  default = "/"
}