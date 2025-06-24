#!/bin/bash
set -e

echo "[+] Downloading Terraform 1.7.5..."
curl -O https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip

echo "[+] Unzipping Terraform..."
unzip -o terraform_1.7.5_linux_amd64.zip

echo "[+] Moving Terraform binary to /usr/local/bin..."
sudo mv terraform /usr/local/bin/

echo "[+] Making setup.sh and deploy.sh executable..."
chmod +x run.sh

declare -A regions_ports=(
  ["central"]=5000
  ["east"]=5001
  ["south"]=5002
  ["west"]=5003
)

echo "Starting multi-region POS deployment..."

for region in "${!regions_ports[@]}"; do
  port=${regions_ports[$region]}
  container_name="pos-${region}"

  echo "Processing region: $region (port $port)..."

  # Build Docker image for the region
  echo "Building Docker image for $region..."
  docker build -t edgeops-pos-$region ./$region

  # Stop running container if exists
  if [ "$(docker ps -q -f name=$container_name)" ]; then
    echo "Stopping existing container $container_name..."
    docker stop $container_name
  fi

  # Remove container if exists
  if [ "$(docker ps -a -q -f name=$container_name)" ]; then
    echo "Removing existing container $container_name..."
    docker rm $container_name
  fi

  # Run container on assigned port
  echo "Starting container $container_name on port $port..."
  docker run -d -p ${port}:5000 --name $container_name edgeops-pos-$region

  echo "Region $region deployed successfully."
done

echo "All regions deployed. POS apps running on ports: ${regions_ports[@]}"
