# Infrastructure as Code for CodeBuild Multi-Architecture Container Images

This directory contains Infrastructure as Code (IaC) implementations for the recipe "CodeBuild Multi-Architecture Container Images".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Docker installed and running (for local testing)
- Appropriate AWS permissions for:
  - CodeBuild project creation and management
  - ECR repository creation and image management
  - IAM role creation and policy management
  - S3 bucket creation and object management
  - CloudWatch Logs access
- Basic understanding of Docker and containerization concepts
- Familiarity with multi-architecture container builds

## Quick Start

### Using CloudFormation

```bash
# Create the stack
aws cloudformation create-stack \
    --stack-name multi-arch-codebuild-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=my-multi-arch-project

# Monitor stack creation
aws cloudformation wait stack-create-complete \
    --stack-name multi-arch-codebuild-stack

# Get outputs
aws cloudformation describe-stacks \
    --stack-name multi-arch-codebuild-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# Get outputs
cdk ls --long
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# Get outputs
cdk ls --long
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the configuration
terraform apply

# Get outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for required parameters
# and provide status updates during deployment
```

## Architecture Overview

The infrastructure creates:

- **ECR Repository**: Container registry for storing multi-architecture images
- **CodeBuild Project**: Build environment with privileged mode for Docker Buildx
- **IAM Role**: Service role with permissions for CodeBuild operations
- **S3 Bucket**: Storage for source code artifacts
- **CloudWatch Logs**: Build logging and monitoring

## Usage After Deployment

1. **Upload your source code** to the created S3 bucket or configure your preferred source provider
2. **Start a build** using the CodeBuild project
3. **Monitor progress** through the AWS Console or CLI
4. **Verify the multi-architecture image** in the ECR repository

### Starting a Build

```bash
# Get the project name from outputs
PROJECT_NAME=$(terraform output -raw codebuild_project_name)

# Start a build
aws codebuild start-build --project-name $PROJECT_NAME

# Monitor build status
aws codebuild list-builds-for-project --project-name $PROJECT_NAME
```

### Verifying Multi-Architecture Images

```bash
# Get ECR repository URI from outputs
ECR_URI=$(terraform output -raw ecr_repository_uri)

# Inspect the multi-architecture manifest
docker buildx imagetools inspect $ECR_URI:latest

# Login to ECR
aws ecr get-login-password --region $(aws configure get region) | \
    docker login --username AWS --password-stdin $ECR_URI

# Pull specific architecture variants
docker pull --platform linux/amd64 $ECR_URI:latest
docker pull --platform linux/arm64 $ECR_URI:latest
```

## Customization

### Variables and Parameters

Each implementation supports customization through variables:

- **Project Name**: Unique identifier for the CodeBuild project
- **ECR Repository Name**: Name for the container registry
- **Build Timeout**: Maximum build duration in minutes
- **Build Environment**: CodeBuild compute type and image
- **Source Location**: S3 bucket and key for source code
- **Cache Settings**: Build cache configuration for optimization

### Sample Application

The infrastructure includes a sample Node.js application that demonstrates multi-architecture capabilities:

```javascript
// app.js - Reports system architecture
const os = require('os');
console.log(`Running on ${os.arch()} architecture`);
console.log(`Platform: ${os.platform()}`);
```

### Dockerfile Optimization

The included Dockerfile supports multi-architecture builds:

```dockerfile
# Multi-stage build with architecture awareness
FROM --platform=$BUILDPLATFORM node:18-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

FROM node:18-alpine AS runtime
# ... optimized for both ARM64 and x86_64
```

## Cost Considerations

- **CodeBuild**: Charged per build minute based on compute type
- **ECR**: Storage costs for container images
- **S3**: Storage costs for source code artifacts
- **CloudWatch**: Logging costs (usually minimal)

Estimated cost: $0.50-$2.00 per build hour depending on compute type and build frequency.

## Security Features

- **IAM Least Privilege**: Service roles with minimal required permissions
- **ECR Image Scanning**: Automated vulnerability scanning enabled
- **Encryption**: ECR repositories use AES-256 encryption
- **Network Security**: CodeBuild runs in secure, isolated environment
- **No Hardcoded Secrets**: All credentials managed through IAM roles

## Monitoring and Troubleshooting

### Build Logs

```bash
# View build logs
aws logs describe-log-groups --log-group-name-prefix /aws/codebuild/

# Stream logs for active build
aws logs tail /aws/codebuild/your-project-name --follow
```

### Common Issues

1. **Build Fails with Permission Errors**: Ensure privileged mode is enabled
2. **Docker Buildx Not Found**: Verify CodeBuild image supports Docker Buildx
3. **ECR Push Failures**: Check IAM permissions for ECR operations
4. **Out of Memory Errors**: Increase CodeBuild compute type

## Performance Optimization

- **Build Caching**: Configured for Docker layer caching
- **Parallel Builds**: Buildx builds ARM64 and x86_64 simultaneously
- **Resource Sizing**: Optimized compute types for build requirements
- **Cache Management**: Automatic cache cleanup to prevent storage bloat

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name multi-arch-codebuild-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name multi-arch-codebuild-stack
```

### Using CDK

```bash
# From the CDK directory
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# From the terraform directory
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation
# and provide status updates during cleanup
```

## Advanced Configuration

### Custom Build Environment

Modify the CodeBuild environment for specific requirements:

```yaml
# CloudFormation example
Environment:
  Type: LINUX_CONTAINER
  Image: aws/codebuild/amazonlinux2-x86_64-standard:4.0
  ComputeType: BUILD_GENERAL1_LARGE
  PrivilegedMode: true
```

### Multi-Source Builds

Configure multiple source inputs:

```yaml
# Support for multiple source repositories
SecondarySourceVersions:
  - SourceIdentifier: config
    SourceVersion: main
```

### Build Notifications

Add SNS notifications for build status:

```yaml
# CloudFormation example
NotificationRule:
  Type: AWS::CodeStarNotifications::NotificationRule
  Properties:
    Name: BuildNotifications
    Resource: !GetAtt CodeBuildProject.Arn
    EventTypeIds:
      - codebuild-project-build-state-succeeded
      - codebuild-project-build-state-failed
```

## Integration Examples

### CI/CD Pipeline Integration

```yaml
# Example: Integrate with CodePipeline
Pipeline:
  Type: AWS::CodePipeline::Pipeline
  Properties:
    Stages:
      - Name: Source
        Actions:
          - Name: SourceAction
            ActionTypeId:
              Category: Source
              Owner: AWS
              Provider: S3
      - Name: Build
        Actions:
          - Name: BuildAction
            ActionTypeId:
              Category: Build
              Owner: AWS
              Provider: CodeBuild
            Configuration:
              ProjectName: !Ref CodeBuildProject
```

### Container Deployment

```bash
# Deploy to ECS with automatic architecture selection
aws ecs create-service \
    --cluster my-cluster \
    --service-name my-service \
    --task-definition my-task:1 \
    --desired-count 2

# The same image reference works for both ARM and x86 instances
```

## Support

For issues with this infrastructure code, refer to:

- Original recipe documentation in the parent directory
- [AWS CodeBuild Documentation](https://docs.aws.amazon.com/codebuild/)
- [Docker Buildx Documentation](https://docs.docker.com/buildx/)
- [Amazon ECR Documentation](https://docs.aws.amazon.com/ecr/)

## Contributing

To improve this infrastructure code:

1. Test changes thoroughly in a development environment
2. Follow AWS best practices and security guidelines
3. Update documentation for any parameter changes
4. Ensure compatibility across all implementation types