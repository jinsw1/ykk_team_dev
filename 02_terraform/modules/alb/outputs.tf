output "alb_arn" {
  value = aws_lb.this.arn
}

output "tg_arn" {
  value = aws_lb_target_group.this.arn
}

output "dns_name" {
  value = aws_lb.this.dns_name
}