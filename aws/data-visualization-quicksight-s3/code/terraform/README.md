# Terraform Infrastructure for Data Visualization Pipeline

This Terraform configuration deploys a complete data visualization pipeline on AWS using S3, Glue, Athena, and supporting services. The infrastructure automates data processing and prepares data for visualization in Amazon QuickSight.

## Architecture Overview

The deployed infrastructure includes:

- **S3 Buckets**: Raw data storage, processed data storage, and Athena query results
- **AWS Glue**: Data catalog, crawlers for schema discovery, and ETL jobs for data transformation
- **Amazon Athena**: Serverless query engine for analyzing processed data
- **AWS Lambda**: Automation function triggered by S3 events
- **IAM Roles**: Secure access controls for all services
- **CloudWatch**: Monitoring and alerting (optional)
- **KMS**: Encryption at rest (optional)

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.0 installed
- Appropriate AWS permissions for resource creation
- QuickSight account activated (for dashboard creation)

## Quick Start

1. **Clone and Navigate**:
   ```bash
   cd aws/data-visualization-pipelines-quicksight-s3/code/terraform/
   ```

2. **Initialize Terraform**:
   ```bash
   terraform init
   ```

3. **Review Configuration**:
   ```bash
   terraform plan
   ```

4. **Deploy Infrastructure**:
   ```bash
   terraform apply
   ```

5. **Trigger Initial Processing**:
   ```bash
   # Start the raw data crawler
   aws glue start-crawler --name $(terraform output -raw glue_raw_crawler_name)
   
   # Wait for crawler to complete, then start ETL job
   aws glue start-job-run --job-name $(terraform output -raw glue_etl_job_name)
   
   # Start processed data crawler
   aws glue start-crawler --name $(terraform output -raw glue_processed_crawler_name)
   ```

## Configuration Variables

### Core Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_name` | Project name prefix for resources | `data-viz-pipeline` | No |
| `environment` | Environment (dev, staging, prod) | `dev` | No |
| `aws_region` | AWS region for deployment | `us-east-1` | No |

### S3 Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_s3_versioning` | Enable S3 bucket versioning | `true` |
| `s3_lifecycle_enabled` | Enable lifecycle management | `true` |
| `s3_lifecycle_transition_days` | Days before IA transition | `30` |
| `enable_intelligent_tiering` | Enable S3 Intelligent Tiering | `true` |

### Glue Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `glue_crawler_schedule` | Crawler schedule (cron format) | `cron(0 2 * * ? *)` |
| `glue_job_timeout` | ETL job timeout (minutes) | `60` |
| `glue_job_max_retries` | Maximum job retries | `1` |
| `glue_version` | Glue version | `4.0` |

### Security Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_kms_encryption` | Enable KMS encryption | `true` |
| `enable_cloudtrail_logging` | Enable CloudTrail logging | `false` |

### Monitoring Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_cloudwatch_alarms` | Enable CloudWatch alarms | `true` |
| `notification_email` | Email for notifications | `""` |

## Customization Examples

### Basic Deployment

```hcl
# terraform.tfvars
project_name = "sales-analytics"
environment  = "dev"
aws_region   = "us-west-2"
```

### Production Deployment

```hcl
# terraform.tfvars
project_name = "sales-analytics"
environment  = "prod"
aws_region   = "us-east-1"

# Enhanced security
enable_kms_encryption = true
enable_cloudtrail_logging = true

# Cost optimization
enable_intelligent_tiering = true
s3_lifecycle_enabled = true
s3_lifecycle_transition_days = 30

# Monitoring
enable_cloudwatch_alarms = true
notification_email = "admin@company.com"

# Glue configuration
glue_crawler_schedule = "cron(0 1 * * ? *)"  # Daily at 1 AM
glue_job_timeout = 120
```

### Development Environment

```hcl
# terraform.tfvars
project_name = "dev-analytics"
environment  = "dev"

# Minimal monitoring for dev
enable_cloudwatch_alarms = false
enable_kms_encryption = false

# Faster processing
glue_crawler_schedule = "cron(0 */6 * * ? *)"  # Every 6 hours
```

## Post-Deployment Steps

### 1. Verify Resource Creation

```bash
# Check all created resources
terraform output

# List S3 buckets
aws s3 ls | grep $(terraform output -raw resource_prefix)

# Check Glue database
aws glue get-database --name $(terraform output -raw glue_database_name)
```

### 2. Upload Sample Data

```bash
# Upload additional data files
aws s3 cp your-data.csv s3://$(terraform output -raw raw_data_bucket_name)/sales-data/

# The Lambda function will automatically trigger processing
```

### 3. Test Athena Queries

```bash
# Get sample queries from output
terraform output sample_athena_queries
```

### 4. Set Up QuickSight

1. Open [QuickSight Console](https://quicksight.aws.amazon.com/)
2. Create new data source with these settings:
   - **Type**: Amazon Athena
   - **Workgroup**: Use value from `terraform output athena_workgroup_name`
   - **Database**: Use value from `terraform output glue_database_name`
3. Create datasets from the processed tables:
   - `enriched_sales`
   - `monthly_sales`
   - `category_performance`
   - `customer_analysis`

## Monitoring and Troubleshooting

### CloudWatch Logs

```bash
# View Glue ETL job logs
aws logs describe-log-groups --log-group-name-prefix "/aws-glue/jobs"

# View Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda"
```

### Glue Job Monitoring

```bash
# Check job runs
aws glue get-job-runs --job-name $(terraform output -raw glue_etl_job_name)

# Check crawler status
aws glue get-crawler --name $(terraform output -raw glue_raw_crawler_name)
```

### Common Issues

1. **ETL Job Fails**: Check data schema compatibility in CloudWatch logs
2. **Crawler Not Finding Tables**: Verify S3 data format and location
3. **Permission Errors**: Review IAM roles and policies
4. **QuickSight Connection Issues**: Verify Athena workgroup permissions

## Cost Optimization

### Estimated Monthly Costs

| Service | Usage | Estimated Cost |
|---------|-------|----------------|
| S3 | 10GB storage | $0.25 |
| Glue | 10 ETL DPU-hours | $4.40 |
| Athena | 100 queries (1GB each) | $5.00 |
| Lambda | 1000 invocations | $0.20 |
| CloudWatch | Standard monitoring | $3.00 |
| **Total** | | **~$13/month** |

### Cost Optimization Features

- **S3 Intelligent Tiering**: Automatically moves data to cheaper storage classes
- **Lifecycle Policies**: Deletes old object versions
- **Athena Query Limits**: Prevents runaway query costs
- **Glue Job Bookmarks**: Processes only new data

## Security Features

### Data Protection

- **Encryption at Rest**: KMS encryption for S3 buckets (optional)
- **Encryption in Transit**: HTTPS/TLS for all API calls
- **Access Controls**: Least privilege IAM roles
- **Bucket Policies**: Block public access on all S3 buckets

### Monitoring

- **CloudTrail**: API call logging (optional)
- **CloudWatch Alarms**: Automated failure detection
- **VPC Flow Logs**: Network traffic monitoring (if deployed in VPC)

## Cleanup

To destroy all resources:

```bash
# Remove all objects from S3 buckets first
aws s3 rm s3://$(terraform output -raw raw_data_bucket_name) --recursive
aws s3 rm s3://$(terraform output -raw processed_data_bucket_name) --recursive
aws s3 rm s3://$(terraform output -raw athena_results_bucket_name) --recursive

# Destroy infrastructure
terraform destroy
```

## Advanced Configuration

### Custom ETL Script

To use a custom ETL script:

1. Modify `etl-script.py` with your transformations
2. Run `terraform apply` to update the S3 object

### Additional Data Sources

To add more data sources:

1. Add new crawler resources in `main.tf`
2. Update the ETL script to process additional tables
3. Modify variables as needed

### Multi-Environment Setup

For multiple environments, use Terraform workspaces:

```bash
# Create workspace
terraform workspace new production

# Deploy to specific workspace
terraform workspace select production
terraform apply -var-file="production.tfvars"
```

## Support and Troubleshooting

### Useful Commands

```bash
# Check resource status
terraform state list
terraform state show aws_glue_job.etl_job

# Refresh state
terraform refresh

# Import existing resources
terraform import aws_s3_bucket.example bucket-name
```

### Log Locations

- **Glue ETL Jobs**: `/aws-glue/jobs/output` and `/aws-glue/jobs/error`
- **Lambda Functions**: `/aws/lambda/function-name`
- **Crawler Logs**: `/aws-glue/crawlers`

### Documentation Links

- [AWS Glue Developer Guide](https://docs.aws.amazon.com/glue/latest/dg/)
- [Amazon Athena User Guide](https://docs.aws.amazon.com/athena/latest/ug/)
- [Amazon QuickSight User Guide](https://docs.aws.amazon.com/quicksight/latest/user/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)