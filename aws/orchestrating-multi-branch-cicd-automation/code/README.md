# Infrastructure as Code for Orchestrating Multi-Branch CI/CD Automation with CodePipeline

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Orchestrating Multi-Branch CI/CD Automation with CodePipeline".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for creating CodePipeline, CodeCommit, CodeBuild, Lambda, EventBridge, and IAM resources
- Git configured for CodeCommit access
- Node.js and npm (for CDK TypeScript)
- Python 3.8+ and pip (for CDK Python)
- Terraform v1.0+ (for Terraform deployment)

### Required AWS Permissions

Your AWS credentials must have permissions to create:
- CodePipeline pipelines and related resources
- CodeCommit repositories
- CodeBuild projects
- Lambda functions
- EventBridge rules and targets
- IAM roles and policies
- S3 buckets
- CloudWatch dashboards and alarms
- SNS topics

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name multi-branch-cicd-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=RepositoryName,ParameterValue=my-multi-branch-repo \
                 ParameterKey=Environment,ParameterValue=dev

# Check stack status
aws cloudformation describe-stacks \
    --stack-name multi-branch-cicd-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk output
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv

# Activate virtual environment
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk output
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Plan deployment
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

# Check deployment status
aws codepipeline list-pipelines \
    --query 'pipelines[?contains(name, `multi-branch-app`)]'
```

## Architecture Overview

This infrastructure creates a complete multi-branch CI/CD system with the following components:

### Core Components

1. **CodeCommit Repository**: Central Git repository for source code
2. **Lambda Pipeline Manager**: Automates pipeline creation and deletion based on branch events
3. **EventBridge Rules**: Trigger pipeline management on branch lifecycle events
4. **CodeBuild Project**: Shared build environment for all branches
5. **CodePipeline**: Separate pipelines for main/develop (permanent) and feature branches (ephemeral)
6. **IAM Roles**: Secure service-to-service communication
7. **S3 Artifact Store**: Pipeline artifact storage
8. **CloudWatch Monitoring**: Pipeline performance and failure monitoring

### Pipeline Types

- **Main Pipeline**: Permanent pipeline for production deployments
- **Develop Pipeline**: Permanent pipeline for staging deployments
- **Feature Pipelines**: Automatically created for `feature/*` branches, automatically deleted when branch is removed

## Configuration

### Environment Variables

The deployment creates several environment-specific resources. Key configuration options:

- `REPOSITORY_NAME`: Name of the CodeCommit repository
- `ENVIRONMENT`: Environment tag (dev, staging, prod)
- `AWS_REGION`: AWS region for deployment
- `ARTIFACT_BUCKET_NAME`: S3 bucket for pipeline artifacts

### Customization Options

#### Branch Patterns
Modify the Lambda function code to change which branches trigger pipeline creation:

```python
# Current: Only feature/* branches create dynamic pipelines
if branch_name.startswith('feature/'):
    # Create pipeline logic
```

#### Pipeline Templates
Customize pipeline stages by modifying the pipeline definition in the Lambda function or IaC templates.

#### Build Specifications
Update the CodeBuild project configuration to change build commands, environment, or compute resources.

## Testing the Deployment

### 1. Create Feature Branch

```bash
# Clone the repository
git clone https://codecommit.{region}.amazonaws.com/v1/repos/{repository-name}
cd {repository-name}

# Create and push feature branch
git checkout -b feature/test-pipeline
echo "# Test Feature" > test.md
git add test.md
git commit -m "Add test feature"
git push origin feature/test-pipeline
```

### 2. Verify Pipeline Creation

```bash
# Check if pipeline was created (wait 30-60 seconds)
aws codepipeline list-pipelines \
    --query 'pipelines[?contains(name, `feature-test-pipeline`)]'

# Check pipeline execution
aws codepipeline get-pipeline-state \
    --name {repository-name}-feature-test-pipeline
```

### 3. Test Pipeline Cleanup

```bash
# Delete feature branch
git push origin --delete feature/test-pipeline

# Verify pipeline deletion (wait 30-60 seconds)
aws codepipeline get-pipeline \
    --name {repository-name}-feature-test-pipeline
# Should return PipelineNotFoundException
```

## Monitoring and Troubleshooting

### CloudWatch Logs

Monitor Lambda function execution:

```bash
# View Lambda logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/pipeline-manager"

# Stream logs
aws logs tail /aws/lambda/pipeline-manager-{suffix} --follow
```

### Pipeline Monitoring

Access the CloudWatch dashboard created by the deployment:

1. Navigate to CloudWatch in AWS Console
2. Select "Dashboards" from the left menu
3. Open "MultibranchPipelines-{suffix}"

### Common Issues

1. **Pipeline Creation Fails**: Check Lambda function logs for IAM permission errors
2. **Build Failures**: Review CodeBuild logs and build specifications
3. **EventBridge Not Triggering**: Verify EventBridge rule configuration and Lambda permissions
4. **S3 Access Denied**: Check S3 bucket policies and IAM role permissions

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name multi-branch-cicd-stack

# Monitor deletion
aws cloudformation describe-stacks \
    --stack-name multi-branch-cicd-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK (AWS)

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
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

If automated cleanup fails, manually delete resources in this order:

1. Delete all CodePipeline pipelines
2. Delete Lambda function
3. Delete EventBridge rules
4. Delete CodeBuild project
5. Delete IAM roles
6. Delete S3 bucket (empty first)
7. Delete CodeCommit repository
8. Delete CloudWatch resources

## Security Considerations

### IAM Policies

The deployment follows least privilege principles:

- CodePipeline role has minimal permissions for source, build, and artifact access
- CodeBuild role has permissions for logging and artifact storage
- Lambda role has permissions for pipeline management only

### Network Security

- All resources operate within AWS managed networks
- No public endpoints are exposed
- CodeCommit provides secure Git over HTTPS

### Secrets Management

- No hardcoded secrets in the infrastructure
- Service-to-service communication uses IAM roles
- Consider using AWS Secrets Manager for application secrets

## Cost Optimization

### Resource Costs

- **Lambda**: Pay per execution (pipeline events)
- **CodeBuild**: Pay per build minute
- **CodePipeline**: Pay per pipeline execution
- **S3**: Pay for artifact storage
- **EventBridge**: Pay per event processed

### Cost Management Tips

1. **Feature Branch Lifecycle**: Implement automatic cleanup for old feature branches
2. **Build Optimization**: Use smaller CodeBuild instances for simple builds
3. **Artifact Retention**: Set lifecycle policies on S3 artifact bucket
4. **Pipeline Scheduling**: Consider build scheduling during business hours

## Advanced Configuration

### Multi-Environment Deployments

Extend the solution to support multiple environments:

```bash
# Deploy to different environments
cdk deploy --context environment=dev
cdk deploy --context environment=staging
cdk deploy --context environment=prod
```

### Integration with External Tools

- **Slack Notifications**: Add SNS integration for build notifications
- **Jira Integration**: Connect pipeline status to Jira tickets
- **Quality Gates**: Add SonarQube or CodeGuru integration

### Scaling Considerations

- **Concurrent Builds**: CodeBuild supports concurrent execution
- **Pipeline Limits**: AWS has default limits on pipeline count
- **Lambda Concurrency**: Default concurrency handles typical branch operations

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review AWS service documentation
3. Verify IAM permissions and service limits
4. Check CloudWatch logs for detailed error messages

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment first
2. Update documentation for any configuration changes
3. Follow AWS best practices for security and performance
4. Consider backward compatibility with existing deployments

## License

This infrastructure code is provided as-is under the same license terms as the original recipe.