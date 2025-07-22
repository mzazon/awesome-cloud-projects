# Infrastructure as Code for Analytics-Ready S3 Tables Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Analytics-Ready S3 Tables Storage".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys:
- Amazon S3 Table Bucket with Apache Iceberg format support
- S3 Tables namespace for logical data organization
- Sample customer events table with optimized schema
- Amazon Athena workgroup for SQL queries
- AWS Glue Data Catalog integration
- IAM roles and policies for secure access

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with administrator permissions for:
  - Amazon S3 and S3 Tables
  - Amazon Athena
  - AWS Glue Data Catalog
  - IAM role creation
- For CDK deployments: Node.js 18+ or Python 3.8+
- For Terraform: Terraform 1.5+ installed
- Basic understanding of Apache Iceberg table format
- Estimated cost: $5-15 for testing (table storage, queries, and Glue requests)

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name s3-tables-analytics-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=analytics-demo

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name s3-tables-analytics-stack \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name s3-tables-analytics-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to TypeScript CDK directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters projectName=analytics-demo

# View outputs
cdk list
```

### Using CDK Python

```bash
# Navigate to Python CDK directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters projectName=analytics-demo

# View outputs
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
terraform plan -var="project_name=analytics-demo"

# Apply the configuration
terraform apply -var="project_name=analytics-demo"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow the prompts and wait for completion
# Script will output resource ARNs and connection details
```

## Configuration Options

### Common Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `project_name` | Project identifier for resource naming | `analytics-demo` | No |
| `aws_region` | AWS region for deployment | Current CLI region | No |
| `table_bucket_name` | Name for S3 Table Bucket | `analytics-data-{random}` | No |
| `namespace_name` | Namespace for logical organization | `analytics_data` | No |
| `enable_encryption` | Enable server-side encryption | `true` | No |

### Environment Variables

Set these environment variables before deployment:

```bash
export AWS_REGION=us-east-1
export PROJECT_NAME=my-analytics-project
export ENABLE_POINT_IN_TIME_RECOVERY=true
```

## Post-Deployment Steps

After successful deployment, follow these steps to validate your environment:

### 1. Verify S3 Tables Resources

```bash
# List table buckets
aws s3tables list-table-buckets

# Check namespace
export TABLE_BUCKET_ARN=$(aws cloudformation describe-stacks \
    --stack-name s3-tables-analytics-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`TableBucketArn`].OutputValue' \
    --output text)

aws s3tables list-namespaces \
    --table-bucket-arn $TABLE_BUCKET_ARN
```

### 2. Create Sample Table Schema

```bash
# Execute DDL to create sample table
export WORKGROUP_NAME=$(aws cloudformation describe-stacks \
    --stack-name s3-tables-analytics-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`AthenaWorkgroup`].OutputValue' \
    --output text)

aws athena start-query-execution \
    --query-string "CREATE TABLE IF NOT EXISTS s3tablescatalog.analytics_data.customer_events (
        event_id STRING,
        customer_id STRING,
        event_type STRING,
        event_timestamp TIMESTAMP,
        product_category STRING,
        amount DECIMAL(10,2),
        session_id STRING,
        user_agent STRING,
        event_date DATE
    )
    USING ICEBERG
    PARTITIONED BY (event_date)" \
    --work-group $WORKGROUP_NAME
```

### 3. Insert Sample Data

```bash
# Insert test data
aws athena start-query-execution \
    --query-string "INSERT INTO s3tablescatalog.analytics_data.customer_events VALUES
    ('evt_001', 'cust_12345', 'page_view', TIMESTAMP '2025-01-15 10:30:00', 'electronics', 0.00, 'sess_abc123', 'Mozilla/5.0', DATE '2025-01-15'),
    ('evt_002', 'cust_12345', 'add_to_cart', TIMESTAMP '2025-01-15 10:35:00', 'electronics', 299.99, 'sess_abc123', 'Mozilla/5.0', DATE '2025-01-15'),
    ('evt_003', 'cust_67890', 'purchase', TIMESTAMP '2025-01-15 11:00:00', 'clothing', 89.99, 'sess_def456', 'Chrome/100.0', DATE '2025-01-15')" \
    --work-group $WORKGROUP_NAME
```

### 4. Run Analytics Queries

```bash
# Execute sample analytics query
aws athena start-query-execution \
    --query-string "SELECT event_type, COUNT(*) as event_count, AVG(amount) as avg_amount 
                    FROM s3tablescatalog.analytics_data.customer_events 
                    WHERE event_date = DATE '2025-01-15' 
                    GROUP BY event_type" \
    --work-group $WORKGROUP_NAME
```

## Monitoring and Observability

### CloudWatch Metrics

Monitor your S3 Tables deployment with these key metrics:
- S3 Tables storage usage
- Athena query execution time
- Glue Data Catalog requests
- Query success/failure rates

### Cost Monitoring

Set up cost alerts for:
- S3 Tables storage costs
- Athena query execution costs
- Data transfer charges
- Glue Data Catalog API requests

## Security Considerations

This deployment implements several security best practices:

- **Encryption at Rest**: All data encrypted using AWS managed keys
- **IAM Least Privilege**: Granular permissions for each service
- **Network Security**: VPC endpoints for secure service communication
- **Access Logging**: CloudTrail integration for audit trails
- **Data Governance**: Lake Formation integration for fine-grained access control

### Additional Security Hardening

Consider implementing these additional security measures:

```bash
# Enable CloudTrail for API logging
aws cloudtrail create-trail \
    --name s3-tables-audit-trail \
    --s3-bucket-name your-audit-bucket

# Set up Config rules for compliance monitoring
aws configservice put-config-rule \
    --config-rule '{
        "ConfigRuleName": "s3-tables-encryption-enabled",
        "Source": {
            "Owner": "AWS",
            "SourceIdentifier": "S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED"
        }
    }'
```

## Troubleshooting

### Common Issues

1. **Table Bucket Creation Fails**
   - Verify S3 Tables is available in your region
   - Check IAM permissions for S3 Tables operations
   - Ensure unique bucket naming

2. **Athena Queries Fail**
   - Verify workgroup configuration
   - Check Glue Data Catalog permissions
   - Validate query syntax for Iceberg tables

3. **Integration Issues**
   - Verify AWS Glue service role permissions
   - Check VPC endpoint configurations
   - Validate cross-service IAM policies

### Debug Commands

```bash
# Check S3 Tables service status
aws s3tables list-table-buckets --region $AWS_REGION

# Verify Athena workgroup
aws athena get-work-group --work-group $WORKGROUP_NAME

# Check Glue catalog integration
aws glue get-databases --catalog-id $AWS_ACCOUNT_ID

# Validate IAM permissions
aws iam simulate-principal-policy \
    --policy-source-arn $ROLE_ARN \
    --action-names s3tables:CreateTable \
    --resource-arns '*'
```

## Performance Optimization

### Query Performance

- Use partitioning on frequently filtered columns (e.g., date)
- Leverage Iceberg's automatic optimization features
- Consider clustering for high-cardinality columns
- Monitor query patterns and adjust table structure accordingly

### Cost Optimization

- Set up lifecycle policies for Athena result buckets
- Use S3 Tables' automatic optimization to reduce storage costs
- Monitor query patterns to optimize workgroup settings
- Implement query result caching where appropriate

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name s3-tables-analytics-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name s3-tables-analytics-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Navigate to appropriate CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_name=analytics-demo"

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts for resource deletion confirmation
```

### Manual Cleanup (if needed)

If automated cleanup fails, manually remove resources in this order:

1. Delete S3 Tables and namespaces
2. Remove Athena workgroups
3. Delete Glue databases and tables
4. Remove IAM roles and policies
5. Delete S3 buckets (including query results)

## Advanced Usage

### Multi-Environment Deployment

Deploy to multiple environments using parameter overrides:

```bash
# Development environment
terraform apply -var="project_name=analytics-dev" -var="environment=dev"

# Production environment
terraform apply -var="project_name=analytics-prod" -var="environment=prod"
```

### Integration with CI/CD

Example GitHub Actions workflow:

```yaml
name: Deploy S3 Tables Analytics
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-region: us-east-1
      - name: Deploy Infrastructure
        run: |
          cd terraform/
          terraform init
          terraform apply -auto-approve
```

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review AWS S3 Tables documentation
3. Consult the original recipe documentation
4. Check AWS service health dashboard
5. Review CloudFormation/CDK/Terraform logs for specific error messages

## Contributing

To improve this infrastructure code:

1. Test changes in a separate AWS account
2. Validate with multiple IaC tools
3. Update documentation accordingly
4. Follow AWS security best practices
5. Test cleanup procedures thoroughly

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Refer to your organization's policies for production usage guidelines.