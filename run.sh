#!/bin/bash
set -e

# === VARIABLES ===
REGION="us-east-1"
FLASK_REPO="mcd-pos-flask"
NGINX_REPO="mcd-pos-nginx"
TAG="latest"

# 1. Install Terraform (if not installed)
if ! command -v terraform &> /dev/null; then
  echo "[+] Installing Terraform 1.7.5..."
  curl -O https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip
  unzip -o terraform_1.7.5_linux_amd64.zip
  sudo mv terraform /usr/local/bin/
fi

echo "[+] Terraform version: $(terraform version)"

# 2. Terraform init & apply (infra deploy)
echo "[+] Initializing Terraform..."
terraform init

echo "[+] Applying Terraform infrastructure..."
terraform apply -auto-approve

# 3. Get AWS Account ID dynamically
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "[+] AWS Account ID: $ACCOUNT_ID"

# 4. Login to AWS ECR
echo "[+] Logging into AWS ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# 5. Build Docker images
echo "[+] Building Flask Docker image..."
docker build -t $FLASK_REPO ./flask-app  # Adjust path if needed

echo "[+] Building Nginx Docker image..."
docker build -t $NGINX_REPO ./nginx      # Adjust path or use official image if no custom Dockerfile

# 6. Tag images for ECR
echo "[+] Tagging images..."
docker tag $FLASK_REPO:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$FLASK_REPO:$TAG
docker tag $NGINX_REPO:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$NGINX_REPO:$TAG

# 7. Push images to ECR
echo "[+] Pushing Flask image to ECR..."
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$FLASK_REPO:$TAG

echo "[+] Pushing Nginx image to ECR..."
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$NGINX_REPO:$TAG

# 8. Deploy ECS Cluster & Services (using AWS CLI)

CLUSTER_NAME="mcd-pos-cluster"

echo "[+] Creating ECS cluster: $CLUSTER_NAME..."
aws ecs create-cluster --cluster-name $CLUSTER_NAME || echo "Cluster already exists"

# You need task definitions JSON files prepared for flask and nginx containers referencing ECR images and using private subnets from terraform output

echo "[+] Registering ECS task definitions..."
aws ecs register-task-definition --cli-input-json file://ecs-flask-task.json
aws ecs register-task-definition --cli-input-json file://ecs-nginx-task.json

# 9. Create ECS Services

echo "[+] Creating ECS services..."
aws ecs create-service --cluster $CLUSTER_NAME --service-name flask-service --task-definition mcd-pos-flask-task --desired-count 1 --launch-type FARGATE --network-configuration '{
  "awsvpcConfiguration": {
    "subnets": ["subnet-xxxxxx", "subnet-yyyyyy"],  # Replace with Terraform private subnet outputs
    "securityGroups": ["sg-xxxxxx"],               # Replace with ECS SG from Terraform output
    "assignPublicIp": "DISABLED"
  }
}'

aws ecs create-service --cluster $CLUSTER_NAME --service-name nginx-service --task-definition mcd-pos-nginx-task --desired-count 1 --launch-type FARGATE --network-configuration '{
  "awsvpcConfiguration": {
    "subnets": ["subnet-xxxxxx", "subnet-yyyyyy"],
    "securityGroups": ["sg-xxxxxx"],
    "assignPublicIp": "ENABLED"
  }
}'

echo "[+] ECS services created!"

echo "[+] Deployment complete!"
