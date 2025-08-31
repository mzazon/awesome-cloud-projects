# Infrastructure as Code for AI Code Assistant Setup with Amazon Q Developer

This directory contains Infrastructure as Code (IaC) implementations for the recipe "AI Code Assistant Setup with Amazon Q Developer".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- Visual Studio Code 1.85.0 or higher installed
- Active internet connection for extension installation
- IAM permissions for creating and managing IAM roles and policies (if deploying infrastructure components)
- Node.js 18+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform deployment)

> **Note**: This recipe primarily involves setting up a development environment rather than deploying AWS infrastructure. The IaC implementations focus on automating the VS Code extension installation and configuration process.

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the CloudFormation stack
aws cloudformation create-stack \
    --stack-name amazon-q-developer-setup \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=VSCodeVersion,ParameterValue=latest

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name amazon-q-developer-setup

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name amazon-q-developer-setup \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this account/region)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy AmazonQDeveloperSetupStack

# View stack outputs
npx cdk list
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv

# Activate virtual environment
source .venv/bin/activate  # Linux/macOS
# .venv\Scripts\activate.bat  # Windows

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the stack
cdk deploy AmazonQDeveloperSetupStack

# View stack outputs
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
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

# Run deployment script
./scripts/deploy.sh

# Follow interactive prompts for configuration
```

## Configuration Options

### Environment Variables

Set these environment variables before deployment:

```bash
# Required
export AWS_REGION="us-east-1"
export VSCODE_EXTENSION_ID="AmazonWebServices.amazon-q-vscode"

# Optional customization
export STACK_NAME="amazon-q-developer-setup"
export VSCODE_VERSION="latest"
export ENABLE_AUTO_UPDATE="true"
```

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| VSCodeVersion | VS Code version requirement | latest | No |
| ExtensionId | Amazon Q extension identifier | AmazonWebServices.amazon-q-vscode | No |
| EnableAutoUpdate | Enable automatic extension updates | true | No |

### Terraform Variables

```hcl
# terraform.tfvars example
aws_region = "us-east-1"
vscode_extension_id = "AmazonWebServices.amazon-q-vscode"
stack_name = "amazon-q-developer-setup"
enable_auto_update = true
```

## Deployment Architecture

The IaC implementations create the following components:

1. **Setup Automation Resources**:
   - Lambda function for VS Code extension management
   - IAM roles and policies for automation
   - CloudWatch logs for monitoring

2. **Configuration Management**:
   - Systems Manager parameters for extension settings
   - S3 bucket for storing configuration templates
   - EventBridge rules for automated updates

3. **Monitoring and Logging**:
   - CloudWatch dashboard for setup metrics
   - SNS notifications for deployment status
   - CloudTrail logging for audit compliance

## Post-Deployment Steps

After successful infrastructure deployment:

1. **Install VS Code Extension**:
   ```bash
   # Extension installation will be automated by the deployment
   # Verify installation manually if needed
   code --list-extensions | grep amazon-q-vscode
   ```

2. **Configure Authentication**:
   ```bash
   # Launch VS Code and complete authentication
   code
   # Follow the Amazon Q authentication prompts
   ```

3. **Verify Setup**:
   ```bash
   # Test extension functionality
   # Create a new file and test AI suggestions
   # Use Amazon Q chat interface
   ```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name amazon-q-developer-setup

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name amazon-q-developer-setup

# Verify stack deletion
aws cloudformation list-stacks \
    --stack-status-filter DELETE_COMPLETE
```

### Using CDK (AWS)

```bash
# Destroy the CDK stack
cdk destroy AmazonQDeveloperSetupStack

# Confirm destruction when prompted
# Clean up CDK bootstrap (optional, only if no other CDK stacks)
# cdk bootstrap --force
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
# Clean up state files (optional)
rm -f terraform.tfstate terraform.tfstate.backup
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow interactive prompts for confirmation
# Script will remove VS Code extension and clean up configuration
```

## Troubleshooting

### Common Issues

1. **Extension Installation Fails**:
   ```bash
   # Manually install extension
   code --install-extension AmazonWebServices.amazon-q-vscode
   
   # Check VS Code version compatibility
   code --version
   ```

2. **Authentication Problems**:
   ```bash
   # Clear VS Code settings and retry
   rm -rf ~/.vscode/extensions/amazonwebservices.amazon-q-vscode*
   code --install-extension AmazonWebServices.amazon-q-vscode
   ```

3. **AWS Permissions Issues**:
   ```bash
   # Verify AWS CLI configuration
   aws sts get-caller-identity
   
   # Check required IAM permissions
   aws iam simulate-principal-policy \
       --policy-source-arn $(aws sts get-caller-identity --query Arn --output text) \
       --action-names iam:CreateRole lambda:CreateFunction
   ```

### Logs and Monitoring

```bash
# View CloudWatch logs for deployment
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/amazon-q-setup"

# Check deployment metrics
aws cloudwatch get-metric-statistics \
    --namespace "AmazonQ/Setup" \
    --metric-name "DeploymentSuccess" \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 3600 \
    --statistics Sum
```

## Customization

### Adding Custom Extensions

Modify the extension list in your preferred IaC implementation:

```yaml
# CloudFormation example
Extensions:
  - AmazonWebServices.amazon-q-vscode
  - AmazonWebServices.aws-toolkit-vscode
  - ms-python.python
```

### Custom VS Code Settings

Update the configuration templates to include custom settings:

```json
{
  "amazonQ.enableInlineCompletion": true,
  "amazonQ.enableCodeWhisperer": true,
  "amazonQ.logLevel": "info"
}
```

### Environment-Specific Configurations

Use parameter overrides for different environments:

```bash
# Development environment
terraform apply -var="environment=dev" -var="log_level=debug"

# Production environment
terraform apply -var="environment=prod" -var="log_level=warn"
```

## Security Considerations

- **IAM Permissions**: All implementations follow least privilege principles
- **Data Privacy**: No sensitive data is stored in infrastructure code
- **Network Security**: Extension downloads use HTTPS connections
- **Audit Logging**: All deployment actions are logged to CloudTrail
- **Access Control**: Resource access is restricted to deployment roles

## Cost Estimation

The infrastructure components have minimal cost impact:

- **Lambda Functions**: $0.01-$0.05/month (minimal execution)
- **CloudWatch Logs**: $0.50-$2.00/month (depending on usage)
- **S3 Storage**: $0.01-$0.10/month (configuration files)
- **Systems Manager**: No additional charges
- **EventBridge**: $1.00/month (rule execution)

**Total Estimated Monthly Cost**: $2-$5 USD

> **Note**: Amazon Q Developer itself has separate pricing. The free tier includes generous usage limits through AWS Builder ID.

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown file
2. **AWS Documentation**: [Amazon Q Developer documentation](https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/)
3. **VS Code Extension**: [Amazon Q Developer in VS Code](https://marketplace.visualstudio.com/items?itemName=AmazonWebServices.amazon-q-vscode)
4. **Community Support**: [AWS Developer Forums](https://forums.aws.amazon.com/)

## Version History

- **v1.0**: Initial IaC implementation
- **v1.1**: Added Terraform and enhanced bash scripts
- **v1.2**: Improved error handling and monitoring
- **v1.3**: Added cost optimization and security enhancements