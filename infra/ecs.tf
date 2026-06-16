resource "aws_ecs_cluster" "app" {
  name = local.name
  tags = local.tags
}

resource "aws_ecs_task_definition" "app" {
  family             = local.name
  network_mode       = "host"
  execution_role_arn = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([{
    name   = "app"
    image  = "${aws_ecr_repository.app.repository_url}:latest"
    memory = 512
    portMappings = [{
      containerPort = 8080
      protocol      = "tcp"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"  = aws_cloudwatch_log_group.app.name
        "awslogs-region" = var.aws_region
      }
    }
  }])

  tags = local.tags
}

resource "aws_ecs_service" "app" {
  name            = local.name
  cluster         = aws_ecs_cluster.app.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "EC2"

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  tags = local.tags
}
