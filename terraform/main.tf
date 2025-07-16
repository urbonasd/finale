# Configure AWS region
provider "aws" {
  region = "eu-central-1"
}

# Terraform backend configuration
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}

# Create a VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# Create public subnets (two for high availability)
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + 1)  # 10.0.1.0/24 and 10.0.2.0/24
  map_public_ip_on_launch = true
  availability_zone       = element(["eu-central-1a", "eu-central-1b"], count.index)
}

# Create an internet gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

# Create a routing table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

# Assign the routing table to subnets
resource "aws_route_table_association" "a" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Create a security group for ALB (allow inbound HTTP on port 80)
resource "aws_security_group" "alb" {
  name        = "alb-sg"
  description = "Allow inbound traffic to ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create a security group for ECS tasks (allow inbound from ALB on port 3000)
resource "aws_security_group" "ecs_tasks" {
  name        = "ecs-tasks-sg"
  description = "Allow inbound traffic to ECS tasks from ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create IAM role for ECS task execution (required for Fargate to pull images from ECR)
resource "aws_iam_role" "ecs_task_execution" {
  name = "ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# Attach policy to ECS task execution role
resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Create a repository to store the Docker image
resource "aws_ecr_repository" "app" {
  name = "hello-world-app-darius"
}

# Create an ECS cluster
resource "aws_ecs_cluster" "main" {
  name = "hello-world-app-darius-cluster"
}

# Create an application load balancer
resource "aws_lb" "main" {
  name               = "hello-world-app-darius-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
}

# Create LB target group (specify target_type as 'ip' for Fargate)
resource "aws_lb_target_group" "app" {
  name        = "hello-world-app-darius-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
}

# Create LB listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# Define the ECS task (hardcoded container name instead of undefined variable)
resource "aws_ecs_task_definition" "app" {
  family                   = "hello-world-app-darius-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = "hello-world"
      image     = "${aws_ecr_repository.app.repository_url}:latest"
      cpu       = 256
      memory    = 512
      essential = true
      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
        }
      ]
    }
  ])
}

# Create the ECS service
resource "aws_ecs_service" "main" {
  name            = "hello-world-app-darius-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "hello-world"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.http]
}
