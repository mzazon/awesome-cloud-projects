# Infrastructure as Code for Cost-Optimized Analytics with S3 Tiering

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cost-Optimized Analytics with S3 Tiering".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements S3 Intelligent-Tiering with automatic archiving to optimize storage costs while maintaining analytics capabilities through Amazon Athena. The infrastructure includes:

- S3 bucket with Intelligent-Tiering configuration
- AWS Glue Data Catalog for metadata management
- Amazon Athena workgroup for cost-controlled analytics
- CloudWatch monitoring and cost anomaly detection
- Lifecycle policies for automatic tier transitions

## Prerequisites

- AWS CLI v2 installed and configured (or AWS CloudShell)
- Appropriate AWS permissions for:
  - S3 (bucket creation, intelligent-tiering configuration)
  - AWS Glue (database and table creation)
  - Amazon Athena (workgroup management)
  - CloudWatch (dashboard and metric creation)
  - Cost Explorer (anomaly detection)
- Basic understanding of S3 storage classes and SQL queries
- Estimated cost: $15-25/month for 100GB of data with mixed access patterns

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name cost-optimized-analytics \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=BucketPrefix,ParameterValue=analytics \
                ParameterKey=ArchiveTransitionDays,ParameterValue=90 \
                ParameterKey=DeepArchiveTransitionDays,ParameterValue=180

# Monitor deployment
aws cloudformation describe-stacks \
    --stack-name cost-optimized-analytics \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate.bat

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls
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

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Upload sample data (optional)
./scripts/upload-sample-data.sh
```

## Configuration Options

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| BucketPrefix | Prefix for S3 bucket name | analytics | Yes |
| ArchiveTransitionDays | Days before moving to Archive tier | 90 | No |
| DeepArchiveTransitionDays | Days before moving to Deep Archive | 180 | No |
| EnableCostAnomalyDetection | Enable cost anomaly detection | true | No |

### Terraform Variables

```hcl
# Example terraform.tfvars
bucket_prefix = "analytics"
archive_transition_days = 90
deep_archive_transition_days = 180
enable_cost_monitoring = true
athena_query_limit_gb = 1
```

### CDK Configuration

Both CDK implementations support environment variables:

```bash
export BUCKET_PREFIX=analytics
export ARCHIVE_DAYS=90
export DEEP_ARCHIVE_DAYS=180
export ENABLE_MONITORING=true
```

## Post-Deployment Steps

1. **Upload Sample Data**:
   ```bash
   # Create sample analytics data
   mkdir -p sample-data
   echo "timestamp,user_id,transaction_id,amount" > sample-data/transactions.csv
   echo "2024-01-01 10:00:00,user123,txn456,100.50" >> sample-data/transactions.csv
   
   # Upload to S3 with Intelligent-Tiering
   aws s3 cp sample-data/ s3://$(terraform output -raw bucket_name)/analytics-data/ \
       --recursive --storage-class INTELLIGENT_TIERING
   ```

2. **Test Athena Queries**:
   ```bash
   # Get workgroup name from outputs
   WORKGROUP=$(terraform output -raw athena_workgroup_name)
   
   # Run test query
   aws athena start-query-execution \
       --query-string "SELECT COUNT(*) FROM analytics_database.transaction_logs" \
       --work-group $WORKGROUP
   ```

3. **Monitor Cost Optimization**:
   ```bash
   # View CloudWatch dashboard
   DASHBOARD_URL=$(terraform output -raw cloudwatch_dashboard_url)
   echo "View dashboard at: $DASHBOARD_URL"
   ```

## Validation & Testing

### Verify S3 Configuration

```bash
# Check Intelligent-Tiering configuration
BUCKET_NAME=$(terraform output -raw bucket_name)
aws s3api get-bucket-intelligent-tiering-configuration \
    --bucket $BUCKET_NAME \
    --id cost-optimization-config
```

### Test Analytics Performance

```bash
# Execute sample analytics query
DATABASE_NAME=$(terraform output -raw glue_database_name)
WORKGROUP_NAME=$(terraform output -raw athena_workgroup_name)

QUERY_ID=$(aws athena start-query-execution \
    --query-string "SELECT user_id, COUNT(*) as transaction_count FROM $DATABASE_NAME.transaction_logs GROUP BY user_id LIMIT 10" \
    --work-group $WORKGROUP_NAME \
    --query 'QueryExecutionId' \
    --output text)

# Check query status
aws athena get-query-execution \
    --query-execution-id $QUERY_ID
```

### Monitor Storage Metrics

```bash
# View storage distribution across tiers
aws cloudwatch get-metric-statistics \
    --namespace AWS/S3 \
    --metric-name BucketSizeBytes \
    --dimensions Name=BucketName,Value=$BUCKET_NAME \
    --start-time $(date -d '7 days ago' -u +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 86400 \
    --statistics Average
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name cost-optimized-analytics

# Monitor deletion
aws cloudformation describe-stacks \
    --stack-name cost-optimized-analytics
```

### Using CDK

```bash
# Destroy the stack
cdk destroy

# Confirm deletion
cdk ls
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm removal
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Manual verification (if needed)
aws s3 ls | grep analytics
```

## Cost Optimization Features

### Intelligent-Tiering Benefits

- **Automatic Optimization**: Objects transition based on access patterns
- **No Retrieval Fees**: Instant access for archived data
- **Monitoring**: $0.0025 per 1,000 objects monthly
- **Savings**: Typically 20-40% cost reduction for mixed access patterns

### Storage Tier Transitions

1. **Frequent Access** → **Infrequent Access**: After 30 days of no access
2. **Infrequent Access** → **Archive Instant Access**: After 90 days (configurable)
3. **Archive** → **Deep Archive Access**: After 180 days (configurable)

### Query Cost Controls

- Athena workgroup with 1GB scan limit per query
- Query result caching enabled
- CloudWatch metrics for cost monitoring
- Cost anomaly detection for unusual spending

## Monitoring and Alerting

### CloudWatch Metrics

- S3 storage distribution by tier
- Athena query execution metrics
- Cost trends and anomalies
- Custom dashboard for visualization

### Cost Analysis

```bash
# Get cost breakdown by storage class
aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=USAGE_TYPE
```

## Troubleshooting

### Common Issues

1. **Intelligent-Tiering Not Active**:
   - Verify objects are larger than 128KB
   - Check configuration status
   - Ensure proper IAM permissions

2. **Athena Query Failures**:
   - Verify Glue table schema
   - Check S3 permissions
   - Validate data format

3. **High Costs**:
   - Review query patterns
   - Check for full table scans
   - Optimize with partitioning

### Debug Commands

```bash
# Check bucket policies
aws s3api get-bucket-policy --bucket $BUCKET_NAME

# Verify Glue table schema
aws glue get-table --database-name $DATABASE_NAME --name transaction_logs

# Review Athena query history
aws athena list-query-executions --work-group $WORKGROUP_NAME
```

## Security Considerations

- S3 bucket encryption enabled by default
- IAM roles follow least privilege principle
- VPC endpoints for private connectivity (optional)
- CloudTrail logging for audit compliance
- No public bucket access

## Performance Optimization

- Use columnar formats (Parquet) for better compression
- Implement partition projection for time-series data
- Enable query result caching
- Use appropriate Athena data types
- Consider data compression options

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS service documentation
3. Validate IAM permissions
4. Review CloudWatch logs for errors
5. Consult AWS support for service-specific issues

## Additional Resources

- [S3 Intelligent-Tiering Documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/intelligent-tiering.html)
- [Amazon Athena User Guide](https://docs.aws.amazon.com/athena/latest/ug/)
- [AWS Glue Developer Guide](https://docs.aws.amazon.com/glue/latest/dg/)
- [CloudWatch Metrics and Alarms](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/)