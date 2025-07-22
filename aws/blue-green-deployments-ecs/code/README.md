# Infrastructure as Code for Blue-Green Deployments for ECS Applications

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Blue-Green Deployments for ECS Applications".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Docker installed for container image management
- Appropriate AWS permissions for:
  - ECS (Elastic Container Service)
  - Application Load Balancer (ALB)
  - CodeDeploy
  - CloudWatch
  - ECR (Elastic Container Registry)
  - IAM roles and policies
  - VPC networking resources
  - S3 bucket creation
- Basic understanding of containerization and blue-green deployments

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name bluegreen-ecs-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=Environment,ParameterValue=dev \
        ParameterKey=AppName,ParameterValue=bluegreen-demo

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name bluegreen-ecs-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript
```bash
# Install dependencies
cd cdk-typescript/
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# View outputs
cdk ls
```

### Using CDK Python
```bash
# Set up virtual environment
cd cdk-python/
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# View outputs
cdk ls
```

### Using Terraform
```bash
# Initialize Terraform
cd terraform/
terraform init

# Review deployment plan
terraform plan

# Apply infrastructure
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
# 1. Create VPC and networking resources
# 2. Set up ECR repository
# 3. Build and push sample application
# 4. Create ECS cluster and task definitions
# 5. Configure Application Load Balancer
# 6. Set up CodeDeploy for blue-green deployments
# 7. Deploy initial application version
```

## Architecture Overview

This infrastructure creates:

- **VPC with public subnets** across multiple availability zones
- **Application Load Balancer** with blue and green target groups
- **ECS Cluster** with Fargate capacity providers
- **ECR Repository** for container image storage
- **CodeDeploy Application** configured for ECS blue-green deployments
- **IAM Roles** for ECS task execution and CodeDeploy service
- **CloudWatch Log Groups** for container logging
- **Security Groups** with appropriate ingress rules

## Deployment Process

1. **Initial Setup**: Creates foundational networking and security resources
2. **Container Registry**: Sets up ECR repository for application images
3. **ECS Infrastructure**: Provisions cluster, task definitions, and services
4. **Load Balancer**: Configures ALB with blue/green target groups
5. **CodeDeploy**: Sets up blue-green deployment automation
6. **Application Deployment**: Deploys initial application version

## Configuration Options

### Environment Variables
- `AWS_REGION`: Target AWS region for deployment
- `APP_NAME`: Application name prefix for resources
- `ENVIRONMENT`: Environment designation (dev, staging, prod)
- `CONTAINER_IMAGE`: Initial container image URI
- `DESIRED_COUNT`: Number of ECS tasks to run

### Customizable Parameters
- **Instance Resources**: CPU and memory allocation for containers
- **Network Configuration**: VPC CIDR blocks and subnet configurations
- **Deployment Strategy**: CodeDeploy configuration for traffic shifting
- **Health Check Settings**: ALB target group health check parameters
- **Logging Configuration**: CloudWatch log group settings

## Testing the Deployment

After deployment, verify the infrastructure:

```bash
# Get ALB DNS name
aws elbv2 describe-load-balancers \
    --names bluegreen-alb-* \
    --query 'LoadBalancers[0].DNSName'

# Test application availability
curl -s http://[ALB_DNS_NAME] | grep "Version"

# Check ECS service status
aws ecs describe-services \
    --cluster bluegreen-cluster-* \
    --services bluegreen-service-* \
    --query 'services[0].status'

# Verify CodeDeploy application
aws deploy list-applications \
    --query 'applications[?contains(@, `bluegreen`)]'
```

## Performing Blue-Green Deployments

Once infrastructure is deployed, perform blue-green deployments:

```bash
# Update application version
docker build -t my-app:v2.0 .
docker tag my-app:v2.0 [ECR_URI]:v2.0
docker push [ECR_URI]:v2.0

# Create new task definition with updated image
aws ecs register-task-definition \
    --family bluegreen-task-* \
    --container-definitions '[{
        "name": "app-container",
        "image": "[ECR_URI]:v2.0",
        "portMappings": [{"containerPort": 80}],
        "essential": true
    }]'

# Trigger blue-green deployment via CodeDeploy
aws deploy create-deployment \
    --application-name bluegreen-app-* \
    --deployment-group-name bluegreen-dg-* \
    --revision '[deployment-revision-config]'
```

## Monitoring and Troubleshooting

### CloudWatch Monitoring
- **ECS Service Metrics**: Monitor CPU, memory, and task count
- **ALB Metrics**: Track request count, latency, and error rates
- **CodeDeploy Metrics**: Monitor deployment success and failure rates

### Common Issues
- **Health Check Failures**: Verify target group health check configuration
- **Deployment Timeouts**: Adjust CodeDeploy timeout settings
- **Image Pull Errors**: Ensure ECR repository permissions are correct
- **Network Connectivity**: Verify security group and subnet configurations

### Debugging Commands
```bash
# Check ECS task logs
aws logs tail /ecs/bluegreen-task-* --follow

# View deployment events
aws deploy get-deployment --deployment-id [DEPLOYMENT_ID]

# Check target group health
aws elbv2 describe-target-health \
    --target-group-arn [TARGET_GROUP_ARN]
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name bluegreen-ecs-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name bluegreen-ecs-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
cdk destroy
```

### Using CDK Python
```bash
cd cdk-python/
cdk destroy
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# 1. Delete CodeDeploy resources
# 2. Remove ECS services and cluster
# 3. Delete load balancer and target groups
# 4. Clean up ECR repository
# 5. Remove VPC and networking resources
# 6. Delete IAM roles and policies
```

## Security Considerations

- **IAM Roles**: Follow least privilege principle for ECS and CodeDeploy roles
- **Network Security**: Security groups restrict access to necessary ports only
- **Container Security**: ECR repository includes image scanning capabilities
- **Secrets Management**: Use AWS Secrets Manager for sensitive configuration
- **Encryption**: Enable encryption at rest and in transit where applicable

## Cost Optimization

- **Fargate Pricing**: Monitor task CPU and memory usage for right-sizing
- **ALB Costs**: Consider using Network Load Balancer for simpler use cases
- **ECR Storage**: Implement lifecycle policies to manage image retention
- **Data Transfer**: Optimize cross-AZ traffic patterns
- **Development Environments**: Use scheduled scaling to reduce costs

## Performance Tuning

- **Health Check Optimization**: Adjust health check intervals and thresholds
- **Container Resources**: Right-size CPU and memory allocations
- **Auto Scaling**: Configure ECS service auto scaling based on metrics
- **Load Balancer Settings**: Optimize connection draining and idle timeout
- **Deployment Speed**: Tune CodeDeploy traffic shifting parameters

## Best Practices

1. **Version Control**: Tag container images with semantic versions
2. **Environment Consistency**: Use identical configurations across environments
3. **Monitoring**: Implement comprehensive monitoring and alerting
4. **Testing**: Validate deployments in non-production environments first
5. **Rollback Strategy**: Maintain automated rollback capabilities
6. **Documentation**: Keep deployment procedures and configurations documented

## Troubleshooting Guide

### Deployment Failures
- **Check ECS Service Events**: Review service event logs for errors
- **Verify Task Definition**: Ensure container specifications are correct
- **Network Connectivity**: Confirm security groups and subnets are properly configured
- **Resource Limits**: Check AWS service limits and quotas

### Blue-Green Deployment Issues
- **CodeDeploy Permissions**: Verify service role has required permissions
- **Health Check Configuration**: Ensure target group health checks are appropriate
- **Deployment Hooks**: Review lifecycle hook configurations if used
- **Traffic Shifting**: Monitor traffic shifting progress and metrics

## Additional Resources

- [AWS ECS Blue/Green Deployment Guide](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-type-bluegreen.html)
- [CodeDeploy for ECS Documentation](https://docs.aws.amazon.com/codedeploy/latest/userguide/applications-create-ecs.html)
- [Application Load Balancer Documentation](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)
- [ECS Task Definition Reference](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definitions.html)

## Support

For issues with this infrastructure code, refer to:
1. The original recipe documentation
2. AWS service documentation
3. Provider-specific troubleshooting guides
4. AWS Support (for AWS-related issues)

## Contributing

To improve this infrastructure code:
1. Test changes in a development environment
2. Validate against AWS best practices
3. Update documentation for any configuration changes
4. Ensure compatibility across all IaC implementations