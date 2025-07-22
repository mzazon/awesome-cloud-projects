# Infrastructure as Code for Secure EC2 Management with Systems Manager

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Secure EC2 Management with Systems Manager".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured with appropriate credentials
- Appropriate AWS permissions for creating/managing:
  - EC2 instances and security groups
  - IAM roles and instance profiles
  - Systems Manager resources
  - CloudWatch Logs
- For CDK implementations: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform CLI 1.0+ installed
- Estimated cost: <$5.00 for a 1-day test (t2.micro EC2 instance + Systems Manager)

## Quick Start

### Using CloudFormation (AWS)
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name ec2-ssm-secure-management \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=EnvironmentName,ParameterValue=test

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name ec2-ssm-secure-management

# Get outputs
aws cloudformation describe-stacks \
    --stack-name ec2-ssm-secure-management \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Deploy the stack
cdk deploy EC2SSMSecureManagementStack

# Get outputs
cdk list
```

### Using CDK Python (AWS)
```bash
cd cdk-python/

# Create virtual environment and install dependencies
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt

# Deploy the stack
cdk deploy EC2SSMSecureManagementStack

# Get outputs
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
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will prompt for deployment parameters and show progress
```

## Post-Deployment Usage

After successful deployment, you can manage your EC2 instance securely using AWS Systems Manager:

### Connect via Session Manager
```bash
# Get instance ID from deployment outputs
INSTANCE_ID=$(aws cloudformation describe-stacks \
    --stack-name ec2-ssm-secure-management \
    --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' \
    --output text)

# Start secure session (requires Session Manager plugin)
aws ssm start-session --target $INSTANCE_ID
```

### Execute Commands via Run Command
```bash
# Run a simple command
aws ssm send-command \
    --document-name "AWS-RunShellScript" \
    --targets "Key=InstanceIds,Values=$INSTANCE_ID" \
    --parameters 'commands=["echo Hello from Systems Manager", "hostname", "df -h"]'
```

### View Session Logs
```bash
# Get log group name from outputs
LOG_GROUP=$(aws cloudformation describe-stacks \
    --stack-name ec2-ssm-secure-management \
    --query 'Stacks[0].Outputs[?OutputKey==`SessionLogGroup`].OutputValue' \
    --output text)

# View recent log streams
aws logs describe-log-streams \
    --log-group-name $LOG_GROUP \
    --order-by LastEventTime \
    --descending
```

## Architecture Overview

This implementation creates:

- **EC2 Instance**: A secure server with Systems Manager agent pre-installed
- **IAM Role**: Service role with minimum permissions for Systems Manager operations
- **Security Group**: Restrictive security group blocking all inbound traffic (no SSH/RDP ports)
- **CloudWatch Log Group**: Centralized logging for all session activity
- **Systems Manager Configuration**: Session Manager preferences for logging and encryption

Key security features:
- No inbound SSH/RDP ports required
- IAM-based access control
- Comprehensive session logging
- Encrypted communication channels

## Customization

### Common Variables/Parameters

All implementations support customization through variables:

- **Environment Name**: Prefix for resource naming (default: "ssm-secure")
- **Instance Type**: EC2 instance size (default: "t2.micro")
- **AMI Type**: Operating system choice ("amazon-linux" or "ubuntu")
- **Enable Session Logging**: Whether to log sessions to CloudWatch (default: true)
- **VPC Configuration**: Use default VPC or specify custom VPC/subnet

### CloudFormation Parameters
Edit the parameters section in `cloudformation.yaml` or provide values during deployment:

```yaml
Parameters:
  EnvironmentName:
    Type: String
    Default: ssm-secure
  InstanceType:
    Type: String
    Default: t2.micro
    AllowedValues: [t2.micro, t2.small, t2.medium]
```

### CDK Configuration
Modify the configuration in the CDK app files:

```typescript
// CDK TypeScript example
const props = {
  environmentName: 'ssm-secure',
  instanceType: ec2.InstanceType.of(ec2.InstanceClass.T2, ec2.InstanceSize.MICRO),
  enableSessionLogging: true
};
```

### Terraform Variables
Modify `terraform/variables.tf` or create a `terraform.tfvars` file:

```hcl
environment_name = "ssm-secure"
instance_type    = "t2.micro"
ami_type         = "amazon-linux"
enable_logging   = true
```

## Cleanup

### Using CloudFormation (AWS)
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name ec2-ssm-secure-management

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name ec2-ssm-secure-management
```

### Using CDK (AWS)
```bash
# Destroy the stack
cdk destroy EC2SSMSecureManagementStack

# Confirm when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Security Considerations

This implementation follows AWS security best practices:

- **Least Privilege**: IAM role includes only minimum required permissions
- **No Inbound Access**: Security group blocks all inbound traffic
- **Encryption in Transit**: All Systems Manager communication is encrypted
- **Audit Logging**: All session activity is logged for compliance
- **No Hardcoded Credentials**: Uses IAM roles instead of access keys

## Troubleshooting

### Instance Not Appearing in Systems Manager
- Verify the IAM role has the `AmazonSSMManagedInstanceCore` policy
- Check that the instance has outbound internet connectivity
- Ensure the SSM agent is running (pre-installed on Amazon Linux and Ubuntu AMIs)

### Session Manager Connection Fails
- Install the Session Manager plugin for AWS CLI
- Verify you have the necessary IAM permissions for Session Manager
- Check that the instance is in "Online" status in Systems Manager

### Command Execution Fails
- Verify the target instance is online and responsive
- Check command syntax and ensure it's compatible with the OS
- Review CloudWatch Logs for detailed error messages

## Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult the [AWS Systems Manager documentation](https://docs.aws.amazon.com/systems-manager/)
4. Review AWS CloudFormation/CDK/Terraform provider documentation

## Cost Optimization

To minimize costs during testing:
- Use `t2.micro` instances (eligible for AWS Free Tier)
- Set CloudWatch Logs retention to 7 days for testing
- Terminate resources promptly after testing
- Consider using Spot instances for non-production workloads (modify the templates accordingly)

## Additional Resources

- [AWS Systems Manager User Guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/)
- [Session Manager Best Practices](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-best-practices.html)
- [Systems Manager Pricing](https://aws.amazon.com/systems-manager/pricing/)
- [IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)