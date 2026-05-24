data "aws_ami" "ecs" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }
}

resource "aws_key_pair" "app" {
  key_name   = "${local.name}-key"
  public_key = file(var.public_key_path)
  tags       = local.tags
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.ecs.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app.id]
  key_name               = aws_key_pair.app.key_name
  iam_instance_profile   = aws_iam_instance_profile.app.name

  user_data = <<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${aws_ecs_cluster.app.name} >> /etc/ecs/ecs.config
  EOF

  tags = merge(local.tags, { Name = "${local.name}-app" })
}
