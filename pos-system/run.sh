#!/bin/bash
set -e

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
