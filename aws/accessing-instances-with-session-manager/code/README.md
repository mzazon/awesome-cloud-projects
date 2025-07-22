# Infrastructure as Code for Accessing Instances with Session Manager

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Accessing Instances with Session Manager".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements secure remote access to EC2 instances using AWS Systems Manager Session Manager, eliminating the need for SSH keys, bastion hosts, or open inbound ports. The infrastructure includes:

- IAM role and instance profile for EC2 instances
- EC2 instance configured with Session Manager
- S3 bucket for session log storage
- CloudWatch log group for real-time session monitoring
- IAM policies for user access control
- Session Manager logging configuration

## Prerequisites

- AWS CLI installed and configured (version 2.0 or later)
- Appropriate AWS permissions for resource creation:
  - EC2: CreateInstance, TerminateInstance, DescribeInstances
  - IAM: CreateRole, CreatePolicy, AttachRolePolicy
  - Systems Manager: PutPreference, DescribeInstanceInformation
  - S3: CreateBucket, PutBucketPolicy
  - CloudWatch Logs: CreateLogGroup
- Basic understanding of AWS IAM, EC2, and Systems Manager
- Estimated cost: $0.50-$2.00 per hour for EC2 instances (t3.micro)

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name session-manager-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=EnvironmentName,ParameterValue=dev

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name session-manager-stack

# Get the instance ID from stack outputs
INSTANCE_ID=$(aws cloudformation describe-stacks \
    --stack-name session-manager-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' \
    --output text)

# Start a session
aws ssm start-session --target $INSTANCE_ID
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy SessionManagerStack

# Get the instance ID from CDK outputs
INSTANCE_ID=$(aws cloudformation describe-stacks \
    --stack-name SessionManagerStack \
    --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' \
    --output text)

# Start a session
aws ssm start-session --target $INSTANCE_ID
```

### Using CDK Python

```bash
cd cdk-python/

# Create and activate virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate.bat

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy SessionManagerStack

# Get the instance ID from CDK outputs
INSTANCE_ID=$(aws cloudformation describe-stacks \
    --stack-name SessionManagerStack \
    --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' \
    --output text)

# Start a session
aws ssm start-session --target $INSTANCE_ID
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan

# Apply the configuration
terraform apply

# Get the instance ID from Terraform outputs
INSTANCE_ID=$(terraform output -raw instance_id)

# Start a session
aws ssm start-session --target $INSTANCE_ID
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will output the instance ID
# Use it to start a session:
# aws ssm start-session --target <INSTANCE_ID>
```

## Configuration Options

### Environment Variables

Set these environment variables to customize the deployment:

```bash
export AWS_REGION=us-west-2              # AWS region for deployment
export ENVIRONMENT_NAME=dev              # Environment identifier
export INSTANCE_TYPE=t3.micro           # EC2 instance type
export LOG_RETENTION_DAYS=30             # CloudWatch log retention
export ENABLE_S3_LOGGING=true           # Enable S3 session logging
```

### Terraform Variables

Create a `terraform.tfvars` file in the terraform directory:

```hcl
environment_name     = "dev"
instance_type       = "t3.micro"
log_retention_days  = 30
enable_s3_logging   = true
allowed_cidr_blocks = ["10.0.0.0/8"]
```

### CloudFormation Parameters

When using CloudFormation, you can override default parameters:

```bash
aws cloudformation create-stack \
    --stack-name session-manager-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameters \
        ParameterKey=EnvironmentName,ParameterValue=production \
        ParameterKey=InstanceType,ParameterValue=t3.small \
        ParameterKey=LogRetentionDays,ParameterValue=90
```

## Validation and Testing

After deployment, validate the solution:

1. **Verify Instance Registration**:
   ```bash
   aws ssm describe-instance-information \
       --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
       --query 'InstanceInformationList[0].[InstanceId,PingStatus,AgentVersion]' \
       --output table
   ```

2. **Test Session Access**:
   ```bash
   aws ssm start-session --target $INSTANCE_ID
   ```

3. **Verify Logging Configuration**:
   ```bash
   # Check CloudWatch log group
   aws logs describe-log-groups \
       --log-group-name-prefix "/aws/sessionmanager" \
       --query 'logGroups[0].[logGroupName,retentionInDays]' \
       --output table

   # Check S3 bucket (if enabled)
   aws s3 ls | grep sessionmanager-logs
   ```

4. **Test Non-Interactive Commands**:
   ```bash
   aws ssm start-session \
       --target $INSTANCE_ID \
       --document-name AWS-StartNonInteractiveCommand \
       --parameters command="whoami && uptime"
   ```

## Security Considerations

- **IAM Permissions**: The solution implements least-privilege access using IAM roles and policies
- **Network Security**: No inbound ports are opened; all access is through AWS APIs
- **Audit Logging**: All session activity is logged to CloudWatch and optionally S3
- **Encryption**: Session data is encrypted in transit using TLS 1.2
- **Access Control**: Fine-grained access control using resource tags and IAM conditions

## Monitoring and Logging

- **Session Logs**: Available in CloudWatch Logs under `/aws/sessionmanager/`
- **API Calls**: Logged in CloudTrail for audit purposes
- **S3 Storage**: Long-term log retention in encrypted S3 bucket
- **Real-time Monitoring**: CloudWatch metrics for session activity

## Troubleshooting

### Common Issues

1. **Instance Not Appearing in Session Manager**:
   - Verify the IAM role has `AmazonSSMManagedInstanceCore` policy
   - Check that SSM Agent is running: `sudo systemctl status amazon-ssm-agent`
   - Ensure the instance has internet connectivity or VPC endpoints

2. **Permission Denied Errors**:
   - Verify IAM user/role has the Session Manager user policy
   - Check resource tags match the policy conditions
   - Confirm the target instance has the correct tags

3. **Session Logging Not Working**:
   - Verify CloudWatch log group exists and has proper permissions
   - Check S3 bucket permissions and encryption settings
   - Ensure Session Manager preferences are configured correctly

### Debug Commands

```bash
# Check SSM Agent status on instance
aws ssm send-command \
    --instance-ids $INSTANCE_ID \
    --document-name "AWS-UpdateSSMAgent" \
    --comment "Update SSM Agent"

# View recent CloudTrail events
aws logs filter-log-events \
    --log-group-name CloudTrail/SessionManagerEvents \
    --start-time $(date -d '1 hour ago' +%s)000
```

## Cleanup

### Using CloudFormation

```bash
aws cloudformation delete-stack --stack-name session-manager-stack
aws cloudformation wait stack-delete-complete --stack-name session-manager-stack
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
cdk destroy SessionManagerStack
```

### Using CDK Python

```bash
cd cdk-python/
cdk destroy SessionManagerStack
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

## Customization

### Adding Custom Session Documents

Create custom SSM documents for specific administrative tasks:

```json
{
  "schemaVersion": "1.2",
  "description": "Custom session document for database administration",
  "sessionType": "Standard_Stream",
  "inputs": {
    "runAsEnabled": true,
    "runAsDefaultUser": "dbadmin"
  }
}
```

### Port Forwarding Setup

Enable port forwarding for accessing applications:

```bash
aws ssm start-session \
    --target $INSTANCE_ID \
    --document-name AWS-StartPortForwardingSession \
    --parameters '{"portNumber":["3306"],"localPortNumber":["13306"]}'
```

### Multi-Region Deployment

Extend the solution across multiple regions by deploying the same infrastructure in different AWS regions and configuring cross-region log aggregation.

## Cost Optimization

- Use Spot instances for development environments
- Configure appropriate CloudWatch log retention periods
- Implement S3 lifecycle policies for log archives
- Consider using Lambda functions for automated resource management

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS Systems Manager documentation: https://docs.aws.amazon.com/systems-manager/
3. Consult AWS IAM best practices: https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html
4. Review CloudFormation/CDK/Terraform provider documentation

## Additional Resources

- [AWS Systems Manager Session Manager User Guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [AWS Security Best Practices for Systems Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/security-best-practices.html)
- [IAM Roles for Amazon EC2](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_switch-role-ec2.html)
- [AWS Well-Architected Framework Security Pillar](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/welcome.html)