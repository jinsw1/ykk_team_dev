output "nat_gateway_id" {
  value = aws_nat_gateway.this.id
}

output "eip" {
  value = aws_eip.this.public_ip
}