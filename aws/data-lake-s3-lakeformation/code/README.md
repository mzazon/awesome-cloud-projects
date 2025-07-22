# Infrastructure as Code for Data Lake Architectures with Lake Formation

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Data Lake Architectures with Lake Formation".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a secure, governed data lake using:

- **Amazon S3**: Scalable storage with three-tier architecture (Raw, Processed, Curated)
- **AWS Lake Formation**: Centralized governance and fine-grained access control
- **AWS Glue**: Data cataloging and schema discovery
- **IAM Roles**: Role-based access control for different user types
- **LF-Tags**: Scalable attribute-based access control
- **Data Cell Filters**: Column-level and row-level security
- **CloudTrail**: Comprehensive audit logging

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with administrative permissions for:
  - Lake Formation
  - S3
  - Glue
  - IAM
  - CloudTrail
  - CloudWatch Logs
- Understanding of data lake concepts and AWS analytics services
- Familiarity with JSON and IAM policies
- Estimated cost: $20-50 for 3-4 hours of resource usage

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name data-lake-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=DataLakeName,ParameterValue=mydatalake \
                 ParameterKey=DatabaseName,ParameterValue=sales_db

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name data-lake-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
# Navigate to CDK directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk list
```

### Using CDK Python

```bash
# Navigate to CDK directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

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

# Apply configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
aws lakeformation get-data-lake-settings
```

## Configuration Options

### CloudFormation Parameters

- `DataLakeName`: Unique name for your data lake (default: mydatalake)
- `DatabaseName`: Glue database name (default: sales_db)
- `EnableAuditLogging`: Enable CloudTrail logging (default: true)
- `DataClassification`: Default data classification level (default: Internal)

### CDK Configuration

Modify the configuration in `app.ts` (TypeScript) or `app.py` (Python):

```typescript
// CDK TypeScript example
const config = {
  dataLakeName: 'mydatalake',
  databaseName: 'sales_db',
  enableAuditLogging: true,
  department: 'Sales'
};
```

### Terraform Variables

Edit `terraform.tfvars` or provide variables via command line:

```bash
# Using tfvars file
echo 'data_lake_name = "mydatalake"' > terraform.tfvars
echo 'database_name = "sales_db"' >> terraform.tfvars

# Using command line
terraform apply -var="data_lake_name=mydatalake" -var="database_name=sales_db"
```

## Post-Deployment Setup

### 1. Upload Sample Data

```bash
# Set environment variables (replace with your actual bucket names)
export RAW_BUCKET="mydatalake-raw"
export PROCESSED_BUCKET="mydatalake-processed"
export CURATED_BUCKET="mydatalake-curated"

# Upload sample data
aws s3 cp sample_data/sales_data.csv s3://${RAW_BUCKET}/sales/
aws s3 cp sample_data/customer_data.csv s3://${RAW_BUCKET}/customers/
```

### 2. Run Glue Crawlers

```bash
# Start crawlers to discover data
aws glue start-crawler --name "sales-crawler"
aws glue start-crawler --name "customer-crawler"

# Monitor crawler status
aws glue get-crawler --name "sales-crawler"
```

### 3. Test Data Access

```bash
# Test Athena query (requires Athena setup)
aws athena start-query-execution \
    --query-string "SELECT COUNT(*) FROM sales_db.sales_sales_data" \
    --result-configuration OutputLocation=s3://${RAW_BUCKET}/athena-results/
```

## Security Features

### Fine-Grained Access Control

The implementation includes:

- **Role-Based Access**: Separate roles for data analysts, engineers, and administrators
- **Column-Level Security**: Data cell filters to protect PII data
- **Row-Level Security**: Filters based on geographic regions or departments
- **Tag-Based Access Control**: Scalable permissions using LF-Tags

### Data Classification

Data is classified using LF-Tags:

- **Public**: No restrictions
- **Internal**: Company-wide access
- **Confidential**: Restricted access
- **Restricted**: Highly sensitive data

### Audit and Compliance

- **CloudTrail Integration**: All API calls logged
- **Data Lineage**: Track data transformations
- **Access Monitoring**: Monitor who accessed what data
- **Compliance Reporting**: Generate audit reports

## Validation and Testing

### Verify Lake Formation Setup

```bash
# Check data lake settings
aws lakeformation get-data-lake-settings

# List registered resources
aws lakeformation list-resources

# Verify LF-Tags
aws lakeformation list-lf-tags
```

### Test Permissions

```bash
# Test different user roles
aws sts assume-role \
    --role-arn "arn:aws:iam::ACCOUNT:role/DataAnalystRole" \
    --role-session-name "test-session"

# Query data with assumed role
aws athena start-query-execution \
    --query-string "SELECT * FROM sales_db.sales_sales_data LIMIT 10"
```

### Validate Data Cell Filters

```bash
# List data cell filters
aws lakeformation list-data-cells-filter \
    --table CatalogId=ACCOUNT,DatabaseName=sales_db,Name=customer_customer_data
```

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**
   - Ensure Lake Formation permissions are granted
   - Check IAM policies for required permissions
   - Verify resource registration with Lake Formation

2. **Crawler Failures**
   - Check IAM role permissions for Glue crawler
   - Verify S3 bucket access permissions
   - Ensure data format compatibility

3. **Query Failures in Athena**
   - Verify table schema in Glue catalog
   - Check Lake Formation permissions
   - Ensure proper data format and location

### Debug Commands

```bash
# Check crawler logs
aws logs filter-log-events \
    --log-group-name /aws/glue/crawlers \
    --filter-pattern "ERROR"

# Verify IAM role trust relationships
aws iam get-role --role-name LakeFormationServiceRole

# Check CloudTrail logs
aws logs filter-log-events \
    --log-group-name /aws/cloudtrail/lake-formation \
    --filter-pattern "lakeformation"
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name data-lake-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name data-lake-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm deletion
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
aws s3 ls | grep mydatalake
```

### Manual Cleanup (if needed)

```bash
# Empty S3 buckets before deletion
aws s3 rm s3://mydatalake-raw --recursive
aws s3 rm s3://mydatalake-processed --recursive
aws s3 rm s3://mydatalake-curated --recursive

# Delete LF-Tags
aws lakeformation delete-lf-tag --tag-key "Department"
aws lakeformation delete-lf-tag --tag-key "Classification"

# Delete CloudWatch log groups
aws logs delete-log-group --log-group-name /aws/lakeformation/audit
```

## Cost Optimization

### Estimated Costs

- **S3 Storage**: $0.023/GB/month (Standard tier)
- **Glue Crawlers**: $0.44/hour per crawler
- **Athena Queries**: $5.00/TB scanned
- **CloudTrail**: $2.00/100,000 events
- **Lake Formation**: No additional charges

### Cost Optimization Tips

1. **Use S3 Lifecycle Policies**: Automatically transition data to cheaper storage classes
2. **Optimize Athena Queries**: Use partitioning and columnar formats
3. **Schedule Crawlers**: Run only when necessary
4. **Monitor Usage**: Use AWS Cost Explorer to track spending

## Advanced Features

### Cross-Account Data Sharing

```bash
# Share database with another account
aws lakeformation create-data-lake-settings \
    --data-lake-settings CreateDatabaseDefaultPermissions='[{
        "Principal": "arn:aws:iam::ACCOUNT2:root",
        "Permissions": ["DESCRIBE"]
    }]'
```

### ML Integration

```bash
# Create SageMaker feature store
aws sagemaker create-feature-group \
    --feature-group-name sales-features \
    --record-identifier-feature-name customer_id
```

### Real-time Data Processing

```bash
# Add Kinesis Data Firehose for real-time ingestion
aws firehose create-delivery-stream \
    --delivery-stream-name sales-stream \
    --s3-destination-configuration RoleARN=arn:aws:iam::ACCOUNT:role/firehose-role
```

## Best Practices

### Security

- Enable MFA for administrative users
- Use least privilege access principles
- Regularly review and audit permissions
- Encrypt data at rest and in transit
- Monitor access patterns and anomalies

### Performance

- Use partitioning for large datasets
- Optimize file sizes (128MB-1GB)
- Use columnar formats like Parquet
- Implement proper data lifecycle management
- Monitor and optimize query performance

### Governance

- Establish data quality standards
- Implement data lineage tracking
- Create data documentation and metadata
- Regular compliance audits
- Training for data users

## Support and Resources

### Documentation

- [AWS Lake Formation User Guide](https://docs.aws.amazon.com/lake-formation/latest/dg/)
- [AWS Glue Developer Guide](https://docs.aws.amazon.com/glue/latest/dg/)
- [Amazon S3 User Guide](https://docs.aws.amazon.com/s3/latest/userguide/)
- [AWS IAM User Guide](https://docs.aws.amazon.com/IAM/latest/UserGuide/)

### Community

- [AWS Lake Formation Forum](https://forums.aws.amazon.com/forum.jspa?forumID=356)
- [AWS Big Data Blog](https://aws.amazon.com/blogs/big-data/)
- [AWS Architecture Center](https://aws.amazon.com/architecture/)

### Professional Services

- AWS Professional Services for complex implementations
- AWS Training and Certification programs
- AWS Support plans for production workloads

## Contributing

For issues with this infrastructure code, please:

1. Check the troubleshooting section
2. Review AWS documentation
3. Consult the original recipe documentation
4. Contact your AWS support team

## License

This code is provided under the MIT License. See LICENSE file for details.