# Infrastructure as Code for Application Modernization with App2Container

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Application Modernization with App2Container".

## Overview

This recipe demonstrates how to modernize legacy Java and .NET applications using AWS App2Container (A2C), transforming traditional applications into containerized workloads that can run on Amazon ECS, Amazon EKS, or AWS App Runner with complete CI/CD pipelines.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture

The infrastructure provisions:
- Amazon ECS cluster with Fargate capacity providers
- Amazon ECR repository for container images
- Amazon S3 bucket for App2Container artifacts
- AWS CodeCommit repository for source code
- AWS CodePipeline with CodeBuild for CI/CD
- Application Load Balancer with security groups
- IAM roles and policies for service permissions
- CloudWatch monitoring and auto-scaling configuration

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - ECS, ECR, and Fargate
  - S3, CodeCommit, CodeBuild, CodePipeline
  - IAM role creation and management
  - CloudWatch and Application Auto Scaling
  - VPC and security group management
- For CDK implementations: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.5+ installed
- Understanding of containerization and AWS container services
- A Linux or Windows server with running Java/.NET applications for App2Container analysis
- Estimated cost: $15-30/hour for container services and supporting infrastructure

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name app2container-modernization \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=EnvironmentName,ParameterValue=dev

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name app2container-modernization \
    --query 'Stacks[0].StackStatus'

# Wait for completion
aws cloudformation wait stack-create-complete \
    --stack-name app2container-modernization
```

### Using CDK TypeScript
```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time in account/region)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk ls
```

### Using CDK Python
```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time in account/region)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never
```

### Using Terraform
```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply configuration
terraform apply -auto-approve

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
# - Validate prerequisites
# - Create all required resources
# - Configure monitoring and auto-scaling
# - Display connection information
```

## Post-Deployment Steps

After infrastructure deployment, follow these steps to complete the App2Container modernization:

1. **Install App2Container** on your worker machine:
   ```bash
   # Download and install App2Container
   curl -o AWSApp2Container-installer-linux.tar.gz \
       https://app2container-release-us-east-1.s3.us-east-1.amazonaws.com/latest/linux/AWSApp2Container-installer-linux.tar.gz
   sudo tar xvf AWSApp2Container-installer-linux.tar.gz
   sudo ./install.sh
   ```

2. **Initialize App2Container** with the deployed S3 bucket:
   ```bash
   # Get S3 bucket name from stack outputs
   export S3_BUCKET=$(aws cloudformation describe-stacks \
       --stack-name app2container-modernization \
       --query 'Stacks[0].Outputs[?OutputKey==`ArtifactsBucket`].OutputValue' \
       --output text)
   
   # Initialize App2Container
   sudo app2container init
   ```

3. **Analyze and containerize applications**:
   ```bash
   # Discover applications
   sudo app2container inventory
   
   # Analyze discovered application
   sudo app2container analyze --application-id <APP_ID>
   
   # Extract and containerize
   sudo app2container extract --application-id <APP_ID>
   sudo app2container containerize --application-id <APP_ID>
   ```

4. **Deploy to ECS** using generated artifacts:
   ```bash
   # Generate and deploy to ECS
   sudo app2container generate app-deployment \
       --application-id <APP_ID> \
       --deploy-target ecs \
       --deploy
   ```

## Configuration Options

### Environment Variables
Set these environment variables before deployment to customize the infrastructure:

```bash
export AWS_REGION="us-east-1"                    # Target AWS region
export ENVIRONMENT_NAME="dev"                    # Environment identifier
export CLUSTER_NAME="app2container-cluster"      # ECS cluster name
export ENABLE_AUTO_SCALING="true"               # Enable auto-scaling
export MIN_CAPACITY="1"                         # Minimum task count
export MAX_CAPACITY="10"                        # Maximum task count
export CPU_THRESHOLD="70"                       # CPU scaling threshold
export ENABLE_LOGGING="true"                    # Enable CloudWatch logging
```

### Customizable Parameters

Each implementation supports these common parameters:

- **EnvironmentName**: Environment identifier (dev, staging, prod)
- **VpcId**: Existing VPC ID (optional, creates new VPC if not specified)
- **SubnetIds**: Existing subnet IDs (optional)
- **EnableAutoScaling**: Enable application auto-scaling (true/false)
- **MinCapacity**: Minimum number of running tasks
- **MaxCapacity**: Maximum number of running tasks
- **CpuThreshold**: CPU utilization threshold for scaling
- **EnableLogging**: Enable comprehensive CloudWatch logging

## Monitoring and Observability

The infrastructure includes comprehensive monitoring:

- **CloudWatch Metrics**: ECS service and task metrics
- **Application Auto Scaling**: CPU and memory-based scaling
- **CloudWatch Logs**: Centralized application and container logs
- **CloudWatch Dashboard**: Visual monitoring interface
- **AWS X-Ray**: Distributed tracing (when enabled)

### Accessing Logs
```bash
# View ECS service logs
aws logs describe-log-groups --log-group-name-prefix "/ecs/"

# Stream application logs
aws logs tail /ecs/app2container --follow
```

### Monitoring Dashboard
Access the CloudWatch dashboard through the AWS Console or get the dashboard URL from stack outputs.

## Security Considerations

The infrastructure implements AWS security best practices:

- **IAM Least Privilege**: Minimal required permissions for all services
- **VPC Security Groups**: Restricted network access with specific port rules
- **Encryption**: Data encryption at rest and in transit
- **Secrets Management**: Integration with AWS Secrets Manager
- **Container Security**: ECR image scanning and vulnerability assessment
- **Network Security**: Private subnets for container workloads

### Security Groups
- **ALB Security Group**: Allows inbound HTTP/HTTPS traffic
- **ECS Security Group**: Allows traffic only from ALB
- **VPC Endpoints**: Secure communication with AWS services

## Cost Optimization

### Included Cost Optimizations
- **AWS Fargate Spot**: Reduced costs for non-critical workloads
- **Application Auto Scaling**: Scale based on actual demand
- **S3 Lifecycle Policies**: Automatic archiving of old artifacts
- **CloudWatch Log Retention**: Configurable log retention periods

### Cost Monitoring
```bash
# Enable AWS Cost Explorer tags for tracking
aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE
```

## Troubleshooting

### Common Issues

1. **Stack Creation Fails**:
   ```bash
   # Check CloudFormation events
   aws cloudformation describe-stack-events \
       --stack-name app2container-modernization
   ```

2. **ECS Tasks Not Starting**:
   ```bash
   # Check ECS service events
   aws ecs describe-services \
       --cluster app2container-cluster \
       --services app2container-service
   ```

3. **Image Pull Errors**:
   ```bash
   # Verify ECR repository permissions
   aws ecr describe-repositories
   aws ecr get-login-password --region $AWS_REGION
   ```

### Debug Commands
```bash
# Check resource status
aws ecs describe-clusters --clusters app2container-cluster
aws ecr describe-repositories
aws s3 ls | grep app2container
aws codepipeline list-pipelines
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name app2container-modernization

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name app2container-modernization

# Verify deletion
aws cloudformation describe-stacks \
    --stack-name app2container-modernization 2>/dev/null || echo "Stack deleted successfully"
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
cdk destroy --force
```

### Using CDK Python
```bash
cd cdk-python/
source .venv/bin/activate
cdk destroy --force
```

### Using Terraform
```bash
cd terraform/
terraform destroy -auto-approve
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# - Prompt for confirmation
# - Remove all created resources
# - Clean up in proper dependency order
# - Verify successful deletion
```

### Manual Cleanup (if needed)
```bash
# Delete ECR images before repository deletion
aws ecr batch-delete-image \
    --repository-name app2container-repo \
    --image-ids imageTag=latest

# Empty S3 bucket before deletion
aws s3 rm s3://app2container-artifacts-bucket --recursive
```

## Advanced Usage

### Multi-Environment Deployment
```bash
# Deploy to multiple environments
for env in dev staging prod; do
    aws cloudformation create-stack \
        --stack-name app2container-${env} \
        --template-body file://cloudformation.yaml \
        --capabilities CAPABILITY_IAM \
        --parameters ParameterKey=EnvironmentName,ParameterValue=${env}
done
```

### Blue/Green Deployment
The infrastructure supports blue/green deployments through CodeDeploy integration:

```bash
# Configure blue/green deployment
aws deploy create-application \
    --application-name app2container-bluegreen \
    --compute-platform ECS
```

### Cross-Region Replication
For disaster recovery, deploy to multiple regions:

```bash
# Deploy to primary region
aws cloudformation create-stack \
    --region us-east-1 \
    --stack-name app2container-primary \
    --template-body file://cloudformation.yaml

# Deploy to secondary region
aws cloudformation create-stack \
    --region us-west-2 \
    --stack-name app2container-secondary \
    --template-body file://cloudformation.yaml
```

## Integration with App2Container

### Workflow Integration
1. **Discovery**: Use App2Container inventory on source machines
2. **Analysis**: Analyze applications and dependencies
3. **Containerization**: Generate Docker containers and artifacts
4. **Deployment**: Use this infrastructure for hosting containerized applications
5. **CI/CD**: Leverage the included pipeline for ongoing deployments

### Supported Application Types
- Java applications (Tomcat, JBoss, WebLogic)
- .NET Framework applications (IIS hosted)
- Applications with complex dependencies
- Multi-tier applications with databases

## Support and Resources

### Documentation
- [AWS App2Container User Guide](https://docs.aws.amazon.com/app2container/latest/UserGuide/what-is-a2c.html)
- [Amazon ECS Developer Guide](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/)
- [AWS CloudFormation User Guide](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/)

### Best Practices
- Test containerization in non-production environments first
- Implement comprehensive monitoring and alerting
- Use least privilege IAM policies
- Enable container image scanning
- Implement automated backup strategies
- Regular security assessments and updates

### Community Resources
- [AWS App2Container GitHub](https://github.com/aws-samples/app2container-migration)
- [AWS Containers Roadmap](https://github.com/aws/containers-roadmap)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)

For issues with this infrastructure code, refer to the original recipe documentation or AWS support resources.