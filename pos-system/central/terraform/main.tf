provider "aws" {
  region = var.region
}

##############################
# ECS Cluster
##############################
resource "aws_ecs_cluster" "pos_cluster" {
  name = "pos-cluster-central"
}

##############################
# DynamoDB Tables for Stores
##############################
resource "aws_dynamodb_table" "store1_table" {
  name         = "pos-store1-central"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "order_id"

  attribute {
    name = "order_id"
    type = "S"
  }
}

resource "aws_dynamodb_table" "store2_table" {
  name         = "pos-store2-central"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "order_id"

  attribute {
    name = "order_id"
    type = "S"
  }
}

##############################
# Master DynamoDB Table
##############################
resource "aws_dynamodb_table" "master_table" {
  name         = "pos-master-db"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "order_id"

  attribute {
    name = "order_id"
    type = "S"
  }
}

##############################
# IAM Role for ECS Task Execution
##############################
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "pos-ecs-task-execution-role-central"

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

##############################
# Security Group (allow HTTP inbound on port 5000)
##############################
resource "aws_security_group" "ecs_sg" {
  name        = "pos-ecs-sg-central"
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

##############################
# ECS Task Definition for Store 1
##############################
resource "aws_ecs_task_definition" "store1_task" {
  family                   = "pos-store1-task-central"
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
        { name = "MASTER_DB_TABLE", value = aws_dynamodb_table.master_table.name }
      ]
    }
  ])
}

##############################
# ECS Task Definition for Store 2
##############################
resource "aws_ecs_task_definition" "store2_task" {
  family                   = "pos-store2-task-central"
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
        { name = "MASTER_DB_TABLE", value = aws_dynamodb_table.master_table.name }
      ]
    }
  ])
}

##############################
# ECS Service for Store 1
##############################
resource "aws_ecs_service" "store1_service" {
  name            = "pos-store1-service-central"
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

##############################
# ECS Service for Store 2
##############################
resource "aws_ecs_service" "store2_service" {
  name            = "pos-store2-service-central"
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
