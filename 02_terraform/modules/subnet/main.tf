# AWS Subnet 생성 리소스
# VPC 내부에 네트워크를 분리하기 위한 서브넷 정의
resource "aws_subnet" "this" {
  vpc_id            = var.vpc_id
  cidr_block        = var.cidr_block
  availability_zone = var.az

  map_public_ip_on_launch = var.map_public_ip

  tags = {
    Name = var.name
  }
}