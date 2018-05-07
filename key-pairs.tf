resource "aws_key_pair" "deployer" {
  key_name = "deploy-${var.workspace}"
  public_key = "${file("~/.ssh/id_ed25519.pub")}"
}