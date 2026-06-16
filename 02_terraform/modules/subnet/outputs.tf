output "subnet_id" {
  value = aws_subnet.this.id
}

output "cidr_block" {
  description = "The CIDR block of this subnet"
  value       = var.cidr_block
}