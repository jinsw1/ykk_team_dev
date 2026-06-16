variable "instance_type" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "security_group_ids" {
  type = list(string)
}

variable "key_name" {
  type = string
}

variable "name" {
  type = string
}

variable "root_volume_size" {
  type    = number
  default = 10
}

variable "tags" {
  description = "어떤 EC2(bastion,was,db)인지 알기 위해 인스턴스에 추가할 태그"
  type        = map(string)
  default     = {}
}

variable "iam_instance_profile" {
  description = "bastion 서버(for 프로메테우스)가 EC2 목록을 조회하기 위해 사용할 IAM 인스턴스 프로파일의 이름"
  type        = string
  default     = null
}

variable "user_data" {
  type    = string
  default = ""
}

variable "source_dest_check" {
  type    = bool
  default = true
}

variable "associate_public_ip_address" {
  type    = bool
  default = null
}