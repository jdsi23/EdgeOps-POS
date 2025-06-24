#!/bin/bash
set -e

# Build and push Docker images for west region stores

docker build -t yourdockerhubusername/pos-store1:latest ../../
docker push yourdockerhubusername/pos-store1:latest

docker build -t yourdockerhubusername/pos-store2:latest ../../
docker push yourdockerhubusername/pos-store2:latest

# Deploy Terraform
cd terraform
terraform init
terraform apply -auto-approve
