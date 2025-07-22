# Infrastructure as Code for ECS Task Environment Variable Management

This directory contains Infrastructure as Code (IaC) implementations for the recipe "ECS Task Environment Variable Management".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This IaC deploys a comprehensive environment variable management solution for Amazon ECS, including:

- ECS Cluster with Fargate capacity providers
- Task definitions with multiple environment variable sources
- Systems Manager Parameter Store hierarchical configuration
- S3 bucket for environment files
- IAM roles with least-privilege access
- CloudWatch logging for monitoring

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amazon ECS (clusters, services, task definitions)
  - AWS Systems Manager Parameter Store
  - AWS Secrets Manager
  - Amazon S3
  - AWS IAM (roles and policies)
  - Amazon CloudWatch Logs
- Node.js 18+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name ecs-envvar-management \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ClusterName,ParameterValue=ecs-envvar-cluster \
                 ParameterKey=TaskFamily,ParameterValue=envvar-demo-task \
    --capabilities CAPABILITY_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name ecs-envvar-management

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name ecs-envvar-management \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy --require-approval never

# View outputs
npx cdk list
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk list
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply the configuration
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

# View deployment status
aws ecs describe-clusters --clusters $(cat .cluster-name)
```

## Configuration Options

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| ClusterName | Name of the ECS cluster | ecs-envvar-cluster | No |
| TaskFamily | Task definition family name | envvar-demo-task | No |
| ServiceName | ECS service name | envvar-demo-service | No |
| ContainerImage | Container image to deploy | nginx:latest | No |
| Environment | Environment identifier | dev | No |

### CDK Configuration

Modify the following in `app.ts` or `app.py`:

```typescript
// cdk-typescript/app.ts
const props = {
  clusterName: 'ecs-envvar-cluster',
  taskFamily: 'envvar-demo-task',
  environment: 'dev',
  containerImage: 'nginx:latest'
};
```

```python
# cdk-python/app.py
props = {
    'cluster_name': 'ecs-envvar-cluster',
    'task_family': 'envvar-demo-task',
    'environment': 'dev',
    'container_image': 'nginx:latest'
}
```

### Terraform Variables

Edit `terraform/terraform.tfvars` or pass variables during deployment:

```hcl
cluster_name = "ecs-envvar-cluster"
task_family = "envvar-demo-task"
service_name = "envvar-demo-service"
environment = "dev"
container_image = "nginx:latest"
```

## Environment Variable Management

The deployed infrastructure supports three methods for environment variable injection:

### 1. Direct Environment Variables
Hard-coded values in task definitions for static configuration:
```json
"environment": [
    {
        "name": "NODE_ENV",
        "value": "development"
    }
]
```

### 2. Systems Manager Parameter Store
Hierarchical parameter management with encryption support:
```json
"secrets": [
    {
        "name": "DATABASE_HOST",
        "valueFrom": "/myapp/dev/database/host"
    }
]
```

### 3. Environment Files (S3)
Batch configuration loading from S3:
```json
"environmentFiles": [
    {
        "value": "arn:aws:s3:::bucket/configs/app-config.env",
        "type": "s3"
    }
]
```

## Validation

After deployment, verify the infrastructure:

```bash
# Check ECS cluster status
aws ecs describe-clusters --clusters YOUR_CLUSTER_NAME

# Verify task definition
aws ecs describe-task-definition --task-definition YOUR_TASK_FAMILY

# List Parameter Store parameters
aws ssm get-parameters-by-path --path "/myapp" --recursive

# Check S3 bucket contents
aws s3 ls s3://YOUR_BUCKET_NAME/configs/

# View service status
aws ecs describe-services \
    --cluster YOUR_CLUSTER_NAME \
    --services YOUR_SERVICE_NAME
```

## Monitoring and Logging

The infrastructure includes CloudWatch integration:

- **Container Logs**: `/ecs/YOUR_TASK_FAMILY`
- **Service Metrics**: ECS service-level metrics
- **Parameter Access**: CloudTrail logs for Parameter Store access

View logs:
```bash
# List log streams
aws logs describe-log-streams \
    --log-group-name "/ecs/YOUR_TASK_FAMILY"

# View recent logs
aws logs get-log-events \
    --log-group-name "/ecs/YOUR_TASK_FAMILY" \
    --log-stream-name "STREAM_NAME"
```

## Security Considerations

The deployed infrastructure implements security best practices:

- **IAM Least Privilege**: Task execution roles have minimal required permissions
- **Parameter Encryption**: Sensitive parameters use SecureString type
- **Network Security**: Tasks deploy in private subnets with NAT gateway access
- **Secret Management**: No hardcoded secrets in container images
- **Access Logging**: S3 bucket access logging enabled

## Cost Optimization

Monitor costs using these strategies:

- **Fargate Spot**: Consider using Fargate Spot for development environments
- **Parameter Store**: Monitor parameter API calls (charged after free tier)
- **S3 Storage**: Use appropriate storage classes for environment files
- **CloudWatch Logs**: Set log retention periods to manage storage costs

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name ecs-envvar-management

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name ecs-envvar-management
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npx cdk destroy --force
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

# Verify cleanup
aws ecs describe-clusters --clusters $(cat .cluster-name) 2>/dev/null || echo "Cluster deleted"
```

## Troubleshooting

### Common Issues

1. **Task Startup Failures**
   - Check CloudWatch logs for container startup errors
   - Verify IAM permissions for Parameter Store and S3 access
   - Ensure parameter paths exist and are accessible

2. **Parameter Store Access Denied**
   - Verify IAM role has `ssm:GetParameter*` permissions
   - Check parameter names match exactly (case sensitive)
   - Ensure SecureString parameters have KMS permissions

3. **Environment File Loading Issues**
   - Verify S3 bucket and object permissions
   - Check environment file format (KEY=VALUE pairs)
   - Ensure task execution role has S3 GetObject permissions

4. **Service Won't Start**
   - Check security group rules allow necessary traffic
   - Verify subnet configuration and NAT gateway connectivity
   - Review task definition resource requirements

### Debug Commands

```bash
# Check task execution role permissions
aws iam get-role --role-name YOUR_EXECUTION_ROLE_NAME

# Test parameter access
aws ssm get-parameter --name "/myapp/dev/database/host"

# Verify S3 access
aws s3 cp s3://YOUR_BUCKET/configs/app-config.env /tmp/test.env

# Check task failure reasons
aws ecs describe-tasks --cluster YOUR_CLUSTER --tasks TASK_ARN
```

## Advanced Configuration

### Multi-Environment Setup

To deploy multiple environments:

```bash
# Deploy development environment
terraform apply -var="environment=dev" -var="cluster_name=ecs-dev"

# Deploy staging environment
terraform apply -var="environment=staging" -var="cluster_name=ecs-staging"

# Deploy production environment
terraform apply -var="environment=prod" -var="cluster_name=ecs-prod"
```

### Custom Container Images

Replace the default nginx image with your application:

1. Build and push your container image to ECR
2. Update the container image parameter in your chosen IaC tool
3. Modify environment variables and secrets as needed for your application

### Scaling Configuration

Modify service scaling settings:

```hcl
# terraform/main.tf
resource "aws_ecs_service" "app_service" {
  desired_count = 2  # Increase for higher availability
  
  deployment_configuration {
    maximum_percent         = 200
    minimum_healthy_percent = 100
  }
}
```

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS ECS documentation for service-specific guidance
3. Consult AWS Systems Manager Parameter Store documentation
4. Review CloudWatch logs for application-specific errors

## Additional Resources

- [Amazon ECS Task Definitions](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definitions.html)
- [Systems Manager Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html)
- [ECS Environment Files](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/use-environment-file.html)
- [ECS Task Execution IAM Role](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html)