variable "region" {
  type = string
}

variable "store1_table_name" {
  type = string
}

variable "store2_table_name" {
  type = string
}

provider "aws" {
  region = var.region
}

resource "aws_dynamodb_table" "store1_table" {
  name         = var.store1_table_name
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
  name         = var.store2_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "order_id"

  attribute {
    name = "order_id"
    type = "S"
  }

  stream_enabled   = true
  stream_view_type = "NEW_IMAGE"
}

output "store1_stream_arn" {
  value = aws_dynamodb_table.store1_table.stream_arn
}

output "store2_stream_arn" {
  value = aws_dynamodb_table.store2_table.stream_arn
}
