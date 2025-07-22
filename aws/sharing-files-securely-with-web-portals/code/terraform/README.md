# Secure File Sharing with AWS Transfer Family - Terraform Infrastructure

This Terraform configuration deploys a complete secure file sharing solution using AWS Transfer Family, S3, CloudTrail, and KMS encryption. The infrastructure provides a secure, scalable, and auditable file sharing platform suitable for business-to-business file exchange and secure internal document sharing.

## Architecture Overview

The solution deploys:

- **AWS Transfer Family Server** with SFTP protocol support
- **S3 Bucket** with encryption, versioning, and lifecycle management
- **CloudTrail** for comprehensive audit logging
- **KMS Keys** for encryption at rest
- **IAM Roles and Policies** following least privilege principles
- **CloudWatch Log Groups** for centralized logging
- **Sample file structure** for immediate testing

## Features

- ✅ **Secure by Default**: KMS encryption, versioning, public access blocking
- ✅ **Comprehensive Auditing**: CloudTrail with data events and log file validation
- ✅ **Cost Optimization**: S3 lifecycle policies for automatic storage class transitions
- ✅ **Scalable Architecture**: Fully managed AWS services that scale automatically
- ✅ **Monitoring Ready**: CloudWatch integration with structured logging
- ✅ **Production Ready**: Security best practices and compliance features

## Prerequisites

- AWS CLI v2 installed and configured with appropriate permissions
- Terraform >= 1.0 installed
- AWS account with permissions to create:
  - Transfer Family servers and users
  - S3 buckets and configurations
  - IAM roles and policies
  - KMS keys
  - CloudTrail trails
  - CloudWatch log groups

## Quick Start

### 1. Clone and Navigate

```bash
cd terraform/
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Review and Customize Variables

Create a `terraform.tfvars` file:

```hcl
# Basic configuration
aws_region      = "us-east-1"
environment     = "dev"
project_name    = "secure-file-sharing"

# Transfer Family configuration
transfer_protocols = ["SFTP"]
test_user_name    = "testuser"

# Security and compliance
enable_cloudtrail = true
enable_sso_integration = false

# Cost optimization
s3_lifecycle_enable = true
s3_transition_to_ia_days = 30
s3_transition_to_glacier_days = 90
```

### 4. Plan and Apply

```bash
# Review the planned changes
terraform plan

# Deploy the infrastructure
terraform apply
```

### 5. Validate Deployment

After deployment, test the infrastructure:

```bash
# Check Transfer Family server status
aws transfer describe-server --server-id $(terraform output -raw transfer_server_id)

# List S3 bucket contents
aws s3 ls s3://$(terraform output -raw s3_bucket_name)/

# Test SFTP connection (requires password or SSH key setup)
sftp $(terraform output -raw transfer_test_user_name)@$(terraform output -raw transfer_server_endpoint)
```

## Configuration Variables

### Core Settings

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `aws_region` | AWS region for resources | `us-east-1` | No |
| `environment` | Environment tag | `dev` | No |
| `project_name` | Project name for resources | `secure-file-sharing` | No |

### Transfer Family Settings

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `transfer_server_endpoint_type` | Endpoint type | `PUBLIC` | No |
| `transfer_protocols` | Supported protocols | `["SFTP"]` | No |
| `test_user_name` | Test user name | `testuser` | No |

### Security Settings

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `enable_cloudtrail` | Enable audit logging | `true` | No |
| `kms_key_deletion_window` | KMS key deletion window | `10` | No |
| `allowed_cidr_blocks` | Allowed IP ranges | `["0.0.0.0/0"]` | No |

### Cost Optimization

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `s3_lifecycle_enable` | Enable lifecycle policies | `true` | No |
| `s3_transition_to_ia_days` | Days to IA transition | `30` | No |
| `s3_transition_to_glacier_days` | Days to Glacier transition | `90` | No |

## Security Considerations

### Encryption
- All S3 objects encrypted with customer-managed KMS keys
- CloudTrail logs encrypted with separate KMS key
- Key rotation enabled for all KMS keys

### Access Control
- IAM roles follow least privilege principle
- S3 bucket blocks all public access
- Transfer Family users restricted to home directories

### Auditing
- CloudTrail captures all API calls and data events
- Log file validation enabled for tamper detection
- Multi-region trail for comprehensive coverage
- Structured logging to CloudWatch

### Network Security
- Public endpoint with configurable IP restrictions
- Option to deploy VPC endpoint for enhanced security
- Security policies enforce strong encryption

## Cost Optimization

The solution includes several cost optimization features:

1. **S3 Lifecycle Policies**: Automatically transition files to cheaper storage classes
2. **CloudWatch Log Retention**: Configurable retention periods to control log costs
3. **KMS Key Optimization**: Bucket key encryption reduces KMS costs
4. **Regional Deployment**: Single region deployment unless multi-region is required

### Estimated Monthly Costs

For light usage (< 100GB storage, < 1000 API calls/month):
- Transfer Family Server: ~$216/month
- S3 Standard Storage (100GB): ~$2.30/month
- KMS Keys: ~$2/month
- CloudTrail: ~$2/month (first trail free)
- **Total: ~$222/month**

## Monitoring and Alerting

### CloudWatch Metrics

The solution automatically creates CloudWatch log groups for:
- Transfer Family server logs
- CloudTrail logs

### Recommended CloudWatch Alarms

Add these alarms for production deployments:

```hcl
# Failed login attempts
resource "aws_cloudwatch_metric_alarm" "failed_logins" {
  alarm_name          = "${var.project_name}-failed-logins"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ErrorCount"
  namespace           = "AWS/Transfer"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "High number of failed login attempts"
  
  dimensions = {
    ServerId = aws_transfer_server.secure_server.id
  }
}
```

## Backup and Disaster Recovery

### S3 Versioning
- Enabled by default for data protection
- Previous versions retained based on lifecycle policies

### Cross-Region Replication
To enable cross-region replication for disaster recovery:

```hcl
resource "aws_s3_bucket_replication_configuration" "replication" {
  role   = aws_iam_role.replication.arn
  bucket = aws_s3_bucket.file_storage.id

  rule {
    id     = "replicate_all"
    status = "Enabled"

    destination {
      bucket = "arn:aws:s3:::backup-bucket-name"
      
      encryption_configuration {
        replica_kms_key_id = aws_kms_key.s3_encryption.arn
      }
    }
  }
}
```

## Compliance Features

### SOC 2 / HIPAA / PCI DSS
- Encryption at rest and in transit
- Comprehensive audit logging
- Access controls and authentication
- Data retention policies

### GDPR
- Right to be forgotten: Automated deletion through lifecycle policies
- Data encryption and access controls
- Audit trail for data access

## Troubleshooting

### Common Issues

1. **Transfer Family User Cannot Connect**
   - Verify IAM role permissions
   - Check S3 bucket policies
   - Validate home directory mappings

2. **CloudTrail Not Logging**
   - Verify S3 bucket policy
   - Check IAM role permissions
   - Confirm trail is enabled

3. **S3 Access Denied**
   - Review IAM policies
   - Check bucket public access block settings
   - Verify KMS key permissions

### Debug Commands

```bash
# Check Transfer Family server configuration
terraform output validation_commands

# View CloudTrail events
aws logs filter-log-events \
  --log-group-name $(terraform output -raw cloudtrail_log_group_name) \
  --start-time $(date -d '1 hour ago' +%s)000

# Test S3 access
aws s3api head-object \
  --bucket $(terraform output -raw s3_bucket_name) \
  --key welcome.txt
```

## Cleanup

To destroy all resources:

```bash
# Remove all Terraform-managed resources
terraform destroy

# Verify cleanup
aws transfer list-servers
aws s3 ls
```

> **Warning**: This will permanently delete all files and configurations. Ensure you have backups if needed.

## Security Hardening

For production deployments, consider these additional security measures:

### 1. VPC Endpoint Configuration
```hcl
variable "transfer_server_endpoint_type" {
  default = "VPC"
}

variable "vpc_id" {
  description = "VPC ID for Transfer Family endpoint"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for Transfer Family endpoint"
  type        = list(string)
}
```

### 2. IP Restrictions
```hcl
variable "allowed_cidr_blocks" {
  default = ["10.0.0.0/8", "172.16.0.0/12"]
}
```

### 3. Multi-Factor Authentication
Enable MFA through IAM Identity Center integration:

```hcl
variable "enable_sso_integration" {
  default = true
}
```

## Support and Documentation

- **AWS Transfer Family**: [User Guide](https://docs.aws.amazon.com/transfer/)
- **S3 Security**: [Best Practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html)
- **CloudTrail**: [User Guide](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/)
- **IAM**: [Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)

For issues with this Terraform configuration, check the AWS provider documentation or file an issue with detailed error messages and configuration details.