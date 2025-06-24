variable "region" {
  type = string
}

variable "master_table_name" {
  type = string
}

variable "store1_stream_arn" {
  type = string
}

variable "store2_stream_arn" {
  type = string
}

provider "aws" {
  region = var.region
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "pos-lambda-exec-role-${var.region}"

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
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "replicator" {
  filename      = "lambda/dynamo_stream_to_master.zip"
  function_name = "dynamo-stream-replicator-${var.region}"
  handler       = "dynamo_stream_to_master.lambda_handler"
  runtime       = "python3.9"
  role          = aws_iam_role.lambda_exec_role.arn

  environment {
    variables = {
      MASTER_TABLE_NAME = var.master_table_name
    }
  }
}

resource "aws_lambda_event_source_mapping" "store1_stream" {
  event_source_arn  = var.store1_stream_arn
  function_name     = aws_lambda_function.replicator.arn
  starting_position = "LATEST"
}

resource "aws_lambda_event_source_mapping" "store2_stream" {
  event_source_arn  = var.store2_stream_arn
  function_name     = aws_lambda_function.replicator.arn
  starting_position = "LATEST"
}
