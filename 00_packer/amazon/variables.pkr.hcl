# ./packer/amazon/variables.pkr.hcl

variable "instance_type" { type = string }
variable "aws_region" { type = string }
variable "source_ami" { type = string }
