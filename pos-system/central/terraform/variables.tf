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
  default     = "us-east-1"
}

variable "store1_image" {
  description = "Docker image URI for Store 1"
  type        = string
}

variable "store2_image" {
  description = "Docker image URI for Store 2"
  type        = string
}
