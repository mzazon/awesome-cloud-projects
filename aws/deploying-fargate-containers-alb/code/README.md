# Infrastructure as Code for Deploying Fargate Containers with Application Load Balancer

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Deploying Fargate Containers with Application Load Balancer".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a serverless container architecture including:

- **Amazon ECR**: Container image registry with vulnerability scanning
- **AWS Fargate**: Serverless compute for containers
- **Amazon ECS**: Container orchestration service
- **Application Load Balancer**: Layer 7 load balancing with health checks
- **Auto Scaling**: Automatic scaling based on CPU and memory metrics
- **CloudWatch**: Comprehensive logging and monitoring
- **IAM Roles**: Least privilege security configuration
- **VPC Security Groups**: Network-level security controls

## Prerequisites

- AWS CLI v2 installed and configured
- Docker installed locally for container image building
- Appropriate AWS permissions for:
  - ECS, Fargate, ECR, and ALB services
  - IAM role creation and management
  - VPC and security group management
  - CloudWatch logs and monitoring
- VPC with public subnets across multiple Availability Zones
- Basic understanding of containerization and load balancing concepts

## Estimated Costs

- **Fargate**: $30-60/month for moderate workloads (pay-per-use pricing)
- **ALB**: ~$16/month base cost plus data processing charges
- **ECR**: $0.10/GB/month for image storage
- **CloudWatch**: Minimal costs for logs and metrics
- **Data Transfer**: Variable based on traffic patterns

> **Note**: Fargate pricing is based on vCPU and memory resources allocated to your containers. You pay only for the resources your containers actually use.

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name fargate-serverless-containers \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=VpcId,ParameterValue=vpc-xxxxxx \
                 ParameterKey=SubnetIds,ParameterValue="subnet-xxxxx,subnet-yyyyy"

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name fargate-serverless-containers \
    --query 'Stacks[0].StackStatus'

# Get ALB DNS name
aws cloudformation describe-stacks \
    --stack-name fargate-serverless-containers \
    --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerDNS`].OutputValue' \
    --output text
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk deploy --outputs-file outputs.json
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk deploy --outputs-file outputs.json
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will:
# 1. Create ECR repository
# 2. Build and push container image
# 3. Create ECS cluster and task definition
# 4. Deploy ALB and target groups
# 5. Configure auto scaling
# 6. Display deployment status
```

## Configuration Options

### CloudFormation Parameters

- `VpcId`: VPC ID for deployment
- `SubnetIds`: Comma-separated list of subnet IDs
- `ContainerCpu`: CPU units for Fargate tasks (256, 512, 1024, etc.)
- `ContainerMemory`: Memory in MB (512, 1024, 2048, etc.)
- `DesiredCount`: Number of tasks to run
- `MaxCapacity`: Maximum number of tasks for auto scaling
- `MinCapacity`: Minimum number of tasks for auto scaling

### CDK Configuration

Modify the following in the CDK code:

```typescript
// CDK TypeScript example
const fargateService = new ecs.FargateService(this, 'FargateService', {
  cluster: cluster,
  taskDefinition: taskDefinition,
  desiredCount: 3,
  minHealthyPercent: 50,
  maxHealthyPercent: 200,
});
```

### Terraform Variables

```hcl
variable "container_cpu" {
  description = "CPU units for Fargate tasks"
  type        = number
  default     = 256
}

variable "container_memory" {
  description = "Memory in MB for Fargate tasks"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Desired number of tasks"
  type        = number
  default     = 3
}
```

## Container Application

The infrastructure deploys a Node.js application with the following features:

- **Health Check Endpoint**: `/health` - Returns service health status
- **Metrics Endpoint**: `/metrics` - Returns container metrics
- **Main Application**: `/` - Returns detailed container information
- **Graceful Shutdown**: Handles SIGTERM for clean container stops
- **Structured Logging**: JSON-formatted logs for CloudWatch
- **Security**: Runs as non-root user with minimal privileges

## Monitoring and Observability

### CloudWatch Integration

- **Container Logs**: Automatically streamed to CloudWatch Logs
- **Metrics**: CPU, memory, and custom application metrics
- **Health Checks**: ALB health checks with configurable thresholds
- **Auto Scaling**: Metrics-based scaling on CPU and memory utilization

### Accessing Logs

```bash
# View log groups
aws logs describe-log-groups --log-group-name-prefix "/ecs/"

# Stream logs in real-time
aws logs tail "/ecs/fargate-task-family" --follow
```

### Monitoring Commands

```bash
# Check service status
aws ecs describe-services --cluster fargate-cluster --services fargate-service

# View scaling activities
aws application-autoscaling describe-scaling-activities \
    --service-namespace ecs \
    --resource-id service/fargate-cluster/fargate-service

# Check target group health
aws elbv2 describe-target-health --target-group-arn <target-group-arn>
```

## Security Features

### Network Security

- **Security Groups**: Restrict traffic to necessary ports only
- **VPC Integration**: Isolated network environment
- **ALB Security**: Public endpoint with controlled access
- **Container Isolation**: Fargate provides task-level isolation

### IAM Security

- **Task Execution Role**: Minimal permissions for ECS operations
- **Task Role**: Application-specific permissions
- **Least Privilege**: Each role has only necessary permissions
- **No Hardcoded Secrets**: Uses AWS Secrets Manager integration

### Container Security

- **Non-root User**: Container runs as unprivileged user
- **Image Scanning**: ECR vulnerability scanning enabled
- **Read-only Root**: Container filesystem restrictions
- **Resource Limits**: CPU and memory limits enforced

## Validation and Testing

### Health Check Validation

```bash
# Test application endpoints
ALB_DNS=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[0].DNSName' --output text)

# Test main endpoint
curl http://${ALB_DNS}/

# Test health check
curl http://${ALB_DNS}/health

# Test metrics
curl http://${ALB_DNS}/metrics
```

### Load Testing

```bash
# Generate load to test auto scaling
for i in {1..100}; do
    curl -s http://${ALB_DNS}/ &
done

# Monitor scaling events
aws ecs describe-services --cluster fargate-cluster --services fargate-service \
    --query 'services[0].events[0:5]'
```

## Troubleshooting

### Common Issues

1. **Tasks Not Starting**
   - Check task definition configuration
   - Verify ECR image exists and is accessible
   - Review CloudWatch logs for container errors

2. **Health Check Failures**
   - Verify application is listening on correct port
   - Check security group allows traffic from ALB
   - Review health check configuration

3. **Scaling Issues**
   - Check auto scaling policies and thresholds
   - Verify CloudWatch metrics are being published
   - Review scaling cooldown periods

### Debugging Commands

```bash
# Get task details
aws ecs describe-tasks --cluster fargate-cluster --tasks <task-arn>

# Check container logs
aws logs get-log-events --log-group-name "/ecs/fargate-task-family" \
    --log-stream-name "<log-stream-name>"

# Verify target group health
aws elbv2 describe-target-health --target-group-arn <target-group-arn>
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name fargate-serverless-containers

# Monitor deletion progress
aws cloudformation describe-stacks --stack-name fargate-serverless-containers \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
# Destroy the stack
cdk destroy

# Confirm destruction when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# 1. Scale service to zero
# 2. Delete ECS service and cluster
# 3. Delete ALB and target groups
# 4. Remove auto scaling configuration
# 5. Clean up IAM roles and policies
# 6. Delete ECR repository
# 7. Remove security groups
```

## Best Practices

### Cost Optimization

- Use Fargate Spot for development environments (up to 70% savings)
- Implement right-sizing for CPU and memory allocations
- Use lifecycle policies for ECR images
- Monitor and optimize auto scaling parameters

### Security Best Practices

- Regularly update container images
- Use ECR image scanning
- Implement least privilege IAM policies
- Enable VPC Flow Logs for network monitoring
- Use AWS Secrets Manager for sensitive data

### Performance Optimization

- Optimize container startup time
- Use appropriate health check intervals
- Configure auto scaling based on application metrics
- Implement caching strategies
- Use ALB sticky sessions if needed

## Support and Documentation

- [AWS Fargate Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html)
- [Application Load Balancer Guide](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)
- [Amazon ECR User Guide](https://docs.aws.amazon.com/AmazonECR/latest/userguide/)
- [ECS Auto Scaling](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-auto-scaling.html)

For issues with this infrastructure code, refer to the original recipe documentation or the AWS documentation for specific services.

## License

This infrastructure code is provided as-is under the MIT License. Use at your own risk and ensure compliance with your organization's policies.