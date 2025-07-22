# Infrastructure as Code for Cloud Development Workflows with CloudShell

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cloud Development Workflows with CloudShell".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured
- Appropriate AWS permissions for:
  - AWS CloudShell access (`AWSCloudShellFullAccess`)
  - AWS CodeCommit management (`AWSCodeCommitFullAccess`)
  - IAM role and policy management
- For CDK implementations: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+

> **Important**: AWS CodeCommit is no longer available to new customers as of July 2024. Existing customers can continue using the service. Consider alternatives like GitHub, GitLab, or AWS CodeStar Connections for new implementations.

## Quick Start

### Using CloudFormation

```bash
# Create the stack
aws cloudformation create-stack \
    --stack-name cloud-dev-workflow-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=RepositoryName,ParameterValue=my-dev-repo \
    --capabilities CAPABILITY_IAM

# Wait for completion
aws cloudformation wait stack-create-complete \
    --stack-name cloud-dev-workflow-stack

# Get outputs
aws cloudformation describe-stacks \
    --stack-name cloud-dev-workflow-stack \
    --query 'Stacks[0].Outputs'
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
cdk ls --long
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls --long
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

# Follow the script prompts for configuration
```

## What Gets Deployed

This infrastructure code deploys the following AWS resources:

1. **CodeCommit Repository**
   - Git repository for source code management
   - Configured with appropriate IAM permissions
   - Optional: Repository triggers for automation

2. **IAM Roles and Policies**
   - CloudShell execution role with CodeCommit access
   - Developer group with appropriate permissions
   - Git credential helper configuration

3. **CloudShell Environment Access**
   - Pre-configured access to CloudShell
   - Environment variables and Git configuration
   - Persistent storage configuration

4. **Optional Components** (depending on implementation)
   - CloudWatch logging for repository access
   - SNS topics for repository notifications
   - Lambda functions for automation

## Configuration Options

### CloudFormation Parameters

- `RepositoryName`: Name for the CodeCommit repository
- `RepositoryDescription`: Description for the repository
- `EnableCloudWatch`: Enable CloudWatch logging (true/false)
- `EnableNotifications`: Enable SNS notifications (true/false)

### CDK Configuration

Modify the stack configuration in `app.ts` (TypeScript) or `app.py` (Python):

```typescript
// CDK TypeScript example
const config = {
  repositoryName: 'my-dev-workflow-repo',
  enableLogging: true,
  enableNotifications: false,
  tags: {
    Environment: 'development',
    Project: 'cloud-dev-workflow'
  }
};
```

### Terraform Variables

Configure in `terraform.tfvars`:

```hcl
repository_name        = "my-dev-workflow-repo"
repository_description = "Development workflow repository"
enable_cloudwatch     = true
enable_notifications  = false

tags = {
  Environment = "development"
  Project     = "cloud-dev-workflow"
}
```

## Accessing Your Environment

After deployment, access your cloud development environment:

1. **Open AWS CloudShell**:
   - Navigate to AWS Management Console
   - Click the CloudShell icon in the top navigation
   - Wait for environment initialization

2. **Clone Your Repository**:
   ```bash
   # Get repository URL from outputs
   REPO_URL=$(aws cloudformation describe-stacks \
       --stack-name cloud-dev-workflow-stack \
       --query 'Stacks[0].Outputs[?OutputKey==`RepositoryCloneUrl`].OutputValue' \
       --output text)
   
   # Clone repository
   git clone $REPO_URL
   ```

3. **Start Developing**:
   ```bash
   cd your-repository-name
   
   # Configure Git (if not already done)
   git config --global user.name "Your Name"
   git config --global user.email "your.email@example.com"
   
   # Start coding!
   ```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name cloud-dev-workflow-stack

# Wait for completion
aws cloudformation wait stack-delete-complete \
    --stack-name cloud-dev-workflow-stack
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Security Considerations

This infrastructure implements several security best practices:

- **IAM Least Privilege**: Roles and policies grant minimal required permissions
- **Encryption**: CodeCommit repositories use encryption at rest
- **Access Logging**: Optional CloudWatch logging for audit trails
- **Secure Authentication**: Uses IAM credentials instead of Git credentials

## Troubleshooting

### Common Issues

1. **CloudShell Access Denied**:
   - Verify your IAM user has `AWSCloudShellFullAccess` policy
   - Check that CloudShell is available in your region

2. **CodeCommit Authentication Failed**:
   - Ensure Git credential helper is configured
   - Verify IAM permissions for CodeCommit operations

3. **Repository Not Found**:
   - Check that the repository was created successfully
   - Verify you're using the correct region

### Debug Commands

```bash
# Check CloudShell environment
aws sts get-caller-identity

# Verify Git configuration
git config --list

# Test CodeCommit access
aws codecommit list-repositories

# Check repository details
aws codecommit get-repository --repository-name YOUR_REPO_NAME
```

## Customization

### Adding CI/CD Pipeline

Extend the infrastructure to include:
- AWS CodePipeline for automated builds
- AWS CodeBuild for testing and compilation
- Integration with other AWS services

### Enhanced Security

Consider adding:
- AWS Config rules for compliance monitoring
- AWS CloudTrail for comprehensive audit logging
- Amazon GuardDuty for threat detection

### Team Collaboration

Enhance for team use:
- IAM groups for different developer roles
- Branch protection rules
- Automated code review workflows

## Cost Optimization

- **CloudShell**: Free tier includes 10 hours per month
- **CodeCommit**: Free tier includes 5 active users per month
- **Storage**: Additional charges apply for persistent storage beyond free tier limits

Monitor usage with AWS Cost Explorer and set up billing alerts to track expenses.

## Support

For issues with this infrastructure code:

1. Refer to the original recipe documentation
2. Check AWS CloudShell documentation: https://docs.aws.amazon.com/cloudshell/
3. Review CodeCommit documentation: https://docs.aws.amazon.com/codecommit/
4. Consult AWS support resources or community forums

## Next Steps

After deploying this infrastructure:

1. Set up your first development project
2. Configure team access and permissions
3. Implement CI/CD pipelines for automated testing
4. Explore advanced CloudShell features and customizations
5. Consider migration strategies if moving away from CodeCommit