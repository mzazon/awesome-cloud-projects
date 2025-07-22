# Infrastructure as Code for Virtual Desktop Infrastructure with WorkSpaces

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Virtual Desktop Infrastructure with WorkSpaces".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a complete virtual desktop infrastructure using AWS WorkSpaces, including:

- VPC with public and private subnets across multiple Availability Zones
- Internet Gateway and NAT Gateway for secure internet access
- AWS Directory Service (Simple AD) for user authentication
- WorkSpaces deployment with encryption and auto-stop configuration
- CloudWatch monitoring and alerting
- IP access control groups for network security

## Prerequisites

### AWS Requirements
- AWS CLI v2 installed and configured
- AWS account with appropriate permissions for:
  - VPC and EC2 resources
  - AWS Directory Service
  - AWS WorkSpaces
  - CloudWatch
  - IAM (for service roles)
- Sufficient service quotas for WorkSpaces in your target region

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI v2.0 or later
- CloudFormation permissions

#### CDK TypeScript
- Node.js 18.x or later
- npm or yarn package manager
- AWS CDK CLI (`npm install -g aws-cdk`)

#### CDK Python
- Python 3.8 or later
- pip package manager
- AWS CDK CLI (`pip install aws-cdk-lib`)

#### Terraform
- Terraform 1.0 or later
- AWS provider 5.0 or later

### Cost Considerations
- Estimated cost: $25-50/month per WorkSpace (varies by bundle type and usage)
- Simple AD is provided free when used with WorkSpaces
- Additional costs for VPC NAT Gateway (~$45/month)
- Data transfer and storage costs may apply

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name workspaces-productivity-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=DirectoryPassword,ParameterValue=YourSecurePassword123! \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name workspaces-productivity-stack \
    --query 'Stacks[0].StackStatus'

# Wait for completion
aws cloudformation wait stack-create-complete \
    --stack-name workspaces-productivity-stack
```

### Using CDK TypeScript
```bash
# Navigate to CDK directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Review changes
cdk diff

# Deploy the stack
cdk deploy

# Verify deployment
cdk list
```

### Using CDK Python
```bash
# Navigate to CDK directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Review changes
cdk diff

# Deploy the stack
cdk deploy

# Verify deployment
cdk list
```

### Using Terraform
```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply

# Verify resources
terraform show
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Monitor deployment (scripts will provide progress updates)
```

## Configuration

### Key Parameters

All implementations support these key configuration options:

- **Region**: AWS region for deployment (default: us-east-1)
- **VPC CIDR**: Network range for the VPC (default: 10.0.0.0/16)
- **Directory Name**: Simple AD directory name
- **Directory Password**: Password for directory admin user (must meet complexity requirements)
- **WorkSpace Bundle**: Bundle type for WorkSpaces (Standard, Performance, etc.)
- **Auto Stop Timeout**: Minutes before WorkSpace auto-stops (default: 60)
- **IP Access Range**: CIDR blocks allowed to access WorkSpaces (default: 0.0.0.0/0)

### CloudFormation Parameters
```yaml
Parameters:
  DirectoryPassword:
    Type: String
    NoEcho: true
    Description: Password for Simple AD directory
  WorkSpaceBundleType:
    Type: String
    Default: Standard
    AllowedValues: [Standard, Performance, Power, PowerPro]
  AutoStopTimeoutMinutes:
    Type: Number
    Default: 60
    MinValue: 60
    MaxValue: 36000
```

### Terraform Variables
```bash
# Create terraform.tfvars file
cat > terraform.tfvars << EOF
region = "us-west-2"
directory_password = "YourSecurePassword123!"
workspace_bundle_type = "Standard"
auto_stop_timeout = 60
allowed_ip_range = "203.0.113.0/24"
EOF
```

### CDK Context
```json
{
  "region": "us-west-2",
  "directoryPassword": "YourSecurePassword123!",
  "workspaceBundleType": "Standard",
  "autoStopTimeout": 60
}
```

## Post-Deployment Steps

### 1. Access WorkSpace
```bash
# Get WorkSpace connection details
aws workspaces describe-workspaces \
    --query 'Workspaces[0].{WorkspaceId:WorkspaceId,State:State,IpAddress:IpAddress}'
```

### 2. User Management
- Users are managed through AWS Directory Service
- Access the WorkSpaces console to create additional users
- Configure user properties and WorkSpace assignments

### 3. Client Installation
- Download WorkSpaces client from AWS website
- Provide users with registration code from WorkSpaces console
- Configure client settings for optimal experience

### 4. Monitoring Setup
```bash
# View CloudWatch metrics
aws cloudwatch list-metrics \
    --namespace AWS/WorkSpaces

# Check connection logs
aws logs describe-log-groups \
    --log-group-name-prefix /aws/workspaces
```

## Validation

### Verify Deployment
```bash
# Check VPC and subnets
aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=workspaces-vpc-*" \
    --query 'Vpcs[0].{VpcId:VpcId,State:State,CidrBlock:CidrBlock}'

# Verify Directory Service
aws ds describe-directories \
    --query 'DirectoryDescriptions[0].{DirectoryId:DirectoryId,Stage:Stage,Type:Type}'

# Check WorkSpace status
aws workspaces describe-workspaces \
    --query 'Workspaces[0].{WorkspaceId:WorkspaceId,State:State,UserName:UserName}'

# Test network connectivity
aws ec2 describe-nat-gateways \
    --query 'NatGateways[0].{NatGatewayId:NatGatewayId,State:State}'
```

### Performance Testing
```bash
# Monitor WorkSpace metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/WorkSpaces \
    --metric-name ConnectionAttempt \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name workspaces-productivity-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name workspaces-productivity-stack

# Verify cleanup
aws cloudformation describe-stacks \
    --stack-name workspaces-productivity-stack 2>/dev/null || echo "Stack deleted successfully"
```

### Using CDK TypeScript/Python
```bash
# Destroy the stack
cdk destroy

# Confirm deletion when prompted
# y

# Verify cleanup
cdk list
```

### Using Terraform
```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm with 'yes' when prompted

# Verify cleanup
terraform show
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts for confirmation
```

## Troubleshooting

### Common Issues

#### WorkSpace Creation Fails
- Verify directory is in "Active" state
- Check VPC subnet configuration
- Ensure sufficient IP addresses in private subnets
- Validate directory registration with WorkSpaces

#### Directory Service Issues
- Verify VPC has DNS resolution enabled
- Check subnet availability across multiple AZs
- Validate security group configurations
- Ensure proper route table configurations

#### Network Connectivity Problems
- Verify Internet Gateway attachment
- Check NAT Gateway status and routing
- Validate security group rules
- Test DNS resolution in VPC

#### User Access Issues
- Verify user exists in directory
- Check IP access control group settings
- Validate WorkSpace bundle compatibility
- Ensure client software is properly configured

### Debug Commands
```bash
# Check CloudFormation events
aws cloudformation describe-stack-events \
    --stack-name workspaces-productivity-stack \
    --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'

# View Terraform state
terraform state list
terraform state show aws_workspaces_workspace.main

# Check CDK output
cdk diff
cdk doctor
```

## Security Considerations

### Network Security
- WorkSpaces deployed in private subnets
- Internet access through NAT Gateway only
- IP access control groups restrict WorkSpace access
- VPC security groups control network traffic

### Encryption
- WorkSpace root and user volumes encrypted at rest
- Directory Service data encrypted
- Network traffic encrypted in transit

### Access Control
- Directory-based user authentication
- IAM roles with least privilege access
- CloudWatch monitoring for access patterns
- Optional integration with AWS SSO

### Best Practices
- Regularly update WorkSpace images
- Monitor and audit user access
- Implement strong password policies
- Use MFA where possible
- Regular security assessments

## Customization

### Scaling Options
- Modify Terraform/CloudFormation to deploy multiple WorkSpaces
- Add auto-scaling based on demand patterns
- Implement user provisioning automation
- Configure different bundle types for user groups

### Integration Examples
- Connect to existing Active Directory
- Integrate with SAML identity providers
- Add custom applications to WorkSpace images
- Implement cost optimization automation

### Monitoring Enhancements
- Custom CloudWatch dashboards
- SNS notifications for WorkSpace events
- Integration with third-party monitoring tools
- Automated performance optimization

## Support

### Documentation Links
- [AWS WorkSpaces User Guide](https://docs.aws.amazon.com/workspaces/latest/userguide/)
- [AWS Directory Service Admin Guide](https://docs.aws.amazon.com/directoryservice/latest/admin-guide/)
- [VPC User Guide](https://docs.aws.amazon.com/vpc/latest/userguide/)

### Getting Help
- For infrastructure issues: Check CloudWatch logs and AWS documentation
- For deployment problems: Review the original recipe documentation
- For provider-specific questions: Consult AWS support or community forums

### Contributing
- Report issues with infrastructure code
- Suggest improvements for automation
- Share customization examples
- Contribute monitoring and optimization scripts

## Version Information

- **Recipe Version**: 1.1
- **Infrastructure Code Generated**: 2025-07-12
- **CDK Version**: Latest stable (>= 2.90.0)
- **Terraform AWS Provider**: >= 5.0
- **CloudFormation Template Format**: 2010-09-09

---

*This infrastructure code implements the complete solution described in the "Virtual Desktop Infrastructure with WorkSpaces" recipe. For detailed implementation steps and architectural explanations, refer to the original recipe documentation.*