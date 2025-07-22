# Infrastructure as Code for Building Data Lake Architectures with S3, Glue, and Athena

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Building Data Lake Architectures with S3, Glue, and Athena".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured with appropriate credentials
- AWS account with permissions for S3, Glue, Athena, and IAM services
- Basic understanding of SQL and data analytics concepts
- Sample datasets for testing (CSV, JSON, or Parquet files)
- Estimated cost: $20-50/month for moderate data volumes and query frequency

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI with CloudFormation permissions
- IAM permissions to create roles and policies

#### CDK TypeScript
- Node.js 18.x or later
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- TypeScript compiler

#### CDK Python
- Python 3.8 or later
- AWS CDK CLI installed (`pip install aws-cdk-lib`)
- pip package manager

#### Terraform
- Terraform 1.0 or later
- AWS provider for Terraform

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name data-lake-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=my-data-lake

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name data-lake-stack \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name data-lake-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk output
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk output
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
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

# The script will:
# 1. Create S3 buckets for data lake storage
# 2. Set up lifecycle policies for cost optimization
# 3. Create IAM roles for Glue services
# 4. Upload sample data and create Glue database
# 5. Create and run Glue crawlers for schema discovery
# 6. Create Glue ETL job for data transformation
# 7. Set up Amazon Athena for SQL analytics
```

## Architecture Overview

The deployed infrastructure includes:

- **S3 Buckets**: Data lake storage with raw, processed, and archive zones
- **S3 Lifecycle Policies**: Automated cost optimization through intelligent tiering
- **IAM Roles**: Secure access for Glue services with least privilege permissions
- **Glue Database**: Centralized metadata repository for data catalog
- **Glue Crawlers**: Automated schema discovery for CSV and JSON data
- **Glue ETL Jobs**: Serverless data transformation to Parquet format
- **Athena Workgroup**: Query isolation and result management
- **Sample Data**: Sales data (CSV) and web logs (JSON) for testing

## Customization

### Variables and Parameters

Each implementation supports customization through variables:

- **ProjectName**: Unique identifier for resource naming
- **DataLakeBucket**: Name for the main data lake S3 bucket
- **GlueDatabase**: Name for the Glue database
- **AthenaBucket**: Name for Athena query results bucket
- **Region**: AWS region for deployment
- **Environment**: Environment tag (dev, staging, prod)

### Sample Data

The implementations include sample datasets:
- **Sales Data**: CSV format with order information, customer data, and regional sales
- **Web Logs**: JSON format with user activity, page views, and session data

### Partitioning Strategy

Data is organized with year/month partitioning for optimal query performance:
```
s3://bucket/raw-zone/sales-data/year=2024/month=01/
s3://bucket/raw-zone/web-logs/year=2024/month=01/
```

## Post-Deployment Steps

1. **Verify Glue Crawlers**: Check that crawlers have successfully cataloged your data
2. **Test Athena Queries**: Run sample queries to validate the setup
3. **Monitor Costs**: Use CloudWatch to track S3 storage and Athena query costs
4. **Set Up Alerts**: Configure CloudWatch alarms for cost thresholds

### Sample Athena Queries

```sql
-- Sales summary by region
SELECT 
    region,
    COUNT(*) as total_orders,
    SUM(quantity * price) as total_revenue,
    AVG(price) as avg_price
FROM sales_data
GROUP BY region
ORDER BY total_revenue DESC;

-- Top products by revenue
SELECT 
    product_name,
    category,
    SUM(quantity * price) as revenue,
    COUNT(*) as order_count
FROM sales_data
GROUP BY product_name, category
ORDER BY revenue DESC
LIMIT 10;
```

## Cost Optimization

The infrastructure includes several cost optimization features:

- **S3 Lifecycle Policies**: Automatic transition to cheaper storage classes
- **Partitioning**: Reduces data scanned by Athena queries
- **Parquet Format**: Columnar storage for better compression and query performance
- **Athena Workgroups**: Query result caching and cost controls

## Security Features

- **IAM Roles**: Least privilege access for Glue services
- **S3 Encryption**: Server-side encryption for all data
- **VPC Endpoints**: Secure communication between services (when applicable)
- **Resource Tagging**: Consistent tagging for governance and billing

## Monitoring and Logging

- **CloudWatch Metrics**: Glue job execution and Athena query metrics
- **CloudWatch Logs**: ETL job logs and crawler execution logs
- **AWS CloudTrail**: API call logging for auditing
- **Cost Explorer**: Track and analyze spending patterns

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name data-lake-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name data-lake-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK (AWS)

```bash
# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# 1. Delete Athena workgroup and queries
# 2. Remove Glue resources (crawlers, jobs, database)
# 3. Clean up S3 buckets and objects
# 4. Remove IAM roles and policies
# 5. Clean up local temporary files
```

## Troubleshooting

### Common Issues

1. **Crawler Failures**: Check IAM permissions and S3 bucket policies
2. **Athena Query Errors**: Verify table schemas and data formats
3. **ETL Job Failures**: Check CloudWatch logs for detailed error messages
4. **Permission Denied**: Ensure IAM roles have necessary permissions

### Debugging Steps

1. **Check CloudWatch Logs**: Review Glue job and crawler logs
2. **Verify IAM Permissions**: Ensure roles have required policies attached
3. **Test S3 Access**: Confirm bucket permissions and object accessibility
4. **Validate Data Formats**: Check that data conforms to expected schemas

## Support and Documentation

- [AWS Glue Documentation](https://docs.aws.amazon.com/glue/)
- [Amazon Athena Documentation](https://docs.aws.amazon.com/athena/)
- [Amazon S3 Documentation](https://docs.aws.amazon.com/s3/)
- [AWS Data Lake Best Practices](https://docs.aws.amazon.com/whitepapers/latest/building-data-lakes/building-data-lakes.html)

For issues with this infrastructure code, refer to the original recipe documentation or the AWS service documentation.

## Advanced Features

### Extensions and Enhancements

1. **Real-time Streaming**: Add Kinesis Data Firehose for real-time data ingestion
2. **Data Quality**: Implement AWS Glue DataBrew for data profiling and quality checks
3. **Lake Formation**: Add fine-grained access controls with AWS Lake Formation
4. **Machine Learning**: Integrate with Amazon SageMaker for ML workflows
5. **Visualization**: Connect to Amazon QuickSight for business intelligence

### Performance Optimization

- **Columnar Formats**: Convert data to Parquet for better compression
- **Partitioning**: Implement appropriate partitioning strategies
- **Compression**: Use GZIP or Snappy compression for cost savings
- **Query Optimization**: Optimize Athena queries for better performance

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Please review and modify according to your organization's security and compliance requirements.