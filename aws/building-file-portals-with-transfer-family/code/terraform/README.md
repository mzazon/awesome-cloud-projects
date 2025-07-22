# AWS Transfer Family Web App - Secure File Portal

This Terraform configuration deploys a complete secure file portal solution using AWS Transfer Family Web Apps with IAM Identity Center integration and S3 Access Grants for fine-grained permission management.

## 🏗️ Architecture Overview

The solution creates:

- **Transfer Family Web App**: Browser-based file portal with enterprise authentication
- **S3 Bucket**: Secure file storage with versioning, encryption, and lifecycle policies
- **IAM Identity Center Integration**: Centralized identity management with SAML/OIDC support
- **S3 Access Grants**: Fine-grained permission control without complex IAM policies
- **CloudWatch Monitoring**: Comprehensive logging and security alerting
- **AWS Backup**: Optional automated backup solution

## 📋 Prerequisites

### Required Tools

- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) >= 2.0
- Valid AWS credentials configured

### Required AWS Services

- **IAM Identity Center**: Must be enabled in your AWS account
- **AWS Transfer Family**: Available in your deployment region
- **Amazon S3**: For file storage
- **CloudWatch**: For monitoring and logging

### Required Permissions

Your AWS credentials must have permissions for:

- IAM role and policy management
- S3 bucket creation and configuration
- Transfer Family operations
- IAM Identity Center user management
- S3 Access Grants configuration
- CloudWatch logging setup

## 🚀 Quick Start

### 1. Clone and Configure

```bash
# Navigate to the terraform directory
cd terraform/

# Copy example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit variables for your environment
vim terraform.tfvars
```

### 2. Initialize Terraform

```bash
# Initialize Terraform and download providers
terraform init

# Validate configuration
terraform validate

# Review planned changes
terraform plan
```

### 3. Deploy Infrastructure

```bash
# Apply configuration
terraform apply

# Confirm deployment by typing 'yes' when prompted
```

### 4. Access the Portal

After deployment, Terraform will output the access URL:

```bash
# Get the web app URL
terraform output web_app_access_url
```

Navigate to the URL in your browser and authenticate with IAM Identity Center credentials.

## ⚙️ Configuration Options

### Basic Configuration

Key variables you should configure in `terraform.tfvars`:

```hcl
# Project identification
project_name = "secure-file-portal"
environment  = "dev"
cost_center  = "IT-Operations"

# Web app sizing
web_app_units = 1  # 1 unit supports ~500 concurrent users

# Test user creation (set to false for production)
create_identity_center_user = true
test_user_email            = "your-email@example.com"
```

### Security Configuration

```hcl
# S3 security features
enable_s3_versioning       = true
enable_encryption         = true
enable_public_access_block = true
enable_access_logging      = true

# Monitoring and alerting
enable_security_monitoring = true
failed_login_threshold     = 5
log_retention_days        = 30
```

### Advanced Configuration

```hcl
# Backup configuration
enable_backup            = true
backup_retention_days    = 120
backup_cold_storage_days = 30

# Network restrictions
allowed_ip_ranges = [
  "203.0.113.0/24",  # Office network
  "198.51.100.0/24"  # VPN network
]

# Additional AWS service integrations
enable_cloudtrail_integration = true
enable_config_integration     = true
enable_guardduty_integration  = true
```

## 📊 Monitoring and Logging

### CloudWatch Integration

The solution automatically configures:

- **Transfer Family Logs**: User activity and system events
- **S3 Access Logs**: File access and API operations
- **Security Alarms**: Failed login attempt monitoring
- **Metric Filters**: Custom security event detection

### Log Groups Created

- `/aws/transfer/webapp/{web-app-id}` - Transfer Family Web App logs
- `/aws/s3/access-logs/{bucket-name}` - S3 access logs

### Security Monitoring

- **Failed Login Alarm**: Triggers when failed attempts exceed threshold
- **Metric Filters**: Detect suspicious access patterns
- **SNS Integration**: Optional alerting to operations teams

## 🔐 Security Features

### Data Protection

- **Encryption at Rest**: AES-256 encryption for all S3 objects
- **Encryption in Transit**: HTTPS/TLS for all web app traffic
- **Versioning**: Track file changes and enable recovery
- **Access Logging**: Comprehensive audit trail

### Access Control

- **IAM Identity Center**: Enterprise identity provider integration
- **S3 Access Grants**: Fine-grained permission management
- **CORS Protection**: Restrict web app access to authorized origins
- **Public Access Block**: Prevent accidental public exposure

### Network Security

- **IP Restrictions**: Optional allowlist for network access
- **HTTPS Only**: Force encrypted connections
- **Custom Domain**: Optional branded domain with SSL certificates

## 🔄 Backup and Recovery

### Automated Backup (Optional)

When `enable_backup = true`:

- **Daily Backups**: Scheduled at 5 AM UTC
- **Lifecycle Management**: Automatic transition to cold storage
- **Cross-Region**: Optional replication for disaster recovery
- **Retention Policies**: Configurable retention periods

### Manual Backup

```bash
# Sync bucket to backup location
aws s3 sync s3://your-bucket-name s3://backup-bucket-name

# Create point-in-time snapshot
aws s3 cp s3://your-bucket-name s3://backup-bucket/$(date +%Y%m%d)/ --recursive
```

## 🛠️ Maintenance

### Updating the Infrastructure

```bash
# Update Terraform configuration
git pull origin main

# Review changes
terraform plan

# Apply updates
terraform apply
```

### Monitoring Health

```bash
# Check web app status
aws transfer describe-web-app --web-app-id $(terraform output -raw web_app_id)

# Verify S3 access grants
aws s3control list-access-grants --account-id $(aws sts get-caller-identity --query Account --output text)

# Test web app connectivity
curl -I $(terraform output -raw web_app_access_url)
```

### Troubleshooting

#### Common Issues

1. **Identity Center Not Available**
   - Ensure IAM Identity Center is enabled in your account
   - Verify you're deploying in a supported region

2. **Permission Denied Errors**
   - Check AWS credentials have required permissions
   - Verify IAM roles are properly configured

3. **Web App Not Accessible**
   - Check CORS configuration
   - Verify security group settings
   - Confirm DNS resolution

#### Debug Commands

```bash
# Check Terraform state
terraform show

# Validate configuration
terraform validate

# Check AWS credentials
aws sts get-caller-identity

# Verify IAM Identity Center
aws sso-admin list-instances
```

## 🧹 Cleanup

### Automated Cleanup

```bash
# Destroy all resources
terraform destroy

# Confirm by typing 'yes' when prompted
```

### Manual Cleanup (if needed)

```bash
# Empty S3 bucket before destruction
aws s3 rm s3://$(terraform output -raw s3_bucket_name) --recursive

# Delete web app
aws transfer delete-web-app --web-app-id $(terraform output -raw web_app_id)

# Remove access grants
aws s3control delete-access-grants-instance --account-id $(aws sts get-caller-identity --query Account --output text)
```

## 💰 Cost Optimization

### Cost Factors

- **Transfer Family Web App**: $0.30/hour per unit (720 hours/month = ~$216)
- **S3 Storage**: $0.023/GB/month (Standard class)
- **S3 Requests**: $0.0004/1,000 PUT requests, $0.0004/10,000 GET requests
- **CloudWatch Logs**: $0.50/GB ingested
- **Data Transfer**: $0.09/GB outbound (first 1GB free monthly)

### Cost Optimization Tips

1. **Right-size Web App Units**: Start with 1 unit, scale as needed
2. **Enable S3 Lifecycle Policies**: Automatically transition to cheaper storage
3. **Optimize Log Retention**: Reduce retention period for non-critical logs
4. **Monitor Usage**: Use AWS Cost Explorer to track spending

### Estimated Monthly Costs

- **Development**: $220-250/month (1 web app unit, minimal usage)
- **Production**: $300-500/month (2 web app units, backup enabled)

## 🔗 Additional Resources

- [AWS Transfer Family Web Apps Documentation](https://docs.aws.amazon.com/transfer/latest/userguide/web-app.html)
- [IAM Identity Center User Guide](https://docs.aws.amazon.com/singlesignon/latest/userguide/what-is.html)
- [S3 Access Grants Documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-grants.html)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## 📞 Support

For issues with this Terraform configuration:

1. Check the [troubleshooting section](#troubleshooting)
2. Review AWS service documentation
3. Consult Terraform AWS provider documentation
4. Check AWS service health dashboard

## 📄 License

This Terraform configuration is provided as-is for educational and demonstration purposes. Please review and test thoroughly before using in production environments.