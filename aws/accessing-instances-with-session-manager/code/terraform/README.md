# Terraform Configuration for Secure Remote Access with Session Manager

This Terraform configuration creates a secure remote access solution using AWS Systems Manager Session Manager, eliminating the need for SSH keys, bastion hosts, or open inbound ports.

## Architecture

The infrastructure includes:

- **EC2 Instance**: Demo instance with SSM Agent for Session Manager access
- **IAM Roles & Policies**: Secure access control with least privilege principles
- **Session Logging**: CloudWatch Logs and S3 storage for audit trails
- **Encryption**: KMS key for encrypting session logs and storage
- **Security Groups**: Zero inbound rules - access via Session Manager only
- **CloudTrail**: Optional API logging for Session Manager activities

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- Terraform >= 1.0
- IAM permissions to create EC2, IAM, S3, CloudWatch, and KMS resources

## Quick Start

1. **Clone and Navigate**:
   ```bash
   cd terraform/
   ```

2. **Configure Variables**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your desired configuration
   ```

3. **Initialize Terraform**:
   ```bash
   terraform init
   ```

4. **Plan Deployment**:
   ```bash
   terraform plan
   ```

5. **Deploy Infrastructure**:
   ```bash
   terraform apply
   ```

6. **Get Outputs**:
   ```bash
   terraform output
   ```

## Configuration Options

### Core Variables

- `environment`: Environment name (dev, staging, prod)
- `project_name`: Project identifier for resource naming
- `instance_type`: EC2 instance type (default: t3.micro)

### Logging Configuration

- `enable_logging`: Enable session logging to CloudWatch and S3
- `log_retention_days`: CloudWatch log retention period
- `s3_log_prefix`: S3 key prefix for session logs
- `enable_cloudtrail_logging`: Enable CloudTrail for API logging

### Security Settings

- `kms_key_deletion_window`: KMS key deletion grace period (7-30 days)
- `allowed_users`: List of IAM users/roles for Session Manager access

### Network Configuration

- `vpc_id`: VPC ID (optional - uses default VPC if not specified)
- `subnet_id`: Subnet ID (optional - uses default subnet if not specified)

## Usage Instructions

### Attach User Policy

After deployment, attach the created IAM policy to users who need Session Manager access:

```bash
# Get the policy ARN from terraform output
POLICY_ARN=$(terraform output -raw user_policy_arn)

# Attach to a user
aws iam attach-user-policy \
    --user-name YOUR_USERNAME \
    --policy-arn $POLICY_ARN
```

### Start Session Manager Session

```bash
# Get instance ID from terraform output
INSTANCE_ID=$(terraform output -raw instance_id)

# Start interactive session
aws ssm start-session --target $INSTANCE_ID

# Run single command
aws ssm start-session \
    --target $INSTANCE_ID \
    --document-name AWS-StartNonInteractiveCommand \
    --parameters command="whoami && uptime"
```

### Port Forwarding

Forward ports through Session Manager for secure application access:

```bash
# Forward remote port 80 to local port 8080
aws ssm start-session \
    --target $INSTANCE_ID \
    --document-name AWS-StartPortForwardingSession \
    --parameters "portNumber=80,localPortNumber=8080"
```

### View Session Logs

If logging is enabled, view session activity:

```bash
# Get log group name
LOG_GROUP=$(terraform output -raw cloudwatch_log_group_name)

# List recent log streams
aws logs describe-log-streams \
    --log-group-name $LOG_GROUP \
    --order-by LastEventTime \
    --descending \
    --max-items 5

# View log events
aws logs get-log-events \
    --log-group-name $LOG_GROUP \
    --log-stream-name STREAM_NAME
```

## Verification

Verify the deployment:

```bash
# Check instance registration with Systems Manager
aws ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=$(terraform output -raw instance_id)" \
    --query 'InstanceInformationList[0].[InstanceId,PingStatus,LastPingDateTime]' \
    --output table

# Test session access
terraform output verification_commands
```

## Security Features

### Zero Trust Architecture
- No SSH keys required
- No inbound security group rules
- All access authenticated via AWS IAM
- Encrypted sessions using AWS APIs

### Comprehensive Logging
- All session activity logged to CloudWatch
- Long-term storage in encrypted S3 bucket
- CloudTrail logging of Session Manager API calls
- KMS encryption for all log data

### Access Controls
- Tag-based access control using IAM conditions
- Least privilege IAM policies
- User-specific session resource naming
- Granular permissions for different operations

## Cost Optimization

- Uses t3.micro instances by default (AWS Free Tier eligible)
- CloudWatch log retention configurable (7-365 days)
- S3 lifecycle policies can be added for log archiving
- No additional charges for Session Manager service

## Troubleshooting

### Instance Not Showing in Session Manager

1. Check instance has proper IAM role:
   ```bash
   aws ec2 describe-instances --instance-ids $(terraform output -raw instance_id) \
       --query 'Reservations[0].Instances[0].IamInstanceProfile'
   ```

2. Verify SSM Agent is running:
   ```bash
   aws ssm describe-instance-information \
       --filters "Key=InstanceIds,Values=$(terraform output -raw instance_id)"
   ```

3. Check VPC endpoints if using private subnets:
   ```bash
   aws ec2 describe-vpc-endpoints \
       --filters "Name=vpc-id,Values=VPC_ID" \
       --query 'VpcEndpoints[?ServiceName==`com.amazonaws.region.ssm`]'
   ```

### Session Logging Not Working

1. Verify CloudWatch log group exists:
   ```bash
   aws logs describe-log-groups \
       --log-group-name-prefix $(terraform output -raw cloudwatch_log_group_name)
   ```

2. Check S3 bucket permissions:
   ```bash
   aws s3api get-bucket-policy \
       --bucket $(terraform output -raw s3_logs_bucket_name)
   ```

### Access Denied Errors

1. Verify IAM policy is attached to user:
   ```bash
   aws iam list-attached-user-policies --user-name YOUR_USERNAME
   ```

2. Check instance tags match policy conditions:
   ```bash
   aws ec2 describe-tags --filters "Name=resource-id,Values=$(terraform output -raw instance_id)"
   ```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will permanently delete all resources including logs. Ensure you have backups if needed.

## Advanced Configuration

### Multiple Instances

To create multiple instances with different configurations:

```hcl
# In terraform.tfvars
instance_configurations = [
  {
    name = "web-server"
    type = "t3.small"
    tags = { Purpose = "WebServer" }
  },
  {
    name = "database"
    type = "t3.medium"
    tags = { Purpose = "Database" }
  }
]
```

### Custom Session Document

Create custom session documents for specific workflows:

```hcl
resource "aws_ssm_document" "custom_session" {
  name          = "CustomSession"
  document_type = "Session"
  document_format = "JSON"
  
  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Custom session with specific settings"
    sessionType   = "Standard_Stream"
    inputs = {
      runAsEnabled = true
      runAsDefaultUser = "ec2-user"
      idleSessionTimeout = "10"
    }
  })
}
```

### Integration with Existing Infrastructure

Use data sources to integrate with existing resources:

```hcl
# Use existing VPC
data "aws_vpc" "existing" {
  tags = {
    Name = "production-vpc"
  }
}

# Use existing security group
data "aws_security_group" "existing" {
  name   = "application-sg"
  vpc_id = data.aws_vpc.existing.id
}
```

## References

- [AWS Systems Manager Session Manager User Guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [Session Manager Prerequisites](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-prerequisites.html)
- [AWS Security Best Practices for Systems Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/security-best-practices.html)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)