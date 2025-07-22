# Infrastructure as Code for GitOps with CodeCommit and CodeBuild

This directory contains Infrastructure as Code (IaC) implementations for the recipe "GitOps with CodeCommit and CodeBuild".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This infrastructure deploys a complete GitOps workflow solution including:

- **AWS CodeCommit**: Git repository for source control and GitOps configuration
- **AWS CodeBuild**: Automated build service for CI/CD pipeline
- **AWS CodePipeline**: Orchestration service for complete GitOps automation
- **Amazon ECR**: Container registry for storing application images
- **Amazon ECS**: Container orchestration service with Fargate
- **IAM Roles**: Service roles with least privilege permissions
- **CloudWatch Logs**: Centralized logging for containers and build processes

## Prerequisites

- AWS CLI v2 installed and configured
- Docker installed for local development (optional)
- Git client installed
- Appropriate AWS permissions for:
  - CodeCommit, CodeBuild, CodePipeline
  - ECR, ECS, Fargate
  - IAM role creation
  - CloudWatch Logs
- Node.js 18+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the complete GitOps infrastructure
aws cloudformation create-stack \
    --stack-name gitops-workflow-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=my-gitops-project

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name gitops-workflow-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript (AWS)

```bash
# Install dependencies and deploy
cd cdk-typescript/
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the GitOps infrastructure
cdk deploy --require-approval never

# View outputs
cdk ls
```

### Using CDK Python (AWS)

```bash
# Set up Python environment and deploy
cd cdk-python/
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the GitOps infrastructure
cdk deploy --require-approval never
```

### Using Terraform

```bash
# Initialize and deploy
cd terraform/
terraform init

# Review planned changes
terraform plan

# Deploy infrastructure
terraform apply -auto-approve

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy GitOps infrastructure
./scripts/deploy.sh

# Follow prompts for configuration
```

## Post-Deployment Setup

After deploying the infrastructure, complete the GitOps setup:

1. **Clone the CodeCommit Repository**:
   ```bash
   # Get repository URL from outputs
   REPO_URL=$(aws cloudformation describe-stacks \
       --stack-name gitops-workflow-stack \
       --query 'Stacks[0].Outputs[?OutputKey==`RepositoryCloneUrl`].OutputValue' \
       --output text)
   
   # Clone repository
   git clone $REPO_URL
   cd gitops-demo-*
   ```

2. **Add Sample Application**:
   ```bash
   # Create application structure
   mkdir -p app config/buildspecs infrastructure
   
   # Add sample Node.js application (see recipe for complete files)
   # Add buildspec.yml for CodeBuild
   # Add ECS task definition
   
   # Commit and push
   git add .
   git commit -m "Initial GitOps configuration"
   git push origin main
   ```

3. **Trigger First Build**:
   ```bash
   # Manual build trigger (optional - automatic on push)
   aws codebuild start-build --project-name <build-project-name>
   ```

## Configuration

### Environment Variables

The following environment variables can be set to customize the deployment:

- `AWS_REGION`: AWS region for deployment (default: us-east-1)
- `PROJECT_NAME`: Base name for all resources (default: gitops-demo)
- `CONTAINER_CPU`: CPU units for ECS tasks (default: 256)
- `CONTAINER_MEMORY`: Memory for ECS tasks (default: 512)
- `BUILD_COMPUTE_TYPE`: CodeBuild compute type (default: BUILD_GENERAL1_SMALL)

### Terraform Variables

Key variables in `terraform/variables.tf`:

```hcl
variable "project_name" {
  description = "Base name for all resources"
  type        = string
  default     = "gitops-demo"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "container_cpu" {
  description = "CPU units for ECS tasks"
  type        = number
  default     = 256
}
```

### CDK Configuration

Both CDK implementations support customization through:

- **Context variables**: Set in `cdk.json`
- **Environment variables**: AWS_REGION, CDK_DEFAULT_ACCOUNT
- **Constructor parameters**: Modify in `app.ts` or `app.py`

## Security Considerations

The infrastructure implements security best practices:

- **IAM Roles**: Least privilege access for CodeBuild and CodePipeline
- **VPC Configuration**: ECS tasks run in private subnets with NAT Gateway
- **Encryption**: ECR repositories use encryption at rest
- **Network Security**: Security groups restrict traffic to necessary ports
- **Secrets Management**: No hardcoded credentials in code

## Monitoring and Logging

The solution includes comprehensive monitoring:

- **CloudWatch Logs**: Centralized logging for all services
- **Build Metrics**: CodeBuild provides build success/failure metrics
- **Container Insights**: ECS container performance monitoring
- **Pipeline Metrics**: CodePipeline execution tracking

## Troubleshooting

### Common Issues

1. **Build Failures**:
   ```bash
   # Check build logs
   aws logs get-log-events \
       --log-group-name /aws/codebuild/gitops-build-project \
       --log-stream-name <stream-name>
   ```

2. **ECS Task Failures**:
   ```bash
   # Check ECS service events
   aws ecs describe-services \
       --cluster gitops-cluster \
       --services gitops-service
   ```

3. **Permission Issues**:
   ```bash
   # Verify IAM role permissions
   aws iam get-role --role-name CodeBuildGitOpsRole
   ```

### Debugging Steps

1. Check CloudFormation stack events for deployment issues
2. Verify IAM permissions for service roles
3. Confirm ECR repository accessibility
4. Check VPC and security group configurations
5. Review CloudWatch logs for runtime errors

## Cost Optimization

To optimize costs:

- Use **Fargate Spot** for non-production workloads
- Implement **ECR lifecycle policies** to remove old images
- Use **CodeBuild reserved capacity** for frequent builds
- Enable **ECS Service Auto Scaling** to match demand
- Set up **CloudWatch alarms** for cost monitoring

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack (removes all resources)
aws cloudformation delete-stack --stack-name gitops-workflow-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name gitops-workflow-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK (AWS)

```bash
# Destroy infrastructure
cd cdk-typescript/  # or cdk-python/
cdk destroy --force
```

### Using Terraform

```bash
# Destroy infrastructure
cd terraform/
terraform destroy -auto-approve
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

### Manual Cleanup (if needed)

If automated cleanup fails, manually delete resources in this order:

1. ECS Services and Tasks
2. CodePipeline pipelines
3. CodeBuild projects
4. ECR repositories (delete images first)
5. CloudWatch log groups
6. IAM roles and policies
7. CodeCommit repositories

## Customization

### Adding New Environments

To add staging/production environments:

1. **Modify Infrastructure**:
   - Add environment-specific parameters
   - Create separate ECS clusters per environment
   - Configure environment-specific CodeBuild projects

2. **Update GitOps Workflow**:
   - Create environment-specific branches
   - Add approval gates for production deployments
   - Configure environment-specific secrets

### Extending the Pipeline

Common extensions:

- **Security Scanning**: Add container vulnerability scanning
- **Testing Stages**: Include unit and integration tests
- **Blue-Green Deployment**: Implement zero-downtime deployments
- **Multi-Region**: Deploy across multiple AWS regions
- **Notifications**: Add SNS notifications for pipeline events

## Integration with Existing Infrastructure

To integrate with existing AWS infrastructure:

1. **VPC Integration**: Modify security groups and subnets
2. **Load Balancer**: Connect ECS service to existing ALB
3. **DNS**: Add Route 53 records for service discovery
4. **Monitoring**: Integrate with existing CloudWatch dashboards
5. **Secrets**: Use existing Parameter Store or Secrets Manager

## Best Practices

1. **Repository Structure**: Maintain clear separation between app code and infrastructure
2. **Branch Strategy**: Use feature branches with pull request workflows
3. **Secrets Management**: Never commit secrets to the repository
4. **Resource Tagging**: Tag all resources for cost tracking and management
5. **Monitoring**: Set up alerts for build failures and deployment issues
6. **Documentation**: Keep deployment procedures and architecture diagrams current

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation for implementation details
2. Review AWS service documentation for specific service configurations
3. Consult AWS CloudFormation/CDK/Terraform documentation for syntax issues
4. Check AWS service limits and quotas for deployment failures

## Version History

- **v1.0**: Initial GitOps workflow implementation
- **v1.1**: Added multi-environment support and security enhancements

For the latest updates, refer to the original recipe documentation.