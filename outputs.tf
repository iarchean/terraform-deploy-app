output "ipmaster" {
  value = aws_instance.app.public_ip
}