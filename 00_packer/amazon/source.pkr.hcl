# ./packer/amazon/source.pkr.hcl

source "amazon-ebs" "ykk_image" {
    ami_name        = "ami-ykk-{{timestamp}}"
    instance_type   = var.instance_type
    region          = var.aws_region
    source_ami      = var.source_ami
    ssh_username    = "ec2-user"
}
