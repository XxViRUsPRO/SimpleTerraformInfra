output "prv_ip_back" {
  value = aws_instance.project1-back.private_ip
}

output "pub_ip_front" {
  value = aws_instance.project1-front.public_ip
}
