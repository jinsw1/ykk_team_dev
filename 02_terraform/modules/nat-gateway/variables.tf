variable "subnet_id" {
  description = "Public subnet ID where NAT Gateway will be deployed"
  type        = string
}

variable "name" {
  description = "Name tag for NAT Gateway"
  type        = string
}