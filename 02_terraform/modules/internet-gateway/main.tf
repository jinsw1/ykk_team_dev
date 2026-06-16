# VPC에 인터넷 연결을 제공하는 게이트웨이
# AWS Internet Gateway 생성 리소스
resource "aws_internet_gateway" "this" {
  vpc_id = var.vpc_id

  tags = {
    Name = var.name
  }
}