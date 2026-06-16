# AWS Security Group 생성
# ingress / egress 규칙을 dynamic block으로 받아서 유연하게 구성

resource "aws_security_group" "this" {
  # 보안그룹 이름
  name   = var.name
  # Security Grop이 속할 VPC ID
  vpc_id = var.vpc_id

  # =========================
  # Ingress (인바운드 규칙)
  # =========================
  # var.ingress_rules 리스트를 반복하면서 여러 개의 ingress rule 생성  
  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = lookup(ingress.value, "cidr_blocks", null)
      security_groups = lookup(ingress.value, "security_groups", null)
	  description = try(ingress.value.description, null)
    }
  }

  # =========================
  # Egress (아웃바운드 규칙)
  # =========================
  # var.egress_rules 리스트를 반복하면서 여러 개의 egress rule 생성  
  dynamic "egress" {
    for_each = var.egress_rules
    content {
      from_port   = egress.value.from_port
      to_port     = egress.value.to_port
      protocol    = egress.value.protocol
      cidr_blocks = lookup(egress.value, "cidr_blocks", null)
      security_groups = lookup(egress.value, "security_groups", null)
	  description = try(egress.value.description, null)
    }
  }
}