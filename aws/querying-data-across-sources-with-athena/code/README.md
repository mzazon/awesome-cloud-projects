# Infrastructure as Code for Querying Data Across Sources with Athena

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Querying Data Across Sources with Athena".

## Overview

This solution deploys a complete serverless analytics platform using Amazon Athena Federated Query to enable SQL queries across multiple data sources including Amazon RDS MySQL, DynamoDB, and S3 without ETL processes. The infrastructure creates data source connectors, configures federated catalogs, and establishes the foundation for cross-platform analytics.

## Architecture Components

- **Amazon Athena**: Serverless query engine for federated analytics
- **AWS Lambda**: Data source connectors (MySQL, DynamoDB)
- **Amazon RDS**: MySQL database for relational data
- **Amazon DynamoDB**: NoSQL database for operational data
- **Amazon S3**: Storage for query results and spill data
- **Amazon VPC**: Network isolation for secure database connectivity
- **IAM Roles**: Secure access control for all components

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### General Requirements

- AWS CLI installed and configured (version 2.0 or later)
- AWS account with appropriate permissions for:
  - Athena, Lambda, S3, RDS, DynamoDB, VPC, IAM
  - CloudFormation (for CloudFormation/CDK deployments)
  - Serverless Application Repository access
- Basic understanding of SQL and data analytics concepts

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI with CloudFormation permissions
- Ability to create IAM roles and policies

#### CDK (TypeScript)
- Node.js 18.x or later
- AWS CDK CLI (`npm install -g aws-cdk`)
- TypeScript (`npm install -g typescript`)

#### CDK (Python)
- Python 3.8 or later
- AWS CDK CLI (`pip install aws-cdk-lib`)
- Virtual environment recommended

#### Terraform
- Terraform 1.0 or later
- AWS provider for Terraform

### Estimated Costs

- RDS MySQL (db.t3.micro): ~$15-25/month
- Lambda executions: ~$1-5/month (based on query frequency)
- S3 storage: ~$1-3/month
- Athena queries: $5 per TB of data scanned
- DynamoDB: ~$1-3/month (provisioned capacity)

> **Note**: Most costs are variable based on usage. Consider using AWS Cost Explorer to monitor expenses.

## Quick Start

### Using CloudFormation

```bash
# Deploy the complete infrastructure
aws cloudformation create-stack \
    --stack-name athena-federated-analytics \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=DatabasePassword,ParameterValue=YourSecurePassword123!

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name athena-federated-analytics

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name athena-federated-analytics \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters DatabasePassword=YourSecurePassword123!

# View outputs
cdk list
```

### Using CDK Python

```bash
# Navigate to CDK directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters DatabasePassword=YourSecurePassword123!

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

# The script will prompt for required parameters
# and guide you through the deployment process
```

## Configuration

### Key Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `DatabasePassword` | Master password for RDS MySQL instance | - | Yes |
| `DatabaseInstanceClass` | RDS instance class | `db.t3.micro` | No |
| `VpcCidr` | CIDR block for VPC | `10.0.0.0/16` | No |
| `SpillBucketName` | S3 bucket for connector spill data | Auto-generated | No |
| `ResultsBucketName` | S3 bucket for query results | Auto-generated | No |
| `LambdaMemorySize` | Memory allocation for Lambda connectors | `3008` | No |
| `LambdaTimeout` | Timeout for Lambda connectors (seconds) | `900` | No |

### Environment Variables

The following environment variables can be set to customize the deployment:

```bash
export AWS_REGION=us-east-1
export DB_INSTANCE_CLASS=db.t3.micro
export LAMBDA_MEMORY_SIZE=3008
export ENABLE_MULTI_AZ=false
```

## Post-Deployment Steps

### 1. Verify Infrastructure

```bash
# Check Athena data catalogs
aws athena list-data-catalogs

# Verify Lambda functions
aws lambda list-functions --query 'Functions[?contains(FunctionName, `athena`)]'

# Check RDS instance status
aws rds describe-db-instances --query 'DBInstances[0].DBInstanceStatus'
```

### 2. Load Sample Data

```bash
# The deployment includes sample data loading
# Verify sample data exists in RDS
aws rds describe-db-instances \
    --db-instance-identifier $(terraform output -raw db_instance_id) \
    --query 'DBInstances[0].Endpoint.Address'

# Check DynamoDB table
aws dynamodb scan --table-name $(terraform output -raw dynamodb_table_name) \
    --query 'Items[*]'
```

### 3. Execute Test Queries

```bash
# Create a test federated query
aws athena start-query-execution \
    --query-string "SELECT COUNT(*) FROM mysql_catalog.analytics_db.sample_orders" \
    --work-group "federated-analytics" \
    --result-configuration OutputLocation=s3://$(terraform output -raw results_bucket_name)/
```

## Usage Examples

### Basic Federated Query

```sql
-- Query data from MySQL
SELECT * FROM mysql_catalog.analytics_db.sample_orders
WHERE order_date >= '2024-01-01';
```

### Cross-Source Join

```sql
-- Join MySQL and DynamoDB data
SELECT 
    o.order_id,
    o.customer_id,
    o.product_name,
    o.price,
    t.status,
    t.tracking_number
FROM mysql_catalog.analytics_db.sample_orders o
LEFT JOIN dynamodb_catalog.default.Orders t
ON CAST(o.order_id AS VARCHAR) = t.order_id;
```

### Analytical Aggregations

```sql
-- Revenue analysis by shipment status
SELECT 
    shipment_status,
    COUNT(*) as order_count,
    SUM(total_amount) as total_revenue,
    AVG(total_amount) as avg_order_value
FROM default.order_analytics
GROUP BY shipment_status
ORDER BY total_revenue DESC;
```

## Monitoring and Troubleshooting

### CloudWatch Logs

Monitor Lambda connector execution:

```bash
# View MySQL connector logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/athena-mysql-connector"

# View DynamoDB connector logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/athena-dynamodb-connector"
```

### Query Performance

Monitor Athena query performance:

```bash
# Get query execution details
aws athena get-query-execution --query-execution-id <query-id> \
    --query 'QueryExecution.Statistics'
```

### Common Issues

1. **Connection Timeouts**: Increase Lambda timeout and memory settings
2. **VPC Connectivity**: Ensure security groups allow MySQL access (port 3306)
3. **IAM Permissions**: Verify Lambda execution roles have necessary permissions
4. **Spill Bucket Access**: Ensure connectors can read/write to spill bucket

## Security Considerations

### Network Security

- RDS instance deployed in private subnets
- Security groups restrict access to necessary ports only
- VPC endpoints can be added for enhanced security

### Access Control

- Lambda functions use least-privilege IAM roles
- Database credentials stored securely
- S3 buckets configured with appropriate access policies

### Data Encryption

- RDS encryption at rest enabled
- DynamoDB encryption at rest enabled
- S3 buckets configured with default encryption

## Performance Optimization

### Connector Optimization

- Increase Lambda memory for better performance
- Use appropriate timeout values
- Enable connection pooling when available

### Query Optimization

- Use predicate pushdown for efficient filtering
- Leverage partition pruning when applicable
- Monitor data scanned metrics

### Cost Optimization

- Monitor Lambda execution costs
- Optimize S3 storage classes for spill data
- Consider reserved capacity for frequently accessed data

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name athena-federated-analytics

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name athena-federated-analytics
```

### Using CDK

```bash
# Destroy the stack
cd cdk-typescript/  # or cdk-python/
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup Verification

After running automated cleanup, verify the following resources are removed:

```bash
# Check S3 buckets
aws s3 ls | grep athena-federated

# Check Lambda functions
aws lambda list-functions --query 'Functions[?contains(FunctionName, `athena`)]'

# Check RDS instances
aws rds describe-db-instances --query 'DBInstances[?contains(DBInstanceIdentifier, `athena`)]'

# Check DynamoDB tables
aws dynamodb list-tables --query 'TableNames[?contains(@, `Orders`)]'
```

## Customization

### Adding New Data Sources

1. Deploy additional connectors from the Serverless Application Repository
2. Create new data catalogs in Athena
3. Update IAM permissions for cross-source access
4. Test connectivity with sample queries

### Scaling Configuration

- Adjust Lambda memory and timeout settings
- Modify RDS instance class for higher performance
- Configure DynamoDB auto-scaling
- Implement connection pooling for high-frequency queries

### Advanced Features

- Enable AWS X-Ray tracing for debugging
- Add CloudWatch alarms for monitoring
- Implement data lineage tracking
- Set up automated backup strategies

## Integration with BI Tools

### Amazon QuickSight

```bash
# Create QuickSight data source
aws quicksight create-data-source \
    --aws-account-id $(aws sts get-caller-identity --query Account --output text) \
    --data-source-id athena-federated-source \
    --name "Athena Federated Analytics" \
    --type ATHENA
```

### Third-Party Tools

- Configure JDBC/ODBC connections to Athena
- Use Athena's standard SQL interface
- Leverage federated views for simplified access

## Support and Resources

### Documentation

- [Amazon Athena Federated Query Documentation](https://docs.aws.amazon.com/athena/latest/ug/connect-to-a-data-source.html)
- [AWS Lambda Connectors](https://github.com/awslabs/aws-athena-query-federation)
- [Athena Query Federation SDK](https://github.com/awslabs/aws-athena-query-federation/tree/master/athena-federation-sdk)

### Community Resources

- [AWS Athena Forums](https://forums.aws.amazon.com/forum.jspa?forumID=242)
- [Stack Overflow - Amazon Athena](https://stackoverflow.com/questions/tagged/amazon-athena)
- [AWS Samples - Athena](https://github.com/aws-samples?q=athena)

### Getting Help

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review AWS CloudFormation/CDK/Terraform documentation
3. Consult the original recipe documentation
4. Contact AWS Support for service-specific issues

## Contributing

To contribute improvements to this infrastructure code:

1. Fork the repository
2. Create a feature branch
3. Test your changes thoroughly
4. Submit a pull request with detailed description

## License

This infrastructure code is provided under the MIT License. See LICENSE file for details.