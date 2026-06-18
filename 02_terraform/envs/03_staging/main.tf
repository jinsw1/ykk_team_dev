############################################
# 00. PROVIDERS (동일)
############################################
terraform {
  required_version = ">=1.14.0, <1.16.0"

  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 6.0" }
    tailscale  = { source = "tailscale/tailscale", version = "0.17.2" }
    cloudflare = { source = "cloudflare/cloudflare", version = "~> 5.0" }
  }
}

provider "aws" { region = "ap-northeast-2" }
provider "tailscale" {
  api_key = var.tailscale_api_key
  tailnet = var.tailnet_name
}
provider "cloudflare" { api_token = var.cloudflare_api_token }

data "cloudflare_zones" "main" {
    name = var.domain_name
}

############################################
# 01. 기존 VPC 가져오기 (중요)
############################################
data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["project02-vpc"]
  }
}

data "aws_subnets" "private_was_a" {
  filter {
    name   = "tag:Name"
    values = ["project02-private-was-a"]
  }
}

data "aws_subnets" "private_was_b" {
  filter {
    name   = "tag:Name"
    values = ["project02-private-was-b"]
  }
}

data "aws_subnets" "private_db" {
  filter {
    name   = "tag:Name"
    values = ["project02-private-db"]
  }
}

data "aws_subnets" "public_alb" {
  filter {
    name   = "tag:Name"
    values = ["project02-public-alb-a"]
  }
}

############################################
# 02. SG (기존 재사용 or staging 전용)
############################################
module "stg_was_sg" {
  source = "../../modules/security-group"
  name   = "stg-was-sg"
  vpc_id = data.aws_vpc.main.id

  ingress_rules = [
    { from_port = 80, to_port = 80, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "HTTP" },
	{ from_port = 22, to_port = 22, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "SSH" }
  ]

  egress_rules = [
    { from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["0.0.0.0/0"] }
  ]
}

module "stg_alb_sg" {
  source = "../../modules/security-group"
  name   = "stg-alb-sg"
  vpc_id = data.aws_vpc.main.id

  ingress_rules = [
    { from_port = 80, to_port = 80, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "HTTP" },
    { from_port = 443, to_port = 443, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "HTTPS" }
  ]

  egress_rules = [
    { from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["0.0.0.0/0"] }
  ]
}

module "stg_db_sg" {
  source = "../../modules/security-group"
  name   = "stg-db-sg"
  vpc_id = data.aws_vpc.main.id

  ingress_rules = [
    {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      security_groups = [module.stg_was_sg.sg_id]
      description = "PostgreSQL from WAS"
    },
	{ from_port = 22, to_port = 22, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "SSH" }
  ]

  egress_rules = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
}

############################################
# 03. STAGING EC2 (WAS)
############################################
module "stg_was01" {
  source        = "../../modules/ec2"
  instance_type = "t3.micro"
  subnet_id          = data.aws_subnets.private_was_a.ids[0]
  security_group_ids = [module.stg_was_sg.sg_id]

  key_name = "project02-was-key"

  name = "stg-was01"
  role = "was"
  env  = "staging"
}

module "stg_was02" {
  source        = "../../modules/ec2"
  instance_type = "t3.micro"
  subnet_id          = data.aws_subnets.private_was_b.ids[0]
  security_group_ids = [module.stg_was_sg.sg_id]

  key_name = "project02-was-key"

  name = "stg-was02"
  role = "was"
  env  = "staging"
}

############################################
# 04. STAGING DB (옵션: 1개 or 재사용 가능)
############################################
module "stg_db" {
  source        = "../../modules/ec2"
  instance_type = "t3.micro"

  subnet_id          = data.aws_subnets.private_db.ids[0]
  security_group_ids = [module.stg_db_sg.sg_id] # DB SG 따로 만들거나 재사용

  key_name = "project02-db-key"

  name = "stg-db"
  role = "db"
  env  = "staging"
}

############################################
# 05. STAGING ALB
############################################

data "aws_subnets" "public_alb_a" {
  filter {
    name   = "tag:Name"
    values = ["project02-public-alb-a"]
  }
}

data "aws_subnets" "public_alb_b" {
  filter {
    name   = "tag:Name"
    values = ["project02-public-alb-b"]
  }
}


module "stg_alb" {
  source = "../../modules/alb"

  name   = "stg-alb"
  vpc_id = data.aws_vpc.main.id

  subnets = [
    data.aws_subnets.public_alb_a.ids[0],
    data.aws_subnets.public_alb_b.ids[0]
  ]

  security_groups = [module.stg_alb_sg.sg_id]
}

resource "aws_lb_target_group_attachment" "stg_was1" {
  target_group_arn = module.stg_alb.tg_arn
  target_id        = module.stg_was01.instance_id
  port             = 80
}

resource "aws_lb_target_group_attachment" "stg_was2" {
  target_group_arn = module.stg_alb.tg_arn
  target_id        = module.stg_was02.instance_id
  port             = 80
}

############################################
# 06. STAGING DNS (Cloudflare)
############################################
module "stg_dns" {
  source  = "../../modules/cloudflare-dns"
  zone_id = data.cloudflare_zones.main.result[0].id

  name    = "staging"
  type    = "CNAME"
  content = module.stg_alb.dns_name
  proxied = true
}





############################################
# Ansivle - inventory.yml
############################################

resource "local_file" "ansible_inventory_bootstrap" {
	filename = "${path.root}/../../../01_ansible/inventories/staging/inventory-bootstrap.yml"
    content = yamlencode({
        all = {
            children = {		
                ykk_was = {
                    hosts = {
                        "${module.stg_was01.private_ip}" = {
                            ansible_user = "ubuntu"
                            ansible_ssh_private_key_file = "~/.ssh/project02-was-key.pem"
                        }

					    "${module.stg_was02.private_ip}" = {
					      ansible_user = "ubuntu"
					      ansible_ssh_private_key_file = "~/.ssh/project02-was-key.pem"
					    }						
                    }
                }
                ykk_db = {
                    hosts = {
                        "${module.stg_db.private_ip}" = {
                            ansible_user = "ubuntu"
                            ansible_ssh_private_key_file = "~/.ssh/project02-db-key.pem"
                        }
                    }
                }				
            }
        }
    })
}

############################################
# Ansivle - inventory.yml
############################################

resource "local_file" "ansible_inventory_dev" {
	filename = "${path.root}/../../../01_ansible/inventories/staging/inventory.yml"
    content = yamlencode({
        all = {
            children = {		
                ykk_was = {
                    hosts = {
                        "${module.stg_was01.private_ip}" = {
                            ansible_user = "ykk-admin"
                            ansible_ssh_private_key_file = "~/.ssh/ykkadmin-key.pem"
                        }

					    "${module.stg_was02.private_ip}" = {
					      ansible_user = "ykk-admin"
					      ansible_ssh_private_key_file = "~/.ssh/ykkadmin-key.pem"
					    }						
                    }
                }
                ykk_db = {
                    hosts = {
                        "${module.stg_db.private_ip}" = {
                            ansible_user = "ykk-admin"
                            ansible_ssh_private_key_file = "~/.ssh/ykkadmin-key.pem"
                        }
                    }
                }				
            }
        }
    })
}


############################################
# 16. OUTPUTS
############################################
output "staging_url" {
  description = "Staging URL"
  value       = "https://staging.${var.domain_name}"
}

output "alb_dns_name" {
  description = "Staging ALB DNS Name"
  value       = module.stg_alb.dns_name
}

output "was01_private_ip" {
  description = "WAS01 Private IP"
  value       = module.stg_was01.private_ip
}

output "was02_private_ip" {
  description = "WAS02 Private IP"
  value       = module.stg_was02.private_ip
}

output "db_private_ip" {
  description = "DB Private IP"
  value       = module.stg_db.private_ip
}

output "www_url" {
  description = "Cloudflare staging URL"
  value       = "https://staging.${var.domain_name}"
}



############################################
# VARIABLES
############################################
variable "host_name" {
  type    = string
  default = "aws-ec2"
}

variable "tailnet_name" {
  type = string
}

variable "tailscale_auth_key" {
  type      = string
  sensitive = true
}

variable "tailscale_api_key" {
  type      = string
  sensitive = true
}

variable "domain_name" {
  type    = string
  default = "dev.infrastudy.store"
}

variable "cloudflare_api_token" {
  type    = string
  default = ""
}

variable "cloudflare_zone_id" {
  type    = string
  default = ""
}