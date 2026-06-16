# Elastic IP 생성 (NAT Gateway용)
resource "aws_eip" "this" {
  domain = "vpc"

  tags = {
    Name = "${var.name}-eip"
  }
}

# NAT Gateway 생성 (Public Subnet에 위치해야 함)
resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.this.id
  subnet_id     = var.subnet_id

  tags = {
    Name = var.name
  }

  depends_on = [aws_eip.this]
}