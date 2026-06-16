# 1. RSA Private Key 생성 (로컬에서 생성됨)
resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# 2. AWS Key Pair 등록
resource "aws_key_pair" "this" {
  key_name   = var.key_name
  public_key = tls_private_key.this.public_key_openssh
}

# 3. Private Key 파일 로컬 저장 (중요)
resource "local_file" "private_key" {
  content         = tls_private_key.this.private_key_pem
  #filename       = "${path.module}/${var.key_name}.pem"
  filename        = pathexpand("~/.ssh/${var.key_name}.pem")
  file_permission = "0400"
}