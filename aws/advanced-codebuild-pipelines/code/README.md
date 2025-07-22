# Infrastructure as Code for Building Advanced CodeBuild Pipelines with Multi-Stage Builds, Caching, and Artifacts Management

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Building Advanced CodeBuild Pipelines with Multi-Stage Builds, Caching, and Artifacts Management".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation deploys a comprehensive CI/CD pipeline solution featuring:

- **Multi-Stage CodeBuild Projects**: Dependency, main build, and parallel build projects
- **Intelligent Caching**: S3-based caching with automated lifecycle management
- **Container Registry**: ECR repository with vulnerability scanning
- **Build Orchestration**: Lambda-based pipeline coordination
- **Analytics & Monitoring**: CloudWatch dashboards and automated reporting
- **Artifact Management**: Versioned storage with comprehensive metadata

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - CodeBuild project creation and management
  - S3 bucket creation and management
  - ECR repository creation and management
  - IAM role and policy management
  - Lambda function deployment
  - CloudWatch dashboard creation
  - EventBridge rule management
- Docker knowledge for containerized builds
- Understanding of CI/CD pipeline concepts
- Node.js 18+ (for CDK TypeScript implementation)
- Python 3.9+ (for CDK Python implementation)
- Terraform 1.0+ (for Terraform implementation)

## Cost Considerations

Estimated monthly costs for moderate usage:
- CodeBuild compute time: $20-100 (varies by build frequency and compute type)
- S3 storage (cache and artifacts): $5-25
- ECR storage: $5-15
- Lambda executions: $1-5
- CloudWatch logs and metrics: $2-10

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name advanced-codebuild-pipeline \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters \
        ParameterKey=ProjectName,ParameterValue=my-advanced-build \
        ParameterKey=Environment,ParameterValue=dev

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name advanced-codebuild-pipeline \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name advanced-codebuild-pipeline \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy AdvancedCodeBuildPipelineStack

# View outputs
cdk ls --long
```

### Using CDK Python

```bash
# Navigate to CDK directory
cd cdk-python/

# Create and activate virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy AdvancedCodeBuildPipelineStack

# View outputs
cdk ls --long
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply the configuration
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

# View deployment status
aws codebuild list-projects --query "projects[?contains(@, 'advanced-build')]"
```

## Configuration Options

### Common Parameters

All implementations support these configuration options:

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| ProjectName | Unique name for the build project | advanced-build | Yes |
| Environment | Environment name (dev, staging, prod) | dev | No |
| CacheRetentionDays | Days to retain build cache | 30 | No |
| ArtifactRetentionDays | Days to retain build artifacts | 90 | No |
| EnableParallelBuilds | Enable parallel architecture builds | true | No |
| ComputeType | CodeBuild compute type | BUILD_GENERAL1_LARGE | No |
| BuildTimeout | Build timeout in minutes | 60 | No |

### CloudFormation Parameters

```yaml
Parameters:
  ProjectName:
    Type: String
    Default: advanced-build
    Description: Unique name for the build project
  Environment:
    Type: String
    Default: dev
    AllowedValues: [dev, staging, prod]
    Description: Environment name
```

### CDK Configuration

```typescript
// CDK TypeScript
const config = {
  projectName: 'advanced-build',
  environment: 'dev',
  cacheRetentionDays: 30,
  artifactRetentionDays: 90,
  enableParallelBuilds: true
};
```

```python
# CDK Python
config = {
    "project_name": "advanced-build",
    "environment": "dev",
    "cache_retention_days": 30,
    "artifact_retention_days": 90,
    "enable_parallel_builds": True
}
```

### Terraform Variables

```hcl
# terraform.tfvars
project_name = "advanced-build"
environment = "dev"
cache_retention_days = 30
artifact_retention_days = 90
enable_parallel_builds = true
```

## Post-Deployment Setup

After deploying the infrastructure, complete these steps:

### 1. Upload Sample Application

```bash
# Get bucket name from outputs
ARTIFACT_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name advanced-codebuild-pipeline \
    --query 'Stacks[0].Outputs[?OutputKey==`ArtifactBucketName`].OutputValue' \
    --output text)

# Create and upload sample application
mkdir sample-app
cd sample-app

# Create package.json
cat > package.json << 'EOF'
{
  "name": "sample-app",
  "version": "1.0.0",
  "scripts": {
    "test": "echo \"No tests specified\" && exit 0",
    "build": "echo \"Build completed\""
  }
}
EOF

# Create Dockerfile
cat > Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
EXPOSE 3000
CMD ["npm", "start"]
EOF

# Create buildspec
cat > buildspec.yml << 'EOF'
version: 0.2
phases:
  install:
    runtime-versions:
      nodejs: 18
  pre_build:
    commands:
      - echo Logging in to Amazon ECR...
      - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com
  build:
    commands:
      - echo Build started on `date`
      - npm install
      - npm run build
      - docker build -t $IMAGE_REPO_NAME:$IMAGE_TAG .
      - docker tag $IMAGE_REPO_NAME:$IMAGE_TAG $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:$IMAGE_TAG
  post_build:
    commands:
      - echo Build completed on `date`
      - docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:$IMAGE_TAG
EOF

# Package and upload
tar -czf source.tar.gz .
aws s3 cp source.tar.gz s3://${ARTIFACT_BUCKET}/source/source.zip
cd ..
rm -rf sample-app
```

### 2. Test Build Pipeline

```bash
# Get orchestrator function name
ORCHESTRATOR_FUNCTION=$(aws cloudformation describe-stacks \
    --stack-name advanced-codebuild-pipeline \
    --query 'Stacks[0].Outputs[?OutputKey==`BuildOrchestratorFunction`].OutputValue' \
    --output text)

# Test build execution
cat > test-build.json << EOF
{
  "buildConfig": {
    "sourceLocation": "s3://${ARTIFACT_BUCKET}/source/source.zip",
    "parallelBuilds": ["amd64"]
  }
}
EOF

aws lambda invoke \
    --function-name ${ORCHESTRATOR_FUNCTION} \
    --payload file://test-build.json \
    --cli-binary-format raw-in-base64-out \
    result.json

# Check result
cat result.json
```

### 3. Access CloudWatch Dashboard

```bash
# Get dashboard URL
DASHBOARD_NAME=$(aws cloudformation describe-stacks \
    --stack-name advanced-codebuild-pipeline \
    --query 'Stacks[0].Outputs[?OutputKey==`CloudWatchDashboard`].OutputValue' \
    --output text)

echo "Dashboard available at: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASHBOARD_NAME}"
```

## Outputs

### CloudFormation Outputs

- `CacheBucketName`: S3 bucket for build caching
- `ArtifactBucketName`: S3 bucket for build artifacts
- `ECRRepositoryURI`: ECR repository URI for container images
- `DependencyBuildProject`: CodeBuild project for dependencies
- `MainBuildProject`: CodeBuild project for main builds
- `ParallelBuildProject`: CodeBuild project for parallel builds
- `BuildOrchestratorFunction`: Lambda function for build orchestration
- `CloudWatchDashboard`: CloudWatch dashboard name
- `BuildRoleArn`: IAM role ARN for CodeBuild projects

### Resource Naming Convention

Resources follow the pattern: `{ProjectName}-{Environment}-{ResourceType}-{RandomSuffix}`

Examples:
- S3 Buckets: `advanced-build-dev-cache-a1b2c3d4`
- CodeBuild Projects: `advanced-build-dev-main-a1b2c3d4`
- Lambda Functions: `advanced-build-dev-orchestrator-a1b2c3d4`

## Monitoring and Troubleshooting

### CloudWatch Logs

Monitor build execution through CloudWatch log groups:

```bash
# List CodeBuild log groups
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/codebuild/advanced-build"

# View recent build logs
aws logs tail "/aws/codebuild/advanced-build-dev-main" --follow
```

### Build Metrics

Key metrics to monitor:
- Build success rate
- Average build duration
- Cache hit rate
- Resource utilization
- Cost per build

### Common Issues

1. **Build Failures**: Check CloudWatch logs for specific error messages
2. **Cache Misses**: Verify S3 bucket permissions and lifecycle policies
3. **ECR Push Failures**: Ensure proper IAM permissions for ECR operations
4. **Timeout Issues**: Adjust build timeout settings based on project complexity

## Security Considerations

### IAM Permissions

The implementation follows the principle of least privilege:
- CodeBuild projects have minimal required permissions
- S3 buckets use server-side encryption
- ECR repositories have vulnerability scanning enabled
- Lambda functions have restricted execution roles

### Network Security

- CodeBuild projects run in AWS-managed VPC
- ECR repositories use HTTPS endpoints
- S3 buckets block public access by default

### Data Protection

- All data in transit is encrypted using TLS
- S3 objects are encrypted at rest using AES-256
- ECR images are scanned for vulnerabilities
- CloudWatch logs are encrypted

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name advanced-codebuild-pipeline

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name advanced-codebuild-pipeline \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# From the CDK directory
cdk destroy AdvancedCodeBuildPipelineStack

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
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

### Manual Cleanup (if needed)

If automated cleanup fails, manually delete resources:

```bash
# Empty S3 buckets first
aws s3 rm s3://advanced-build-dev-cache-* --recursive
aws s3 rm s3://advanced-build-dev-artifacts-* --recursive

# Delete ECR images
aws ecr list-images --repository-name advanced-build-dev-repo-* \
    --query 'imageIds[*]' --output json > images.json
aws ecr batch-delete-image --repository-name advanced-build-dev-repo-* \
    --image-ids file://images.json

# Then re-run the cleanup script
```

## Customization

### Adding Custom Build Steps

To add custom build steps, modify the buildspec files in your source code:

```yaml
# buildspec.yml
version: 0.2
phases:
  pre_build:
    commands:
      - echo Custom pre-build step
      - # Add your custom commands here
  build:
    commands:
      - echo Custom build step
      - # Add your custom build commands here
  post_build:
    commands:
      - echo Custom post-build step
      - # Add your custom post-build commands here
```

### Extending Pipeline Stages

To add additional pipeline stages:

1. Create new CodeBuild projects in the IaC templates
2. Update the Lambda orchestrator to include new stages
3. Modify EventBridge rules for new scheduling requirements
4. Update IAM permissions for new resources

### Custom Caching Strategies

Implement custom caching by modifying:

1. S3 lifecycle policies for different cache types
2. CodeBuild cache configurations
3. Lambda cache management logic

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review AWS CodeBuild documentation
3. Consult AWS support for service-specific issues
4. Review CloudWatch logs for troubleshooting

## Contributing

To improve this IaC implementation:

1. Follow AWS best practices
2. Test changes thoroughly
3. Update documentation accordingly
4. Consider backward compatibility

## Version History

- v1.0: Initial implementation with multi-stage builds and caching
- v1.1: Added parallel build support and enhanced monitoring
- v1.2: Improved security configurations and analytics

## Related Resources

- [AWS CodeBuild User Guide](https://docs.aws.amazon.com/codebuild/latest/userguide/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/latest/guide/)
- [AWS CloudFormation User Guide](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)