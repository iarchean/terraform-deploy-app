/* Setup our aws provider */
provider "aws" {
  access_key  = "${var.access_key}"
  secret_key  = "${var.secret_key}"
  region      = "${var.region}"
}
resource "aws_instance" "app" {
  ami           = "${var.aws_ami}"
  instance_type = "${var.aws_type}"
  security_groups = ["${aws_security_group.app.name}"]
  key_name = "${aws_key_pair.deployer.key_name}"
  connection {
    host = self.public_ip
    user = "ubuntu"
    private_key = "${file("~/.ssh/id_ed25519")}"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo apt update",
      "sudo apt-get install ca-certificates curl gnupg lsb-release",
      "sudo mkdir -p /etc/apt/keyrings",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg",
      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
      "sudo apt-get update",
      "sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin",
      "sudo docker run -p 21000:21000 -p 21000:21000/udp -d --restart always --name=snell archean/docker-snell-server",
      "sudo docker logs snell"
    ]
  }
  tags = { 
    Name = "${var.workspace}-primary"
  }
}

