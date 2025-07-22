# Infrastructure as Code for Analytics-Optimized S3 Tables Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Analytics-Optimized S3 Tables Storage".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured (version 2.0 or later)
- Appropriate AWS permissions for S3 Tables, Athena, Glue, and QuickSight
- Node.js 18+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)
- Basic knowledge of SQL and data analytics concepts
- Understanding of Apache Iceberg table format fundamentals

> **Note**: S3 Tables is available in limited AWS regions. Check the [S3 Tables regions documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-tables-regions-quotas.html) for current availability.

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name s3-tables-analytics \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=TableBucketName,ParameterValue=analytics-tables-$(date +%s) \
                 ParameterKey=NamespaceName,ParameterValue=sales_analytics \
                 ParameterKey=TableName,ParameterValue=transaction_data

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name s3-tables-analytics \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name s3-tables-analytics \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy

# View outputs
npx cdk list
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv

# Activate virtual environment
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
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

# Check deployment status
./scripts/deploy.sh --status
```

## Architecture Overview

The infrastructure deploys:

- **S3 Table Bucket**: Purpose-built storage for Apache Iceberg tables
- **Table Namespace**: Logical organization for analytics tables
- **Iceberg Table**: High-performance table with automatic maintenance
- **AWS Glue Database**: Data catalog integration for metadata management
- **Amazon Athena Workgroup**: Interactive SQL querying environment
- **IAM Roles and Policies**: Secure access permissions
- **Sample Data Sources**: Test datasets for validation

## Configuration Options

### CloudFormation Parameters

- `TableBucketName`: Unique name for the S3 table bucket
- `NamespaceName`: Namespace for organizing tables (default: sales_analytics)
- `TableName`: Name of the Iceberg table (default: transaction_data)
- `GlueDatabaseName`: Glue catalog database name (default: s3_tables_analytics)

### CDK Configuration

Modify the stack parameters in `app.ts` (TypeScript) or `app.py` (Python):

```typescript
// CDK TypeScript example
const stack = new S3TablesAnalyticsStack(app, 'S3TablesAnalyticsStack', {
  tableBucketName: 'analytics-tables-' + Date.now(),
  namespaceName: 'sales_analytics',
  tableName: 'transaction_data',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});
```

### Terraform Variables

Customize deployment by modifying `terraform.tfvars`:

```hcl
table_bucket_name = "analytics-tables-unique-suffix"
namespace_name    = "sales_analytics"
table_name        = "transaction_data"
glue_database_name = "s3_tables_analytics"
aws_region        = "us-east-1"
```

## Validation & Testing

After deployment, validate the infrastructure:

### 1. Verify S3 Table Bucket

```bash
# List table buckets
aws s3tables list-table-buckets

# Get table bucket details
aws s3tables get-table-bucket --name <table-bucket-name>
```

### 2. Check Table Creation

```bash
# List namespaces
aws s3tables list-namespaces --table-bucket-arn <table-bucket-arn>

# List tables in namespace
aws s3tables list-tables \
    --table-bucket-arn <table-bucket-arn> \
    --namespace <namespace-name>
```

### 3. Test Athena Integration

```bash
# Execute test query
aws athena start-query-execution \
    --query-string "SHOW TABLES IN <glue-database-name>" \
    --work-group <athena-workgroup-name> \
    --result-configuration OutputLocation=s3://<results-bucket>/
```

### 4. Validate Glue Catalog

```bash
# Check database creation
aws glue get-database --name <glue-database-name>

# List tables in database
aws glue get-tables --database-name <glue-database-name>
```

## Cost Considerations

Estimated monthly costs for this implementation:

- **S3 Tables Storage**: ~$35.37 per TB per month
- **Athena Queries**: $5 per TB of data scanned
- **AWS Glue Crawlers**: $0.44 per DPU-hour
- **QuickSight**: Starting at $9 per user per month

> **Tip**: Use S3 Tables' automatic optimization features to reduce storage costs and improve query performance over time.

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name s3-tables-analytics

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name s3-tables-analytics \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Destroy the stack
cd cdk-typescript/  # or cdk-python/
npx cdk destroy     # or cdk destroy for Python
```

### Using Terraform

```bash
# Destroy infrastructure
cd terraform/
terraform destroy

# Confirm destruction
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
./scripts/destroy.sh --verify
```

## Security Best Practices

This implementation follows AWS security best practices:

- **Least Privilege IAM**: Roles and policies grant minimum required permissions
- **Resource-Based Policies**: S3 table bucket policies control service access
- **Encryption**: All data encrypted at rest and in transit
- **VPC Endpoints**: Private connectivity for AWS services (where applicable)
- **Access Logging**: CloudTrail integration for audit trails

## Troubleshooting

### Common Issues

1. **S3 Tables Not Available**: Verify your region supports S3 Tables
2. **Permission Errors**: Check IAM roles and policies
3. **Athena Query Failures**: Verify Glue catalog integration
4. **QuickSight Connection Issues**: Ensure proper data source configuration

### Debug Commands

```bash
# Check AWS CLI configuration
aws sts get-caller-identity

# Verify region support for S3 Tables
aws s3tables list-table-buckets --region <your-region>

# Check CloudFormation events
aws cloudformation describe-stack-events --stack-name s3-tables-analytics

# View Terraform state
terraform show

# CDK diff to see changes
npx cdk diff  # or cdk diff for Python
```

## Advanced Configuration

### Multi-Region Setup

For multi-region analytics, modify the templates to include:

- Cross-region replication configuration
- Regional Athena workgroups
- Distributed QuickSight datasets

### Enhanced Security

Add these security enhancements:

- AWS KMS customer-managed keys
- VPC endpoints for private connectivity
- Enhanced CloudTrail logging
- AWS Config compliance rules

### Performance Optimization

Optimize for high-performance analytics:

- Configure S3 Tables maintenance schedules
- Implement data partitioning strategies
- Set up Athena result caching
- Configure QuickSight SPICE refresh schedules

## Integration with Existing Infrastructure

### Data Pipeline Integration

Connect to existing data pipelines:

- AWS Glue ETL jobs for data transformation
- Amazon Kinesis for real-time ingestion
- AWS Lambda for event-driven processing
- Amazon EventBridge for workflow orchestration

### Monitoring and Alerting

Add comprehensive monitoring:

- CloudWatch metrics for S3 Tables
- Athena query performance monitoring
- Glue job execution tracking
- QuickSight usage analytics

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../analytics-optimized-data-storage-s3-tables.md)
2. Review AWS service documentation:
   - [S3 Tables User Guide](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-tables.html)
   - [Athena User Guide](https://docs.aws.amazon.com/athena/latest/ug/)
   - [Glue Developer Guide](https://docs.aws.amazon.com/glue/latest/dg/)
   - [QuickSight User Guide](https://docs.aws.amazon.com/quicksight/latest/user/)
3. Check AWS service health dashboard
4. Review CloudFormation/CDK/Terraform logs for deployment issues

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Follow AWS Well-Architected Framework principles
3. Update documentation for any configuration changes
4. Validate security implications of modifications
5. Test cleanup procedures thoroughly

---

**Last Updated**: 2025-07-12  
**Recipe Version**: 1.0  
**Infrastructure Code Version**: 1.0