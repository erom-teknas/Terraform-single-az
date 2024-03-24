output "bastian-pub-ip" {
  description = "This is the bastian host in the public subnet:"
  value       = aws_eip.ec2-bastian-eip.public_ip
}
output "ec2-private-ip" {
  description = "This is the private ec2 host in the private subnet:"
  value       = aws_instance.private-ec2.private_ip
}