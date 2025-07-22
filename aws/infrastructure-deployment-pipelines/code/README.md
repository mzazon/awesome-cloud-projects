# Infrastructure as Code for Infrastructure Deployment Pipelines with CDK

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Infrastructure Deployment Pipelines with CDK".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Node.js 18+ and npm/yarn for CDK development
- Terraform 1.0+ (for Terraform implementation)
- Git for version control
- Appropriate AWS permissions for CDK, CodePipeline, CodeBuild, CodeCommit, and CloudFormation
- CDK bootstrap completed: `cdk bootstrap aws://ACCOUNT-ID/REGION`

## Quick Start

### Using CloudFormation (AWS)

```bash
# Set required parameters
export PROJECT_NAME="my-pipeline-project"
export REPO_NAME="my-infrastructure-repo"

# Deploy the stack
aws cloudformation create-stack \
    --stack-name cdk-pipeline-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ProjectName,ParameterValue=$PROJECT_NAME \
                 ParameterKey=RepositoryName,ParameterValue=$REPO_NAME \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Monitor deployment
aws cloudformation wait stack-create-complete \
    --stack-name cdk-pipeline-stack
```

### Using CDK TypeScript (AWS)

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Set environment variables
export PROJECT_NAME="my-pipeline-project"
export REPO_NAME="my-infrastructure-repo"

# Deploy the pipeline
cdk deploy --all

# View outputs
cdk output
```

### Using CDK Python (AWS)

```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export PROJECT_NAME="my-pipeline-project"
export REPO_NAME="my-infrastructure-repo"

# Deploy the pipeline
cdk deploy --all

# View outputs
cdk output
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Set variables (create terraform.tfvars)
cat > terraform.tfvars << EOF
project_name = "my-pipeline-project"
repository_name = "my-infrastructure-repo"
aws_region = "us-east-1"
EOF

# Plan deployment
terraform plan

# Apply configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Set required environment variables
export PROJECT_NAME="my-pipeline-project"
export REPO_NAME="my-infrastructure-repo"
export AWS_REGION="us-east-1"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
aws codepipeline get-pipeline-state \
    --name InfrastructurePipeline
```

## Post-Deployment Setup

After deploying the pipeline infrastructure, you'll need to:

1. **Initialize your CDK project**:
   ```bash
   # Clone the created repository
   git clone https://git-codecommit.REGION.amazonaws.com/v1/repos/REPO_NAME
   cd REPO_NAME
   
   # Initialize CDK project
   npx cdk init app --language typescript
   ```

2. **Add pipeline code** (example structure):
   ```bash
   # Install pipeline dependencies
   npm install @aws-cdk/pipelines
   
   # Create your pipeline stack (see recipe for complete implementation)
   # lib/pipeline-stack.ts
   # bin/your-app.ts
   ```

3. **Push initial code**:
   ```bash
   git add .
   git commit -m "Initial pipeline setup"
   git push origin main
   ```

## Architecture Components

The deployed infrastructure includes:

- **CodeCommit Repository**: Git repository for infrastructure code
- **CodePipeline**: Orchestrates the CI/CD workflow
- **CodeBuild Projects**: Builds and tests the CDK application
- **IAM Roles**: Service roles for pipeline execution
- **S3 Buckets**: Artifact storage for pipeline
- **CloudWatch Logs**: Pipeline execution logs
- **SNS Topics**: Notifications for pipeline events

## Environment Variables

### Required Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PROJECT_NAME` | Unique project identifier | `cdk-pipeline-project` |
| `REPO_NAME` | CodeCommit repository name | `infrastructure-repo` |
| `AWS_REGION` | AWS region for deployment | `us-east-1` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `NOTIFICATION_EMAIL` | Email for pipeline notifications | None |
| `ENABLE_APPROVAL_STAGE` | Enable manual approval for production | `true` |
| `BUILD_TIMEOUT` | CodeBuild timeout in minutes | `60` |

## Customization

### Pipeline Configuration

Modify the pipeline configuration by updating:

- **Source stage**: Change repository or branch
- **Build stage**: Modify build commands or environment
- **Deploy stages**: Add/remove deployment environments
- **Approval gates**: Configure manual approval requirements

### Security Settings

- **IAM Policies**: Customize service permissions
- **Encryption**: Enable KMS encryption for artifacts
- **VPC Configuration**: Deploy build projects in VPC
- **Security Scanning**: Add security validation stages

### Monitoring and Alerts

- **CloudWatch Alarms**: Set up pipeline failure alerts
- **SNS Notifications**: Configure email/SMS notifications
- **CloudTrail**: Enable API call logging
- **Cost Monitoring**: Set up budget alerts

## Troubleshooting

### Common Issues

1. **Bootstrap Error**: Ensure CDK is bootstrapped in target region
   ```bash
   cdk bootstrap aws://ACCOUNT-ID/REGION
   ```

2. **Permission Denied**: Verify IAM permissions for all services
   ```bash
   # Check current user permissions
   aws sts get-caller-identity
   aws iam get-user
   ```

3. **Pipeline Failures**: Check CloudWatch logs for build errors
   ```bash
   aws logs describe-log-groups --log-group-name-prefix /aws/codebuild/
   ```

### Debugging Commands

```bash
# Check pipeline status
aws codepipeline get-pipeline-state --name InfrastructurePipeline

# View recent executions
aws codepipeline list-pipeline-executions --pipeline-name InfrastructurePipeline

# Check build logs
aws logs get-log-events \
    --log-group-name /aws/codebuild/PROJECT_NAME \
    --log-stream-name STREAM_NAME
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name cdk-pipeline-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name cdk-pipeline-stack

# Clean up CDK bootstrap (if no longer needed)
aws cloudformation delete-stack --stack-name CDKToolkit
```

### Using CDK (AWS)

```bash
# Destroy all stacks
cdk destroy --all

# Confirm deletion
cdk list
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Manual cleanup if needed
aws codecommit delete-repository --repository-name $REPO_NAME
```

## Security Considerations

- **Least Privilege**: All IAM roles follow principle of least privilege
- **Encryption**: Artifacts are encrypted at rest and in transit
- **Audit Logging**: All API calls are logged via CloudTrail
- **Network Security**: Build projects can be deployed in private subnets
- **Secret Management**: Use AWS Secrets Manager for sensitive data

## Cost Optimization

- **Build Optimization**: Use build caching to reduce build times
- **Resource Cleanup**: Automatically clean up temporary resources
- **Reserved Capacity**: Consider reserved capacity for frequent builds
- **Monitoring**: Set up cost alerts for unexpected usage

## Best Practices

1. **Version Control**: Keep all infrastructure code in version control
2. **Testing**: Implement automated testing for infrastructure changes
3. **Documentation**: Document all customizations and configurations
4. **Monitoring**: Set up comprehensive monitoring and alerting
5. **Security**: Regularly review and update security configurations
6. **Backup**: Implement backup strategies for critical components

## Support

For issues with this infrastructure code, refer to:

- [Original Recipe Documentation](../infrastructure-deployment-pipelines-cdk-codepipeline.md)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [AWS CodePipeline Documentation](https://docs.aws.amazon.com/codepipeline/)
- [AWS CodeBuild Documentation](https://docs.aws.amazon.com/codebuild/)
- [AWS CodeCommit Documentation](https://docs.aws.amazon.com/codecommit/)

## License

This infrastructure code is provided under the same license as the parent recipe repository.