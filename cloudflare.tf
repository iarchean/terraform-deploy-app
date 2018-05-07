provider "cloudflare" {
  email = "zephyr422@gmail.com"
  api_token = "${var.cloudflare_apitoken}"
}

resource "cloudflare_record" "aws-test" {
  zone_id = "${var.cloudflare_zone_id}"
  name    = "aws-test"
  value   = "${aws_instance.app.public_ip}"
  type    = "A"
  proxied = false

  depends_on = [
    aws_instance.app
  ]
}
