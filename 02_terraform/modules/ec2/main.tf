## AWS Linux
# data "aws_ami" "latest_al2023" {
#   most_recent = true
#   owners      = ["amazon"]

#   filter {
#     name   = "name"
#     values = ["al2023-ami-2023*-x86_64"]
#   }
# }

##Ubuntu
data "aws_ami" "ubuntu_24_04" {
  most_recent = true
  owners      = ["099720109477"] 
  
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}


resource "aws_instance" "this" {
  #ami                    = data.aws_ami.latest_al2023.id
  ami                    = data.aws_ami.ubuntu_24_04.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  key_name               = var.key_name
  iam_instance_profile = var.iam_instance_profile

	associate_public_ip_address = var.associate_public_ip_address
	source_dest_check      = var.source_dest_check

  user_data = var.user_data
  
  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  tags = {
    Name     = var.name
    Role     = var.role
    Env      = var.env

    # ⭐ SSM 전용 타겟 태그
    SSMRole  = var.role
  }
}