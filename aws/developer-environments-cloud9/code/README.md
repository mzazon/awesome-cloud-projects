# Infrastructure as Code for Developer Environments with Cloud9

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Developer Environments with Cloud9".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for Cloud9, EC2, IAM, VPC, CodeCommit, and CloudWatch
- For CDK implementations: Node.js 18+ (TypeScript) or Python 3.9+ (Python)
- For Terraform: Terraform v1.0+ installed

> **Warning**: AWS Cloud9 is no longer available to new customers. Existing customers can continue using the service. This infrastructure code is provided for educational purposes and for teams already using Cloud9.

## Quick Start

### Using CloudFormation
```bash
# Create the stack
aws cloudformation create-stack \
    --stack-name cloud9-dev-environment \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=EnvironmentName,ParameterValue=my-dev-env \
                 ParameterKey=InstanceType,ParameterValue=t3.medium \
    --capabilities CAPABILITY_IAM

# Monitor stack creation
aws cloudformation describe-stacks \
    --stack-name cloud9-dev-environment \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# Optional: View the synthesized CloudFormation template
cdk synth
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# Optional: View the synthesized CloudFormation template
cdk synth
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# Optional: View current state
terraform show
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
echo "Environment ID: $ENVIRONMENT_ID"
```

## Configuration Options

### Environment Variables
Set these environment variables before deployment:

```bash
export AWS_REGION=us-east-1                    # Target AWS region
export CLOUD9_ENV_NAME=dev-environment        # Environment name
export INSTANCE_TYPE=t3.medium                # EC2 instance type
export AUTO_STOP_MINUTES=60                   # Auto-hibernation timeout
```

### CloudFormation Parameters
- `EnvironmentName`: Name for the Cloud9 environment
- `InstanceType`: EC2 instance type (t3.small, t3.medium, t3.large)
- `AutoStopTimeMinutes`: Minutes before auto-hibernation (default: 60)
- `SubnetId`: VPC subnet ID (optional, uses default if not specified)

### CDK Context Values
Configure in `cdk.json`:
```json
{
  "context": {
    "environmentName": "dev-environment",
    "instanceType": "t3.medium",
    "autoStopTimeMinutes": 60
  }
}
```

### Terraform Variables
Configure in `terraform.tfvars`:
```hcl
environment_name      = "dev-environment"
instance_type        = "t3.medium"
auto_stop_minutes    = 60
repository_name      = "team-development-repo"
```

## Post-Deployment Setup

After deploying the infrastructure, complete the setup by running these commands in your Cloud9 environment:

1. **Access the Cloud9 IDE**: Navigate to the AWS Console > Cloud9 > Your Environment
2. **Run the setup script**:
   ```bash
   # The setup script will be available in your environment
   chmod +x cloud9-setup.sh
   ./cloud9-setup.sh
   ```
3. **Configure environment variables**:
   ```bash
   source environment-config.sh
   echo 'source ~/environment-config.sh' >> ~/.bashrc
   ```
4. **Clone the CodeCommit repository**:
   ```bash
   git clone $REPO_URL ~/projects/team-repo
   ```

## Environment Management

### Adding Team Members
```bash
# Add a team member to the environment
aws cloud9 create-environment-membership \
    --environment-id $ENVIRONMENT_ID \
    --user-arn arn:aws:iam::ACCOUNT-ID:user/USERNAME \
    --permissions read-write
```

### Monitoring Environment Usage
```bash
# View CloudWatch dashboard
aws cloudwatch get-dashboard \
    --dashboard-name Cloud9-Environment-Dashboard

# Check environment status
aws cloud9 describe-environment-status \
    --environment-id $ENVIRONMENT_ID
```

### Managing Environment Hibernation
```bash
# Update auto-stop settings
aws cloud9 update-environment \
    --environment-id $ENVIRONMENT_ID \
    --automatic-stop-time-minutes 120
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name cloud9-dev-environment

# Monitor deletion
aws cloudformation describe-stacks \
    --stack-name cloud9-dev-environment \
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
source .venv/bin/activate
cdk destroy
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **Environment Creation Fails**:
   - Verify IAM permissions for Cloud9, EC2, and VPC
   - Check subnet availability in the specified region
   - Ensure account limits allow new EC2 instances

2. **CodeCommit Access Issues**:
   - Verify IAM permissions for CodeCommit
   - Configure Git credentials for HTTPS or SSH
   - Check repository name uniqueness

3. **Cost Concerns**:
   - Monitor EC2 instance usage in CloudWatch
   - Adjust auto-stop timeout to minimize costs
   - Consider smaller instance types for development

### Verification Commands

```bash
# Check environment status
aws cloud9 describe-environments \
    --environment-ids $ENVIRONMENT_ID

# Verify CodeCommit repository
aws codecommit get-repository \
    --repository-name $REPO_NAME

# Check IAM role attachment
aws iam list-attached-role-policies \
    --role-name $IAM_ROLE_NAME
```

## Cost Optimization

### Instance Sizing Recommendations
- **t3.small**: Light development work, cost-effective ($15-25/month)
- **t3.medium**: Balanced performance and cost ($30-50/month)
- **t3.large**: Resource-intensive development ($60-100/month)

### Cost Management Tips
- Set auto-hibernation to 30-60 minutes for active development
- Use CloudWatch billing alerts to monitor usage
- Consider using spot instances for non-critical development work
- Regularly review and clean up unused environments

## Security Considerations

- All IAM roles follow least-privilege principle
- Environment access is controlled through IAM users and roles
- CodeCommit repositories use IAM authentication
- EC2 instances use AWS Systems Manager for secure shell access
- CloudWatch monitoring tracks environment usage and access patterns

## Integration Options

### CI/CD Integration
Connect your Cloud9 environment to AWS CodePipeline:
```bash
# Example: Create a basic pipeline
aws codepipeline create-pipeline \
    --pipeline file://pipeline-config.json
```

### Additional AWS Services
Consider integrating with:
- **AWS CodeCommit**: Git repositories with IAM integration
- **AWS CodeBuild**: Automated build and test environments
- **AWS Lambda**: Serverless function development and testing
- **Amazon S3**: Asset storage and static website hosting

## Support

For issues with this infrastructure code:
1. Check AWS service health in the AWS Console
2. Review CloudFormation/CDK events for deployment issues
3. Consult the original recipe documentation
4. Reference AWS Cloud9 documentation for service-specific guidance

## Alternative Solutions

Since AWS Cloud9 is no longer available to new customers, consider these alternatives:
- **GitHub Codespaces**: Browser-based development environments
- **AWS CodeWhisperer**: AI-powered coding assistant for local IDEs
- **Docker + AWS CodeBuild**: Container-based development environments
- **VS Code Remote Development**: Remote development over SSH to EC2 instances