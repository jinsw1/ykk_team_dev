output "vpc_id" {
  value = aws_vpc.this.id
}

output "cidr_block" {
  value = var.cidr_block
}