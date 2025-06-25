terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_availability_zones" "available" {}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

# --- VPC & Networking ---

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "mcd-pos-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "mcd-pos-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = 3
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "mcd-pos-public-subnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count             = 3
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + 3)
  availability_zone = local.azs[count.index]

  tags = {
    Name = "mcd-pos-private-subnet-${count.index + 1}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "mcd-pos-public-rt"
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  count          = 3
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  count = 1
  vpc   = true

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "mcd-pos-private-rt"
  }
}

resource "aws_route" "private_route" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

resource "aws_route_table_association" "private_assoc" {
  count          = 3
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# --- Security Groups ---

resource "aws_security_group" "rds_sg" {
  name        = "mcd-pos-rds-sg"
  description = "Allow Aurora DB access from VPC"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "mcd-pos-rds-sg"
  }
}

# ECS SG (for example, adjust as needed)
resource "aws_security_group" "ecs_sg" {
  name        = "mcd-pos-ecs-sg"
  description = "Allow outbound access to RDS"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.rds_sg.id]
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "mcd-pos-ecs-sg"
  }
}

# --- DB Subnet Group for RDS ---

resource "aws_db_subnet_group" "private" {
  name       = "mcd-pos-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "mcd-pos-db-subnet-group"
  }
}

# --- Aurora Global Cluster ---

resource "aws_rds_global_cluster" "global" {
  global_cluster_identifier = "mcd-pos-global-db"
}

# --- Primary Aurora Cluster (writes) ---

resource "aws_rds_cluster" "primary" {
  cluster_identifier         = "mcd-pos-primary-cluster"
  engine                     = "aurora-postgresql"
  engine_version             = "15.2"
  global_cluster_identifier  = aws_rds_global_cluster.global.id
  master_username            = "posadmin"
  master_password            = "YourStrongPasswordHere!"
  database_name              = "posdb"
  db_subnet_group_name       = aws_db_subnet_group.private.name
  vpc_security_group_ids     = [aws_security_group.rds_sg.id]
  availability_zones         = [local.azs[0]]
  skip_final_snapshot        = true
  deletion_protection        = false

  tags = {
    Name = "mcd-pos-primary-cluster"
  }
}

resource "aws_rds_cluster_instance" "primary_instance" {
  count              = 1
  identifier         = "mcd-pos-primary-instance-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.primary.id
  instance_class     = "db.t4g.medium"
  engine             = aws_rds_cluster.primary.engine
  engine_version     = aws_rds_cluster.primary.engine_version
  publicly_accessible = false
  availability_zone  = local.azs[0]

  tags = {
    Name = "mcd-pos-primary-instance-${count.index + 1}"
  }
}

# --- Secondary clusters (read-only replicas) ---

resource "aws_rds_cluster" "replica_az2" {
  cluster_identifier        = "mcd-pos-replica-az2"
  engine                    = "aurora-postgresql"
  engine_version            = "15.2"
  global_cluster_identifier = aws_rds_global_cluster.global.id
  db_subnet_group_name      = aws_db_subnet_group.private.name
  vpc_security_group_ids    = [aws_security_group.rds_sg.id]
  availability_zones        = [local.azs[1]]
  skip_final_snapshot       = true
  deletion_protection       = false

  tags = {
    Name = "mcd-pos-replica-az2"
  }
}

resource "aws_rds_cluster_instance" "replica_instance_az2" {
  count              = 1
  identifier         = "mcd-pos-replica-instance-az2-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.replica_az2.id
  instance_class     = "db.t4g.medium"
  engine             = aws_rds_cluster.replica_az2.engine
  engine_version     = aws_rds_cluster.replica_az2.engine_version
  publicly_accessible = false
  availability_zone  = local.azs[1]

  tags = {
    Name = "mcd-pos-replica-instance-az2-${count.index + 1}"
  }
}

resource "aws_rds_cluster" "replica_az3" {
  cluster_identifier        = "mcd-pos-replica-az3"
  engine                    = "aurora-postgresql"
  engine_version            = "15.2"
  global_cluster_identifier = aws_rds_global_cluster.global.id
  db_subnet_group_name      = aws_db_subnet_group.private.name
  vpc_security_group_ids    = [aws_security_group.rds_sg.id]
  availability_zones        = [local.azs[2]]
  skip_final_snapshot       = true
  deletion_protection       = false

  tags = {
    Name = "mcd-pos-replica-az3"
  }
}

resource "aws_rds_cluster_instance" "replica_instance_az3" {
  count              = 1
  identifier         = "mcd-pos-replica-instance-az3-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.replica_az3.id
  instance_class     = "db.t4g.medium"
  engine             = aws_rds_cluster.replica_az3.engine
  engine_version     = aws_rds_cluster.replica_az3.engine_version
  publicly_accessible = false
  availability_zone  = local.azs[2]

  tags = {
    Name = "mcd-pos-replica-instance-az3-${count.index + 1}"
  }
}

# --- Outputs ---

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public Subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private Subnet IDs"
  value       = aws_subnet.private[*].id
}

output "rds_primary_endpoint" {
  description = "Aurora Primary Cluster Endpoint"
  value       = aws_rds_cluster.primary.endpoint
}

output "rds_reader_endpoint" {
  description = "Aurora Primary Reader Endpoint"
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "rds_replica_az2_endpoint" {
  description = "Aurora Replica AZ2 Endpoint"
  value       = aws_rds_cluster.replica_az2.endpoint
}

output "rds_replica_az3_endpoint" {
  description = "Aurora Replica AZ3 Endpoint"
  value       = aws_rds_cluster.replica_az3.endpoint
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "rds_sg_id" {
  description = "RDS security group ID"
  value       = aws_security_group.rds_sg.id
}

output "ecs_sg_id" {
  description = "ECS security group ID"
  value       = aws_security_group.ecs_sg.id
}