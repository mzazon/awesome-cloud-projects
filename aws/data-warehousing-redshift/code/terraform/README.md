# Amazon Redshift Data Warehouse - Terraform Infrastructure

This Terraform configuration creates a complete data warehousing solution using Amazon Redshift Serverless, S3 for data storage, and supporting AWS services.

## Architecture Overview

The infrastructure includes:
- **Amazon Redshift Serverless**: Scalable data warehouse with namespace and workgroup
- **S3 Bucket**: Secure data storage for data lake integration
- **IAM Role**: Secure access between Redshift and S3
- **KMS Key**: Encryption for data at rest (optional)
- **CloudWatch**: Monitoring and logging (optional)
- **Secrets Manager**: Secure storage of database credentials
- **Sample Data**: Pre-loaded sample datasets for testing

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.5 installed
- Appropriate AWS permissions for creating:
  - Redshift Serverless resources
  - S3 buckets and objects
  - IAM roles and policies
  - KMS keys (if encryption enabled)
  - CloudWatch resources (if monitoring enabled)
  - Secrets Manager secrets

## Cost Considerations

- **Redshift Serverless**: Pay-per-use compute (RPU-hours), starting at ~$0.375/RPU-hour
- **S3**: Standard storage pricing (~$0.023/GB/month)
- **KMS**: ~$1/month per key + usage charges
- **CloudWatch**: Logs and metrics charges
- **Secrets Manager**: ~$0.40/month per secret

Estimated monthly cost for development workloads: $10-50 depending on usage.

## Quick Start

1. **Clone and navigate to the directory**:
   ```bash
   cd terraform/
   ```

2. **Copy and customize variables**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your preferences
   ```

3. **Initialize Terraform**:
   ```bash
   terraform init
   ```

4. **Review the plan**:
   ```bash
   terraform plan
   ```

5. **Deploy the infrastructure**:
   ```bash
   terraform apply
   ```

6. **Connect to your data warehouse**:
   - Use the outputs to get connection information
   - Connect via AWS Query Editor v2 or your preferred SQL client
   - Run the provided SQL commands to create tables and load data

## Configuration Options

### Essential Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `aws_region` | AWS region for deployment | `us-east-1` | No |
| `environment` | Environment name (dev/staging/prod) | `dev` | No |
| `base_capacity` | Base RPU capacity for workgroup | `128` | No |
| `publicly_accessible` | Whether workgroup is publicly accessible | `true` | No |

### Security Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `enable_encryption` | Enable KMS encryption | `true` | No |
| `enable_cloudwatch_logs` | Enable CloudWatch logging | `true` | No |
| `subnet_ids` | Subnet IDs for private access | `[]` | No |
| `security_group_ids` | Security group IDs for private access | `[]` | No |

### Cost Control Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `enable_usage_limits` | Enable usage limits for cost control | `true` | No |
| `usage_limit_amount` | Monthly RPU-hour limit | `1000` | No |
| `usage_limit_breach_action` | Action on limit breach | `emit-metric` | No |

## Outputs

After deployment, Terraform provides:

- **Connection Information**: Endpoint, port, database name, username
- **Resource Details**: ARNs and IDs of created resources
- **SQL Commands**: Ready-to-use SQL for table creation and data loading
- **S3 Paths**: Locations of uploaded sample data
- **Next Steps**: Instructions for getting started

## Sample Data and Queries

The configuration automatically uploads sample datasets:
- **Sales Data**: Order transactions with customer, product, and pricing information
- **Customer Data**: Customer demographics and contact information

Sample analytical queries are provided for:
- Sales summary by customer and geography
- Daily sales trends and patterns
- Product performance analysis
- Customer segmentation by state

## Private Network Configuration

For production environments, configure private access:

```hcl
# In terraform.tfvars
publicly_accessible = false
subnet_ids = ["subnet-12345", "subnet-67890"]
security_group_ids = ["sg-abcdef"]
```

This requires:
- VPC with private subnets
- Security groups allowing Redshift traffic (port 5439)
- VPC endpoints for S3 access (recommended)

## Monitoring and Alerting

When `enable_cloudwatch_logs = true`, the configuration creates:
- CloudWatch log groups for Redshift logs
- CloudWatch dashboard with key metrics
- Capacity usage alarm
- Configurable log retention (default: 7 days)

## Security Best Practices

The configuration implements:
- **Least Privilege IAM**: Minimal permissions for Redshift S3 access
- **Encryption at Rest**: KMS encryption for Redshift and S3
- **Secure Credentials**: Passwords stored in Secrets Manager
- **Network Security**: Optional private subnet deployment
- **Access Logging**: Comprehensive audit trail

## Data Loading Process

1. **Table Creation**: Use the provided `create_tables_sql` output
2. **Data Loading**: Execute the `load_data_sql` COPY commands
3. **Query Testing**: Run the sample analytical queries
4. **BI Integration**: Connect your business intelligence tools

## Scaling and Performance

- **Auto Scaling**: Redshift Serverless automatically scales compute
- **Base Capacity**: Minimum compute units (32-512 RPUs)
- **Max Capacity**: Maximum auto-scaling limit
- **Storage**: Automatically scales with data volume
- **Query Performance**: Optimized with column storage and MPP

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure AWS credentials have sufficient permissions
2. **Naming Conflicts**: Resource names must be globally unique
3. **Capacity Limits**: Check AWS service quotas for your region
4. **Network Issues**: Verify VPC configuration for private deployments

### Debugging Steps

1. Check Terraform logs: `terraform apply -debug`
2. Verify AWS permissions: `aws sts get-caller-identity`
3. Check resource status in AWS Console
4. Review CloudWatch logs for Redshift errors

## Cleanup

To avoid ongoing charges, destroy the infrastructure when no longer needed:

```bash
terraform destroy
```

**Warning**: This will permanently delete all data and resources. Ensure you have backups if needed.

## Advanced Configurations

### Multi-Environment Setup

Use Terraform workspaces for multiple environments:

```bash
terraform workspace new production
terraform workspace select production
terraform apply -var-file="production.tfvars"
```

### Custom Encryption

Bring your own KMS key:

```hcl
# Disable auto-created key
enable_encryption = true

# Reference existing key in main.tf
kms_key_id = "arn:aws:kms:region:account:key/key-id"
```

### Integration with Data Pipeline

Connect to existing data pipelines:

```hcl
# Use existing S3 bucket
s3_bucket_name = "my-existing-data-bucket"
create_sample_data = false
```

## Support and Documentation

- [Amazon Redshift Serverless Documentation](https://docs.aws.amazon.com/redshift/latest/mgmt/working-with-serverless.html)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Redshift Best Practices](https://docs.aws.amazon.com/redshift/latest/dg/best-practices.html)
- [Cost Optimization Guide](https://docs.aws.amazon.com/redshift/latest/mgmt/managing-costs.html)