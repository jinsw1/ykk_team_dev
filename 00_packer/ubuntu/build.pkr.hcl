# ./packer/ubuntu/build.pkr.hcl

build {
    sources = ["source.amazon-ebs.ykk_image_ubuntu"]
    provisioner "ansible" {
        playbook_file   = "./setup.yml"
        user            = "ubuntu"
        use_proxy       = false
    }
}
