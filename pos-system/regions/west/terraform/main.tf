terraform {
  backend "local" {
    path = "../../root/terraform.tfstate"
  }
}

provider "aws" {
  region = "us-west-2"
}

data "terraform_remote_state" "root" {
  backend = "local"
  config = {
    path = "../../root/terraform.tfstate"
  }
}

data "aws_caller_identity" "current" {}

resource "aws_dynamodb_table" "store1_table" {
  name         = "pos-store1-west"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "order_id"

  attribute {
    name = "order_id"
    type = "S"
  }

  stream_enabled   = true
  stream_view_type = "NEW_IMAGE"
}

resource "aws_dynamodb_table" "store2_table" {
  name         = "pos-store2-west"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "order_id"

  attribute {
    name = "order_id"
    type = "S"
  }

  stream_enabled   = true
  stream_view_type = "NEW_IMAGE"
}

data "aws_iam_policy_document" "ecs_task_exec_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "ecs-task-execution-west"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_exec_assume.json
}

resource "aws_iam_role_policy_attachment" "ecs_exec_attach" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_security_group" "ecs_sg" {
  name        = "ecs-sg-west"
  description = "Allow HTTP inbound to ECS tasks"
  vpc_id      = data.terraform_remote_state.root.outputs.vpc_id

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

resource "aws_ecs_cluster" "pos_cluster" {
  name = "pos-cluster-west"
}

resource "aws_ecs_task_definition" "store1_task" {
  family                   = "store1-task-west"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "store1"
      image     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.us-west-2.amazonaws.com/pos-store1:latest"
      essential = true
      portMappings = [{ containerPort = 80, hostPort = 80 }]
      environment = [
        { name = "DYNAMODB_TABLE",  value = aws_dynamodb_table.store1_table.name },
        { name = "MASTER_DB_TABLE", value = data.terraform_remote_state.root.outputs.master_table_name }
      ]
    }
  ])
}

resource "aws_ecs_service" "store1_service" {
  name            = "pos-store1-service-west"
  cluster         = aws_ecs_cluster.pos_cluster.id
  task_definition = aws_ecs_task_definition.store1_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.terraform_remote_state.root.outputs.subnet_ids
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
}

resource "aws_ecs_task_definition" "store2_task" {
  family                   = "store2-task-west"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "store2"
      image     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.us-west-2.amazonaws.com/pos-store2:latest"
      essential = true
      portMappings = [{ containerPort = 80, hostPort = 80 }]
      environment = [
        { name = "DYNAMODB_TABLE",  value = aws_dynamodb_table.store2_table.name },
        { name = "MASTER_DB_TABLE", value = data.terraform_remote_state.root.outputs.master_table_name }
      ]
    }
  ])
}

resource "aws_ecs_service" "store2_service" {
  name            = "pos-store2-service-west"
  cluster         = aws_ecs_cluster.pos_cluster.id
  task_definition = aws_ecs_task_definition.store2_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.terraform_remote_state.root.outputs.subnet_ids
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "pos-lambda-exec-role-west"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "replicator" {
  filename      = "../../lambda/dynamo_stream_to_master.zip"
  function_name = "dynamo-stream-replicator-west"
  handler       = "dynamo_stream_to_master.lambda_handler"
  runtime       = "python3.9"
  role          = aws_iam_role.lambda_exec_role.arn

  environment {
    variables = {
      MASTER_TABLE_NAME = data.terraform_remote_state.root.outputs.master_table_name
    }
  }
}

resource "aws_lambda_event_source_mapping" "store1_stream" {
  event_source_arn  = aws_dynamodb_table.store1_table.stream_arn
  function_name     = aws_lambda_function.replicator.arn
  starting_position = "LATEST"
}

resource "aws_lambda_event_source_mapping" "store2_stream" {
  event_source_arn  = aws_dynamodb_table.store2_table.stream_arn
  function_name     = aws_lambda_function.replicator.arn
  starting_position = "LATEST"
}

variable "region" {
  type    = string
  default = "us-west-2"
}
