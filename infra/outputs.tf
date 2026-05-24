output "instance_public_ip" {
  description = "EC2 public IP"
  value       = aws_instance.app.public_ip
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.app.repository_url
}
