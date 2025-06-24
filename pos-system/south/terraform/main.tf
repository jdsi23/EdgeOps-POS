provider "aws" {
  region = var.region
}

resource "aws_ecs_cluster" "pos_cluster" {
  name = "pos-cluster-south"
}

resource "aws_dynamodb_table" "store1_table" {
  name         = "pos-store1-south"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "order_id"

  attribute {
    name = "order_id"
    type = "S"
  }
}

resource "aws_dynamodb_table" "store2_table" {
  name         = "pos-store2-south"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "order_id"

  attribute {
    name = "order_id"
    type = "S"
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "pos-ecs-task-execution-role-south"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_security_group" "ecs_sg" {
  name        = "pos-ecs-sg-south"
  description = "Allow inbound HTTP to ECS tasks"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 5000
    to_port     = 5000
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

resource "aws_ecs_task_definition" "store1_task" {
  family                   = "pos-store1-task-south"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "pos-store1"
      image     = var.store1_image
      essential = true
      portMappings = [{
        containerPort = 5000
        protocol      = "tcp"
      }]
      environment = [
        { name = "DYNAMODB_TABLE", value = aws_dynamodb_table.store1_table.name },
        { name = "REGION", value = var.region },
        { name = "MASTER_DB_TABLE", value = var.master_db_table }
      ]
    }
  ])
}

resource "aws_ecs_task_definition" "store2_task" {
  family                   = "pos-store2-task-south"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "pos-store2"
      image     = var.store2_image
      essential = true
      portMappings = [{
        containerPort = 5000
        protocol      = "tcp"
      }]
      environment = [
        { name = "DYNAMODB_TABLE", value = aws_dynamodb_table.store2_table.name },
        { name = "REGION", value = var.region },
        { name = "MASTER_DB_TABLE", value = var.master_db_table }
      ]
    }
  ])
}

resource "aws_ecs_service" "store1_service" {
  name            = "pos-store1-service-south"
  cluster         = aws_ecs_cluster.pos_cluster.id
  task_definition = aws_ecs_task_definition.store1_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = var.subnets
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
}

resource "aws_ecs_service" "store2_service" {
  name            = "pos-store2-service-south"
  cluster         = aws_ecs_cluster.pos_cluster.id
  task_definition = aws_ecs_task_definition.store2_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = var.subnets
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
}

variable "vpc_id" {
  description = "VPC ID where ECS will be deployed"
  type        = string
}

variable "subnets" {
  description = "List of subnet IDs for ECS tasks"
  type        = list(string)
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-1"
}

variable "store1_image" {
  description = "Docker image URI for Store 1"
  type        = string
}

variable "store2_image" {
  description = "Docker image URI for Store 2"
  type        = string
}

variable "master_db_table" {
  description = "Master DynamoDB table name"
  type        = string
  default     = "pos-master-db"
}
