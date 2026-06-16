# ./packer/amazon/build.pkr.hcl

build {
    sources = ["source.amazon-ebs.ykk_image"]
    provisioner "ansible" {
        playbook_file   = "./setup.yml"
        user            = "ec2-user"
        use_proxy       = false
    }
}
