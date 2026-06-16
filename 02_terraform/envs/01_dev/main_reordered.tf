############################################
# 00. PROVIDERS
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

############################################
# 01. DATA SOURCES (AMI / AZ / CF ZONE)
############################################
data "aws_ami" "latest_al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
}

data "aws_availability_zones" "available" { state = "available" }

data "cloudflare_zones" "main" {
  name = var.domain_name
}

locals {
  zone_id = data.cloudflare_zones.main.result[0].id
}

############################################
# 02. TAILSCALE EC2 JOIN KEY
############################################
resource "tailscale_tailnet_key" "ec2_join_key" {
  reusable      = true
  ephemeral     = true
  preauthorized = true
  expiry        = 3600
}

############################################
# 03. VPC/IGW
############################################
module "project02_vpc" {
  source     = "../../modules/vpc"
  cidr_block = "10.0.0.0/16"
  name       = "project02-vpc"
}

module "igw" {
  source = "../../modules/internet-gateway"
  vpc_id = module.project02_vpc.vpc_id
  name   = "project02-igw"
}

############################################
# 04. SUBNETS (Private: infra/was/db, Public: nat/alb-a/alb-b)
############################################
module "project02_private_subnet_infra" {
  source        = "../../modules/subnet"
  vpc_id        = module.project02_vpc.vpc_id
  cidr_block    = "10.0.10.0/24"
  az            = data.aws_availability_zones.available.names[0]
  map_public_ip = false
  name          = "project02-private-infra"
}

module "project02_private_subnet_was_a" {
  source        = "../../modules/subnet"
  vpc_id        = module.project02_vpc.vpc_id
  cidr_block    = "10.0.20.0/24"
  az            = data.aws_availability_zones.available.names[0]
  map_public_ip = false
  name          = "project02-private-was-a"
}

module "project02_private_subnet_was_b" {
  source        = "../../modules/subnet"
  vpc_id        = module.project02_vpc.vpc_id
  cidr_block    = "10.0.21.0/24"
  az            = data.aws_availability_zones.available.names[1]
  map_public_ip = false
  name          = "project02-private-was-b"
}


module "project02_private_subnet_db" {
  source        = "../../modules/subnet"
  vpc_id        = module.project02_vpc.vpc_id
  cidr_block    = "10.0.30.0/24"
  az            = data.aws_availability_zones.available.names[0]
  map_public_ip = false
  name          = "project02-private-db"
}

module "project02_public_subnet_nat" {
  source        = "../../modules/subnet"
  vpc_id        = module.project02_vpc.vpc_id
  cidr_block    = "10.0.1.0/24"
  az            = data.aws_availability_zones.available.names[0]
  map_public_ip = true
  name          = "project02-public-nat"
}

module "project02_public_subnet_alb_a" {
  source        = "../../modules/subnet"
  vpc_id        = module.project02_vpc.vpc_id
  cidr_block    = "10.0.2.0/24"
  az            = data.aws_availability_zones.available.names[0]
  map_public_ip = true
  name          = "project02-public-alb-a"
}

module "project02_public_subnet_alb_b" {
  source        = "../../modules/subnet"
  vpc_id        = module.project02_vpc.vpc_id
  cidr_block    = "10.0.3.0/24"
  az            = data.aws_availability_zones.available.names[1]
  map_public_ip = true
  name          = "project02-public-alb-b"
}

############################################
# 05. NAT INSTANCE
############################################
resource "aws_security_group" "nat_sg" {
  vpc_id = module.project02_vpc.vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [module.project02_vpc.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "nat_instance" {
  ami                         = data.aws_ami.latest_al2023.id
  instance_type               = "t3.micro"
  subnet_id                   = module.project02_public_subnet_nat.subnet_id
  associate_public_ip_address = true

  source_dest_check      = false
  vpc_security_group_ids = [aws_security_group.nat_sg.id]

  user_data = <<-EOF
    #!/bin/bash -eux
    echo 1 > /proc/sys/net/ipv4/ip_forward
    dnf install -y iptables iptables-services
    systemctl enable --now iptables
    iptables -P FORWARD ACCEPT
    iptables -I FORWARD -j ACCEPT
    iptables -t nat -A POSTROUTING -s ${module.project02_vpc.cidr_block} -j MASQUERADE
    service iptables save
  EOF

  depends_on = [module.igw]
  tags       = { Name = "nat-instance" }
}

##탄력 아이피 적용시 주석제거
# resource "aws_eip" "nat" {
#   domain = "vpc"
# }
# resource "aws_eip_association" "nat" {
#   instance_id   = aws_instance.nat_instance.id
#   allocation_id = aws_eip.nat.id
# }

############################################
# 06. ROUTE TABLES
############################################
# Public RT
resource "aws_route_table" "public_rt" {
  vpc_id = module.project02_vpc.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = module.igw.igw_id
  }
}
resource "aws_route_table_association" "public_nat_rt" {
  subnet_id      = module.project02_public_subnet_nat.subnet_id
  route_table_id = aws_route_table.public_rt.id
}
resource "aws_route_table_association" "alb_a" {
  subnet_id      = module.project02_public_subnet_alb_a.subnet_id
  route_table_id = aws_route_table.public_rt.id
}
resource "aws_route_table_association" "alb_b" {
  subnet_id      = module.project02_public_subnet_alb_b.subnet_id
  route_table_id = aws_route_table.public_rt.id
}

# Private RT → NAT 인스턴스
resource "aws_route_table" "private_rt" {
  vpc_id = module.project02_vpc.vpc_id

  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_instance.nat_instance.primary_network_interface_id
  }
}
resource "aws_route_table_association" "infra_rt" {
  subnet_id      = module.project02_private_subnet_infra.subnet_id
  route_table_id = aws_route_table.private_rt.id
}
resource "aws_route_table_association" "was_a_rt" {
  subnet_id      = module.project02_private_subnet_was_a.subnet_id
  route_table_id = aws_route_table.private_rt.id
}
resource "aws_route_table_association" "was_b_rt" {
  subnet_id      = module.project02_private_subnet_was_b.subnet_id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "db_rt" {
  subnet_id      = module.project02_private_subnet_db.subnet_id
  route_table_id = aws_route_table.private_rt.id
}

############################################
# 07. SECURITY GROUPS
############################################
module "project02_infra_sg" {
  source = "../../modules/security-group"
  name   = "project02-infra-sg"
  vpc_id = module.project02_vpc.vpc_id

  ingress_rules = [
    { from_port = 22, to_port = 22, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "SSH" },
    { from_port = 80, to_port = 80, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "HTTP" },
    { from_port = -1, to_port = -1, protocol = "icmp", cidr_blocks = [module.project02_vpc.cidr_block], description = "ICMP" }
  ]
  egress_rules = [
    { from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["0.0.0.0/0"] }
  ]
}

module "project02_was_sg" {
  source = "../../modules/security-group"
  name   = "project02-was-sg"
  vpc_id = module.project02_vpc.vpc_id

  ingress_rules = [
    { from_port = 22, to_port = 22, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "SSH" },
    { from_port = 80, to_port = 80, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "HTTP" },
	{ from_port = 443, to_port = 443, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "HTTP" },
    { from_port = -1, to_port = -1, protocol = "icmp", cidr_blocks = [module.project02_vpc.cidr_block], description = "ICMP" }
  ]
  egress_rules = [
    { from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["0.0.0.0/0"] }
  ]
}

module "project02_db_sg" {
  source = "../../modules/security-group"
  name   = "project02-db-sg"
  vpc_id = module.project02_vpc.vpc_id

  ingress_rules = [
    {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      # 만약 서브넷 모듈에 cidr_block output 이 없다면
      # 하드코딩으로 directly 입력해 주세요.
      cidr_blocks = ["10.0.10.0/24"]
      # ← 여기서 한글 화살표(→) 대신 ASCII -> 로 변경
      description = "WAS to DB"
    },
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "SSH"
    },
    {
      from_port   = -1
      to_port     = -1
      protocol    = "icmp"
      cidr_blocks = ["10.0.0.0/16"]
      description = "ICMP (internal test)"
    }
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

module "project02_alb_sg" {
  source = "../../modules/security-group"
  name   = "project02-alb-sg"
  vpc_id = module.project02_vpc.vpc_id

  ingress_rules = [
    { from_port = 80, to_port = 80, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "HTTP" },
    { from_port = 443, to_port = 443, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "HTTPS" }
  ]
  egress_rules = [
    { from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["0.0.0.0/0"] }
  ]
}

############################################
# 08. KEYPAIR
############################################
module "project02_infra_ec2_key" {
  source   = "../../modules/keypair"
  key_name = "project02-infra-key"
}
module "project02_was_ec2_key" {
  source   = "../../modules/keypair"
  key_name = "project02-was-key"
}
module "project02_db_ec2_key" {
  source   = "../../modules/keypair"
  key_name = "project02-db-key"
}

############################################
# 09. IAM ROLE & INSTANCE PROFILE (SSM)
############################################
resource "aws_iam_role" "ssm_role" {
  name = "project02-ssm-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_instance_profile" "ssm_profile" {
  name = "project02-ssm-profile"
  role = aws_iam_role.ssm_role.name
}

############################################
# 10. EC2 INSTANCES (Infra + WAS1 + WAS2 + DB)
############################################
module "project02_infra_ec2" {
  source               = "../../modules/ec2"
  instance_type        = "t3.micro"
  subnet_id            = module.project02_private_subnet_infra.subnet_id
  security_group_ids   = [module.project02_infra_sg.sg_id]
  key_name             = module.project02_infra_ec2_key.key_name
  name                 = "project02-infra"
  iam_instance_profile = aws_iam_instance_profile.ssm_profile.name

  role   = "infra"
  env    = "prod"

  source_dest_check      = false

  # NAT + private_rt 생성 완료 후에만 실행
  depends_on = [
    aws_instance.nat_instance,
    aws_route_table.private_rt
  ]

  user_data = <<-EOF
    #!/bin/bash -eux

    echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
    echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
    sudo sysctl -p /etc/sysctl.d/99-tailscale.conf

    until curl -s https://pkgs.tailscale.com >/dev/null; do sleep 5; done
    curl -fsSL https://tailscale.com/install.sh | sh
    systemctl enable --now tailscaled
    sysctl --system
    tailscale up \
      --auth-key=${tailscale_tailnet_key.ec2_join_key.key} \
      --hostname=project02 \
      --advertise-routes=${module.project02_vpc.cidr_block} \
      --accept-routes \
      --ssh
  EOF
}

module "project02_was01_ec2" {
  source               = "../../modules/ec2"
  instance_type        = "t3.micro"
  subnet_id            = module.project02_private_subnet_was_a.subnet_id
  security_group_ids   = [module.project02_was_sg.sg_id]
  key_name             = module.project02_was_ec2_key.key_name
  name                 = "project02-was01"
  iam_instance_profile = aws_iam_instance_profile.ssm_profile.name
  
  role   = "was"
  env    = "prod"


}

module "project02_was02_ec2" {
  source               = "../../modules/ec2"
  instance_type        = "t3.micro"
  subnet_id            = module.project02_private_subnet_was_b.subnet_id
  security_group_ids   = [module.project02_was_sg.sg_id]
  key_name             = module.project02_was_ec2_key.key_name
  name                 = "project02-was02"
  iam_instance_profile = aws_iam_instance_profile.ssm_profile.name

  role   = "was"
  env    = "prod"
}

module "project02_db_ec2" {
  source               = "../../modules/ec2"
  instance_type        = "t3.micro"
  subnet_id            = module.project02_private_subnet_db.subnet_id
  security_group_ids   = [module.project02_db_sg.sg_id]
  key_name             = module.project02_db_ec2_key.key_name
  name                 = "project02-db"
  iam_instance_profile = aws_iam_instance_profile.ssm_profile.name

  role   = "db"
  env    = "prod"
}

############################################
# 11. TAILSCALE ROUTE 승인
############################################
resource "time_sleep" "wait_for_tailscale_sync" {
  depends_on      = [module.project02_infra_ec2]
  create_duration = "180s"
}

data "tailscale_device" "my_ec2_device" {
   hostname   = "project02"
   wait_for   = "300s"
   depends_on = [time_sleep.wait_for_tailscale_sync]
}

resource "tailscale_device_subnet_routes" "approve_vpc_routes" {
   device_id = data.tailscale_device.my_ec2_device.id
   routes    = [module.project02_vpc.cidr_block]
}

############################################
# 12. APPLICATION LOAD BALANCER (ALB) 생성
############################################
module "project02_alb" {
  source = "../../modules/alb"
  name   = "project02-alb"
  vpc_id = module.project02_vpc.vpc_id
  subnets = [
    module.project02_public_subnet_alb_a.subnet_id,
    module.project02_public_subnet_alb_b.subnet_id
  ]
  security_groups = [module.project02_alb_sg.sg_id]
}

# WAS1 / WAS2를 Target Group에 붙입니다
resource "aws_lb_target_group_attachment" "tg_was1" {
  target_group_arn = module.project02_alb.tg_arn
  target_id        = module.project02_was01_ec2.instance_id
  port             = 80
}
resource "aws_lb_target_group_attachment" "tg_was2" {
  target_group_arn = module.project02_alb.tg_arn
  target_id        = module.project02_was02_ec2.instance_id
  port             = 80
}

############################################
# 13. ACM 인증서 & DNS 검증 (Cloudflare)
############################################
module "project02_acm" {
  source      = "../../modules/acm"
  domain_name = var.domain_name
}

locals {
  # domain_validation_options 는 set(object) 타입이라
  # tolist() 으로 바꿔야 인덱스 접근이 됩니다.
  dv = tolist(module.project02_acm.domain_validation_options)[0]
}

module "project02_acm_dns" {
  source  = "../../modules/cloudflare-dns"
  zone_id = local.zone_id

  # tolist() 후 0 번째 요소의 각 필드를 꺼내 쓴다
  name    = local.dv.resource_record_name
  type    = local.dv.resource_record_type
  content = local.dv.resource_record_value

  proxied = false
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = module.project02_acm.cert_arn
  validation_record_fqdns = [module.project02_acm_dns.fqdn]
}

############################################
# 14. ALB 리스너 (HTTP→HTTPS / HTTPS→Target Group)
############################################
resource "aws_lb_listener" "http" {
  load_balancer_arn = module.project02_alb.alb_arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = module.project02_alb.alb_arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  certificate_arn = aws_acm_certificate_validation.this.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = module.project02_alb.tg_arn
  }
}

############################################
# 15. CLOUDFLARE DNS – www → ALB DNS
############################################
module "project02_dns" {
  source  = "../../modules/cloudflare-dns"
  zone_id = local.zone_id

  name    = "www"
  type    = "CNAME"
  content = module.project02_alb.dns_name
  proxied = true
}


############################################
# Ansivle - inventory.yml
############################################

resource "local_file" "ansible_inventory_bootstrap" {
	filename = "${path.root}/../../../01_ansible/inventories/bootstrap/inventory.yml"
    content = yamlencode({
        all = {
            children = {
                ykk_infra = {
                    hosts = {
                        "${module.project02_infra_ec2.private_ip}" = {
                            ansible_user = "ubuntu"
                            ansible_ssh_private_key_file = "~/.ssh/${module.project02_infra_ec2_key.key_name}.pem"
                        }
                    }
                }					
                ykk_was = {
                    hosts = {
                        "${module.project02_was01_ec2.private_ip}" = {
                            ansible_user = "ubuntu"
                            ansible_ssh_private_key_file = "~/.ssh/${module.project02_was_ec2_key.key_name}.pem"
                        }

					    "${module.project02_was02_ec2.private_ip}" = {
					      ansible_user = "ubuntu"
					      ansible_ssh_private_key_file = "~/.ssh/${module.project02_was_ec2_key.key_name}.pem"
					    }						
                    }
                }
                ykk_db = {
                    hosts = {
                        "${module.project02_db_ec2.private_ip}" = {
                            ansible_user = "ubuntu"
                            ansible_ssh_private_key_file = "~/.ssh/${module.project02_db_ec2_key.key_name}.pem"
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
	filename = "${path.root}/../../../01_ansible/inventories/dev/inventory.yml"
    content = yamlencode({
        all = {
            children = {
                ykk_infra = {
                    hosts = {
                        "${module.project02_infra_ec2.private_ip}" = {
                            ansible_user = "ykk-admin"
                            ansible_ssh_private_key_file = "~/.ssh/ykkadmin-key.pem"
                        }
                    }
                }					
                ykk_was = {
                    hosts = {
                        "${module.project02_was01_ec2.private_ip}" = {
                            ansible_user = "ykk-admin"
                            ansible_ssh_private_key_file = "~/.ssh/ykkadmin-key.pem"
                        }

					    "${module.project02_was02_ec2.private_ip}" = {
					      ansible_user = "ykk-admin"
					      ansible_ssh_private_key_file = "~/.ssh/ykkadmin-key.pem"
					    }
                    }
                }
                ykk_db = {
                    hosts = {
                        "${module.project02_db_ec2.private_ip}" = {
                            ansible_user = "ykk-admin"
                            ansible_ssh_private_key_file = "~/.ssh/ykkadmin-key.pem"
                        }
                    }
                }				
            }
        }
    })
}

resource "local_file" "ansible_config"{
	filename = "${path.root}/../../../01_ansible/ansible.cfg"
    content = <<-EOF
        [defaults]
        inventory = ./inventories/dev/inventory.yml
        roles_path = ./roles
        host_key_checking = False
    EOF
}


############################################
# 16. OUTPUTS
############################################
output "alb_dns_name" {
  description = "ALB DNS Name"
  value       = module.project02_alb.dns_name
}

output "www_url" {
  description = "Public URL (Cloudflare www record)"
  value       = "https://www.${var.domain_name}"
}

output "instance_was_private_ip" {
  value = module.project02_was01_ec2.private_ip
}
output "instance_db_private_ip" {
  value = module.project02_db_ec2.private_ip
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
  default = "infrastudy.store"
}

variable "cloudflare_api_token" {
  type    = string
  default = ""
}

variable "cloudflare_zone_id" {
  type    = string
  default = ""
}


