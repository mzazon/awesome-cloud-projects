#!/bin/bash

# Configure ECS cluster name
echo "ECS_CLUSTER=${cluster_name}" >> /etc/ecs/ecs.config

# Enable Spot instance draining for graceful task migration
echo "ECS_ENABLE_SPOT_INSTANCE_DRAINING=true" >> /etc/ecs/ecs.config

# Configure container instance attributes for better task placement
echo "ECS_INSTANCE_ATTRIBUTES={\"instance.type\":\"spot\"}" >> /etc/ecs/ecs.config

# Set up logging for ECS agent
echo "ECS_LOGLEVEL=info" >> /etc/ecs/ecs.config

# Update the system
yum update -y

# Install CloudWatch agent for enhanced monitoring
yum install -y amazon-cloudwatch-agent

# Start ECS agent
start ecs

# Wait for ECS agent to be ready
until curl -s http://localhost:51678/v1/metadata
do
  echo "Waiting for ECS agent to be ready..."
  sleep 5
done

echo "ECS instance configuration complete"