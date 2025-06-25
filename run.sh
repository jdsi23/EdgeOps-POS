#!/bin/bash
set -e

# Variables
REGION="us-east-1"
FLASK_REPO="mcd-pos-flask"
NGINX_REPO="mcd-pos-nginx"
TAG="latest"
CLUSTER_NAME="mcd-pos-cluster"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  echo "ERROR: 'jq' is required but not installed. Please install jq and rerun."
  exit 1
fi

# Install Terraform if missing
if ! command -v terraform &> /dev/null; then
  echo "[+] Installing Terraform 1.7.5..."
  curl -O https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip
  unzip -o terraform_1.7.5_linux_amd64.zip
  sudo mv terraform /usr/local/bin/
fi

echo "[+] Terraform version: $(terraform version)"

# Terraform init & apply
echo "[+] Initializing Terraform..."
terraform init

echo "[+] Applying Terraform configuration..."
terraform apply -auto-approve

echo "[+] Getting Terraform outputs..."
TF_OUTPUT=$(terraform output -json)

PRIVATE_SUBNET_IDS=$(echo "$TF_OUTPUT" | jq -r '.private_subnet_ids.value | join(",")')
RDS_SG_ID=$(echo "$TF_OUTPUT" | jq -r '.rds_sg_id.value')
ECS_SG_ID=$(echo "$TF_OUTPUT" | jq -r '.ecs_sg_id.value')

echo "Private subnets: $PRIVATE_SUBNET_IDS"
echo "RDS SG ID: $RDS_SG_ID"
echo "ECS SG ID: $ECS_SG_ID"

# Convert subnet IDs to JSON array for AWS CLI
IFS=',' read -ra SUBNET_ARR <<< "$PRIVATE_SUBNET_IDS"
SUBNETS_JSON=$(printf '"%s",' "${SUBNET_ARR[@]}")
SUBNETS_JSON="[${SUBNETS_JSON%,}]"

SECURITY_GROUPS_JSON="[\"$ECS_SG_ID\"]"

# Get AWS Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "[+] AWS Account ID: $ACCOUNT_ID"

# Login to AWS ECR
echo "[+] Logging in to AWS ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# Build Docker images
echo "[+] Building Flask Docker image..."
docker build -t $FLASK_REPO ./flask-app

echo "[+] Building Nginx Docker image..."
docker build -t $NGINX_REPO ./nginx

# Tag Docker images for ECR
echo "[+] Tagging Docker images..."
docker tag $FLASK_REPO:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$FLASK_REPO:$TAG
docker tag $NGINX_REPO:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$NGINX_REPO:$TAG

# Push Docker images to ECR
echo "[+] Pushing Flask image to ECR..."
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$FLASK_REPO:$TAG

echo "[+] Pushing Nginx image to ECR..."
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$NGINX_REPO:$TAG

# Create ECS Cluster if not exists
echo "[+] Creating ECS cluster $CLUSTER_NAME (if not exists)..."
aws ecs create-cluster --cluster-name $CLUSTER_NAME || echo "Cluster $CLUSTER_NAME already exists."

# Register task definitions (assuming JSON files exist and use placeholders for image URIs)
echo "[+] Registering ECS task definitions..."
aws ecs register-task-definition --cli-input-json file://ecs-flask-task.json
aws ecs register-task-definition --cli-input-json file://ecs-nginx-task.json

# Create or update ECS services
echo "[+] Creating/updating ECS services..."

aws ecs describe-services --cluster $CLUSTER_NAME --services flask-service >/dev/null 2>&1 && \
  echo "Updating existing Flask service..." && \
  aws ecs update-service --cluster $CLUSTER_NAME --service flask-service --desired-count 1 || \
  echo "Creating Flask service..." && \
  aws ecs create-service --cluster $CLUSTER_NAME --service-name flask-service --task-definition mcd-pos-flask-task --desired-count 1 --launch-type FARGATE --network-configuration "{\"awsvpcConfiguration\":{\"subnets\":$SUBNETS_JSON,\"securityGroups\":$SECURITY_GROUPS_JSON,\"assignPublicIp\":\"DISABLED\"}}"

aws ecs describe-services --cluster $CLUSTER_NAME --services nginx-service >/dev/null 2>&1 && \
  echo "Updating existing Nginx service..." && \
  aws ecs update-service --cluster $CLUSTER_NAME --service nginx-service --desired-count 1 || \
  echo "Creating Nginx service..." && \
  aws ecs create-service --cluster $CLUSTER_NAME --service-name nginx-service --task-definition mcd-pos-nginx-task --desired-count 1 --launch-type FARGATE --network-configuration "{\"awsvpcConfiguration\":{\"subnets\":$SUBNETS_JSON,\"securityGroups\":$SECURITY_GROUPS_JSON,\"assignPublicIp\":\"ENABLED\"}}"

echo "[+] Deployment complete!"
