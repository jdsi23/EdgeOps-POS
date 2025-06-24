provider "aws" {}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_vpc" "pos_vpc" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "pos-vpc" }
}

resource "aws_subnet" "pos_subnet_1" {
  vpc_id            = aws_vpc.pos_vpc.id
  cidr_block        = "10.10.1.0/24"
  availability_zone = "${data.aws_region.current.name}a"
  tags              = { Name = "pos-subnet-1" }
}

resource "aws_subnet" "pos_subnet_2" {
  vpc_id            = aws_vpc.pos_vpc.id
  cidr_block        = "10.10.2.0/24"
  availability_zone = "${data.aws_region.current.name}b"
  tags              = { Name = "pos-subnet-2" }
}

resource "aws_internet_gateway" "pos_igw" {
  vpc_id = aws_vpc.pos_vpc.id
  tags   = { Name = "pos-igw" }
}

resource "aws_route_table" "pos_route_table" {
  vpc_id = aws_vpc.pos_vpc.id
  tags   = { Name = "pos-route-table" }
}

resource "aws_route_table_association" "pos_subnet_1_assoc" {
  subnet_id      = aws_subnet.pos_subnet_1.id
  route_table_id = aws_route_table.pos_route_table.id
}

resource "aws_route_table_association" "pos_subnet_2_assoc" {
  subnet_id      = aws_subnet.pos_subnet_2.id
  route_table_id = aws_route_table.pos_route_table.id
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_route_table.pos_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.pos_igw.id
}

resource "aws_ecr_repository" "store1_repo" {
  name = "pos-store1"
}

resource "aws_ecr_repository" "store2_repo" {
  name = "pos-store2"
}

resource "aws_dynamodb_table" "master_table" {
  name         = "pos-master-db"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "order_id"

  attribute {
    name = "order_id"
    type = "S"
  }

  tags = {
    Name = "pos-master-db"
  }
}

output "vpc_id" {
  value = aws_vpc.pos_vpc.id
}

output "subnet_ids" {
  value = [
    aws_subnet.pos_subnet_1.id,
    aws_subnet.pos_subnet_2.id,
  ]
}

output "store1_ecr_uri" {
  value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/pos-store1"
}

output "store2_ecr_uri" {
  value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/pos-store2"
}

output "master_table_name" {
  value = aws_dynamodb_table.master_table.name
}
