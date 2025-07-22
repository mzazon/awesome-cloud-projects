# Terraform Infrastructure as Code for AWS

This directory contains a complete Terraform configuration for deploying a scalable web application infrastructure on AWS, demonstrating Infrastructure as Code best practices.

## Architecture Overview

This Terraform configuration deploys:

- **VPC with Multi-AZ Public Subnets** - Provides network isolation and high availability
- **Application Load Balancer (ALB)** - Distributes traffic across multiple instances
- **Auto Scaling Group with Launch Template** - Ensures application availability and automatic scaling
- **Security Groups** - Implements least-privilege network security
- **CloudWatch Alarms** - Monitors CPU utilization and triggers scaling actions
- **S3 Bucket for ALB Logs** - Optional access logging for monitoring and troubleshooting

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **AWS CLI** installed and configured with appropriate credentials
2. **Terraform** v1.0 or later installed
3. **AWS Account** with sufficient permissions for:
   - VPC and networking resources
   - EC2 instances and Auto Scaling
   - Application Load Balancer
   - CloudWatch alarms
   - S3 buckets (if logging enabled)
4. **S3 Backend** prepared for remote state management (recommended)
5. **DynamoDB Table** for state locking (recommended)

## Quick Start

### 1. Prepare Terraform Backend (Recommended)

```bash
# Create S3 bucket for Terraform state
aws s3api create-bucket \
    --bucket your-terraform-state-bucket \
    --create-bucket-configuration LocationConstraint=us-west-2

# Enable versioning
aws s3api put-bucket-versioning \
    --bucket your-terraform-state-bucket \
    --versioning-configuration Status=Enabled

# Create DynamoDB table for state locking
aws dynamodb create-table \
    --table-name terraform-state-locks \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5
```

### 2. Initialize Terraform

```bash
# Clone or navigate to this directory
cd terraform/

# Initialize with remote backend (recommended)
terraform init \
    -backend-config="bucket=your-terraform-state-bucket" \
    -backend-config="key=infrastructure-as-code-demo/terraform.tfstate" \
    -backend-config="region=us-west-2" \
    -backend-config="dynamodb_table=terraform-state-locks" \
    -backend-config="encrypt=true"

# Or initialize with local state (not recommended for production)
terraform init
```

### 3. Review and Customize Variables

Create a `terraform.tfvars` file to customize your deployment:

```hcl
# terraform.tfvars
aws_region     = "us-west-2"
project_name   = "my-iac-demo"
environment    = "dev"
vpc_cidr       = "10.0.0.0/16"
instance_type  = "t3.micro"
min_capacity   = 2
max_capacity   = 4
enable_logging = true

additional_tags = {
  Owner       = "DevOps Team"
  CostCenter  = "Engineering"
  Application = "Web Demo"
}
```

### 4. Plan and Deploy

```bash
# Review the execution plan
terraform plan

# Apply the configuration
terraform apply

# Confirm with 'yes' when prompted
```

### 5. Access Your Application

After deployment, retrieve the load balancer URL:

```bash
# Get the ALB DNS name
terraform output alb_url

# Test the application
curl $(terraform output -raw alb_url)
```

## Configuration Options

### Environment Variables

You can override variables using environment variables:

```bash
export TF_VAR_project_name="my-custom-project"
export TF_VAR_environment="staging"
export TF_VAR_instance_type="t3.small"
```

### Variable Descriptions

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `aws_region` | string | `"us-east-1"` | AWS region for deployment |
| `project_name` | string | `"terraform-iac-demo"` | Project name for resource naming |
| `environment` | string | `"dev"` | Environment (dev/staging/prod) |
| `vpc_cidr` | string | `"10.0.0.0/16"` | CIDR block for VPC |
| `instance_type` | string | `"t3.micro"` | EC2 instance type |
| `min_capacity` | number | `2` | Minimum instances in ASG |
| `max_capacity` | number | `4` | Maximum instances in ASG |
| `desired_capacity` | number | `2` | Desired instances in ASG |
| `enable_logging` | bool | `true` | Enable ALB access logging |
| `ssl_certificate_arn` | string | `""` | SSL certificate ARN for HTTPS |

## Outputs

After deployment, Terraform provides these useful outputs:

- `alb_url` - Application access URL
- `vpc_id` - VPC identifier
- `alb_dns_name` - Load balancer DNS name
- `autoscaling_group_name` - Auto Scaling Group name
- `resource_name_prefix` - Resource naming prefix
- `estimated_monthly_cost_components` - Cost breakdown

## Validation and Testing

### Verify Infrastructure

```bash
# List all created resources
terraform state list

# Show specific resource details
terraform state show aws_lb.web

# Refresh state from AWS
terraform refresh
```

### Test Application

```bash
# Test load balancer health
ALB_URL=$(terraform output -raw alb_url)
curl -I $ALB_URL

# Test multiple requests to see load balancing
for i in {1..5}; do
  curl -s $ALB_URL | grep "Instance ID"
done

# Check Auto Scaling Group
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names $(terraform output -raw autoscaling_group_name)
```

### Monitor Resources

```bash
# Check CloudWatch alarms
aws cloudwatch describe-alarms \
    --alarm-names $(terraform output -raw cloudwatch_alarm_high_cpu_name)

# View ALB access logs (if enabled)
aws s3 ls s3://$(terraform output -raw alb_logs_bucket_name)/
```

## Cost Estimation

Estimated monthly costs (US East 1, subject to change):

| Component | Monthly Cost (USD) |
|-----------|-------------------|
| Application Load Balancer | ~$16.20 |
| EC2 Instances (2x t3.micro) | ~$17.00 |
| Data Transfer (100GB) | ~$9.00 |
| CloudWatch Alarms | ~$0.20 |
| S3 Storage (ALB logs) | ~$0.50 |
| **Total Estimated** | **~$43.00** |

*Costs may vary based on usage, region, and AWS pricing changes.*

## Security Considerations

This configuration implements several security best practices:

- **Security Groups**: Restrict access to necessary ports only
- **IMDSv2**: Forces use of Instance Metadata Service v2
- **S3 Encryption**: ALB logs bucket uses server-side encryption
- **Public Access Block**: S3 bucket blocks public access
- **VPC Isolation**: Resources deployed in isolated VPC

### Additional Security Recommendations

1. **SSL/TLS**: Add SSL certificate for HTTPS traffic
2. **WAF**: Consider adding AWS WAF for application protection
3. **Secrets Manager**: Use for sensitive configuration data
4. **VPC Flow Logs**: Enable for network monitoring
5. **GuardDuty**: Enable for threat detection

## Troubleshooting

### Common Issues

1. **Permission Errors**
   ```bash
   # Check AWS credentials
   aws sts get-caller-identity
   
   # Verify required permissions
   aws iam simulate-principal-policy --policy-source-arn $(aws sts get-caller-identity --query Arn --output text) --action-names ec2:CreateVpc
   ```

2. **Resource Limits**
   ```bash
   # Check VPC limits
   aws ec2 describe-account-attributes --attribute-names max-instances
   
   # Check EIP limits
   aws ec2 describe-account-attributes --attribute-names max-elastic-ips
   ```

3. **State Lock Issues**
   ```bash
   # Force unlock (use with caution)
   terraform force-unlock LOCK_ID
   ```

4. **Validation Errors**
   ```bash
   # Validate configuration
   terraform validate
   
   # Format code
   terraform fmt -recursive
   ```

### Debug Mode

Enable Terraform debug logging:

```bash
export TF_LOG=DEBUG
export TF_LOG_PATH=./terraform.log
terraform apply
```

## Cleanup

To avoid ongoing charges, destroy the infrastructure when no longer needed:

```bash
# Destroy all resources
terraform destroy

# Confirm with 'yes' when prompted

# Clean up state bucket (optional)
aws s3 rm s3://your-terraform-state-bucket --recursive
aws s3api delete-bucket --bucket your-terraform-state-bucket

# Delete DynamoDB lock table (optional)
aws dynamodb delete-table --table-name terraform-state-locks
```

## Advanced Usage

### Multi-Environment Deployment

Create environment-specific variable files:

```bash
# environments/dev.tfvars
environment = "dev"
instance_type = "t3.micro"
min_capacity = 1
max_capacity = 2

# environments/prod.tfvars
environment = "prod"
instance_type = "t3.small"
min_capacity = 2
max_capacity = 6
enable_deletion_protection = true
```

Deploy to specific environment:

```bash
terraform plan -var-file="environments/dev.tfvars"
terraform apply -var-file="environments/dev.tfvars"
```

### CI/CD Integration

Example GitHub Actions workflow:

```yaml
name: Terraform Deploy
on:
  push:
    branches: [main]
jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: hashicorp/setup-terraform@v2
      - run: terraform init
      - run: terraform plan
      - run: terraform apply -auto-approve
```

## Module Development

This configuration can be converted to a reusable module:

```hcl
# main.tf
module "web_infrastructure" {
  source = "./modules/web-infrastructure"
  
  project_name   = "my-app"
  environment    = "production"
  instance_type  = "t3.medium"
  ssl_cert_arn   = aws_acm_certificate.main.arn
}
```

## Contributing

When modifying this configuration:

1. Follow Terraform best practices
2. Update variable validation rules
3. Add appropriate comments
4. Test changes in development environment
5. Update this README for any new features

## Resources and References

- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/index.html)
- [AWS Auto Scaling Best Practices](https://docs.aws.amazon.com/autoscaling/ec2/userguide/auto-scaling-benefits.html)

## License

This code is provided as-is for educational and demonstration purposes. Use at your own risk and ensure compliance with your organization's policies.

---

**Note**: Always review and understand the resources being created before applying Terraform configurations in production environments.