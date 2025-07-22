# Infrastructure as Code for Secure SSH Access with EC2 Instance Connect

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Secure SSH Access with EC2 Instance Connect".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for EC2, IAM, CloudTrail, and S3 operations
- For CDK implementations: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed
- Basic understanding of AWS networking, security groups, and IAM policies

### Required AWS Permissions

Your AWS credentials need the following permissions:
- `ec2:*` (for instances, security groups, subnets, and Instance Connect endpoints)
- `iam:*` (for creating users, roles, and policies)
- `cloudtrail:*` (for audit logging)
- `s3:*` (for CloudTrail log storage)
- `logs:*` (for CloudWatch logs access)

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name ec2-instance-connect-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=dev

# Monitor deployment progress
aws cloudformation describe-stack-events \
    --stack-name ec2-instance-connect-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name ec2-instance-connect-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters environment=dev

# View stack outputs
cdk list
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters environment=dev

# View stack outputs
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
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

# The script will output connection details and testing commands
```

## Post-Deployment Testing

After successful deployment, test the EC2 Instance Connect functionality:

### Test Public Instance Access

```bash
# Get instance ID from stack outputs
export INSTANCE_ID="<your-instance-id>"

# Test direct SSH connection
aws ec2-instance-connect ssh \
    --instance-id "${INSTANCE_ID}" \
    --os-user ec2-user \
    --command "hostname && whoami"
```

### Test Private Instance Access (if deployed)

```bash
# Get private instance ID from stack outputs
export PRIVATE_INSTANCE_ID="<your-private-instance-id>"

# Test connection via Instance Connect Endpoint
aws ec2-instance-connect ssh \
    --instance-id "${PRIVATE_INSTANCE_ID}" \
    --os-user ec2-user \
    --connection-type eice \
    --command "hostname && whoami"
```

### Verify IAM Permissions

```bash
# Test sending SSH public key (demonstrates IAM policy)
ssh-keygen -t rsa -b 2048 -f test-key -N "" -q

aws ec2-instance-connect send-ssh-public-key \
    --instance-id "${INSTANCE_ID}" \
    --instance-os-user ec2-user \
    --ssh-public-key file://test-key.pub

# Clean up test key
rm -f test-key test-key.pub
```

## Customization

### CloudFormation Parameters

Modify `cloudformation.yaml` parameters section or provide values during deployment:

- `Environment`: Environment name (dev, staging, prod)
- `InstanceType`: EC2 instance type (default: t2.micro)
- `AllowedCIDR`: CIDR block allowed for SSH access (default: 0.0.0.0/0)
- `EnablePrivateInstance`: Create private instance and endpoint (default: true)
- `EnableCloudTrail`: Enable CloudTrail logging (default: true)

### CDK Customization

Edit the following files to customize your deployment:

**TypeScript**: `cdk-typescript/lib/ec2-instance-connect-stack.ts`
**Python**: `cdk-python/ec2_instance_connect/stack.py`

Common customizations:
- Instance types and AMI selection
- VPC and subnet configuration
- Security group rules
- IAM policy restrictions
- CloudTrail configuration

### Terraform Variables

Modify `terraform/variables.tf` or create a `terraform.tfvars` file:

```hcl
# terraform.tfvars
environment = "production"
instance_type = "t3.micro"
allowed_cidr = "10.0.0.0/8"
enable_private_instance = true
enable_cloudtrail = true
```

### Bash Script Environment Variables

Before running scripts, set environment variables to customize deployment:

```bash
export ENVIRONMENT="dev"
export INSTANCE_TYPE="t2.micro"
export ALLOWED_CIDR="0.0.0.0/0"
export ENABLE_PRIVATE_INSTANCE="true"
export ENABLE_CLOUDTRAIL="true"
```

## Architecture Overview

The deployed infrastructure includes:

1. **Public EC2 Instance**: Accessible via EC2 Instance Connect
2. **Private EC2 Instance**: Accessible via Instance Connect Endpoint
3. **Security Groups**: Configured for SSH access
4. **IAM Resources**: User, policies, and roles for Instance Connect
5. **Instance Connect Endpoint**: For secure private instance access
6. **CloudTrail**: Audit logging for connection attempts
7. **S3 Bucket**: Storage for CloudTrail logs

## Security Considerations

- **Least Privilege**: IAM policies restrict access to specific OS users
- **Temporary Keys**: SSH keys are valid for only 60 seconds
- **Audit Logging**: All connection attempts logged via CloudTrail
- **Network Isolation**: Private instances accessible only via endpoints
- **Encryption**: All logs and data encrypted at rest and in transit

## Monitoring and Logging

### CloudTrail Events

Monitor EC2 Instance Connect usage:

```bash
# View recent Instance Connect events
aws logs filter-log-events \
    --log-group-name CloudTrail/EC2InstanceConnect \
    --start-time $(date -d '1 hour ago' +%s)000 \
    --filter-pattern "{ $.eventName = SendSSHPublicKey }"
```

### Instance Connect Endpoint Metrics

```bash
# View endpoint connection metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/EC2InstanceConnect \
    --metric-name ActiveConnections \
    --start-time $(date -d '1 hour ago' --iso-8601) \
    --end-time $(date --iso-8601) \
    --period 300 \
    --statistics Average
```

## Troubleshooting

### Common Issues

1. **Connection Timeout**: Verify security group allows SSH (port 22)
2. **Permission Denied**: Check IAM policy and EC2 instance permissions
3. **Key Upload Fails**: Ensure instance has Instance Connect installed
4. **Private Instance Access**: Verify Instance Connect Endpoint status

### Debug Commands

```bash
# Check instance status
aws ec2 describe-instances --instance-ids "${INSTANCE_ID}"

# Verify Instance Connect installation
aws ec2-instance-connect ssh \
    --instance-id "${INSTANCE_ID}" \
    --os-user ec2-user \
    --command "sudo systemctl status ec2-instance-connect"

# Check security group rules
aws ec2 describe-security-groups \
    --group-ids "${SECURITY_GROUP_ID}"
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name ec2-instance-connect-stack

# Monitor deletion progress
aws cloudformation describe-stack-events \
    --stack-name ec2-instance-connect-stack
```

### Using CDK

```bash
# Navigate to appropriate CDK directory
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

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

### Manual Cleanup Verification

After automated cleanup, verify all resources are removed:

```bash
# Check for remaining instances
aws ec2 describe-instances \
    --filters "Name=tag:Environment,Values=<your-environment>" \
    --query 'Reservations[].Instances[?State.Name!=`terminated`]'

# Check for remaining IAM resources
aws iam list-users --query 'Users[?contains(UserName, `ec2-connect`)]'
aws iam list-policies --scope Local \
    --query 'Policies[?contains(PolicyName, `EC2InstanceConnect`)]'
```

## Cost Optimization

- **Instance Types**: Use t2.micro for testing (free tier eligible)
- **Instance Connect Endpoints**: Incur hourly charges (~$0.10/hour)
- **CloudTrail**: Consider data event logging costs for high-volume usage
- **S3 Storage**: Monitor CloudTrail log storage costs

## Support

For issues with this infrastructure code:

1. Review the [original recipe documentation](../ec2-instance-connect-secure-ssh-access.md)
2. Consult [AWS EC2 Instance Connect documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Connect-using-EC2-Instance-Connect.html)
3. Check [AWS CloudFormation documentation](https://docs.aws.amazon.com/cloudformation/)
4. Reference [AWS CDK documentation](https://docs.aws.amazon.com/cdk/)
5. Review [Terraform AWS Provider documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Contributing

When modifying this infrastructure code:

1. Test all changes in a development environment
2. Validate syntax using appropriate tools (cfn-lint, cdk synth, terraform validate)
3. Update documentation to reflect changes
4. Follow AWS security best practices
5. Ensure all resources are properly tagged and documented