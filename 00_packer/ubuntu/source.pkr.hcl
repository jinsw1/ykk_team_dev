# ./packer/ubuntu/source.pkr.hcl

source "amazon-ebs" "ykk_image_ubuntu" {
    ami_name        = "ami-ykk-ubuntu-{{timestamp}}"
    instance_type   = var.instance_type
    region          = var.aws_region
    source_ami      = var.source_ami
    ssh_username    = "ubuntu"
}
