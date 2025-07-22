# Infrastructure as Code for Data Warehousing Solutions with Redshift

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Data Warehousing Solutions with Redshift".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a complete data warehousing infrastructure using:

- Amazon Redshift Serverless (Namespace and Workgroup)
- S3 bucket for data storage
- IAM roles with appropriate permissions
- CloudWatch monitoring integration
- Sample data and analytical queries

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for creating:
  - Redshift Serverless resources
  - S3 buckets
  - IAM roles and policies
  - CloudWatch resources
- For CDK deployments: Node.js 18+ or Python 3.8+
- For Terraform deployments: Terraform 1.0+
- Estimated cost: $0.50-$2.00 per hour for compute resources (only when queries are running)

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name redshift-data-warehouse \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=NamespaceNameSuffix,ParameterValue=$(date +%s) \
        ParameterKey=AdminPassword,ParameterValue=TempPassword123!

# Wait for deployment to complete
aws cloudformation wait stack-create-complete \
    --stack-name redshift-data-warehouse

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name redshift-data-warehouse \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this account/region)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy

# View stack outputs
npx cdk list --long
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack outputs
cdk list --long
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

# The script will output connection details and sample queries
```

## Post-Deployment Steps

After infrastructure deployment, complete these steps to fully utilize your data warehouse:

### 1. Connect to Query Editor v2

1. Navigate to the Amazon Redshift console
2. Select "Query Editor v2"
3. Connect to your workgroup using the admin credentials
4. Database: `sampledb`
5. Username: `awsuser`
6. Password: (as specified during deployment)

### 2. Create Sample Tables

Execute the following SQL to create sample tables:

```sql
CREATE TABLE sales (
    order_id INTEGER,
    customer_id INTEGER,
    product_id INTEGER,
    quantity INTEGER,
    price DECIMAL(10,2),
    order_date DATE
);

CREATE TABLE customers (
    customer_id INTEGER,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    email VARCHAR(100),
    city VARCHAR(50),
    state VARCHAR(2)
);
```

### 3. Load Sample Data

Use the COPY command to load data from the automatically created S3 bucket:

```sql
-- Get the S3 bucket name from your deployment outputs
COPY sales FROM 's3://[YOUR-BUCKET-NAME]/data/sales_data.csv'
IAM_ROLE '[YOUR-IAM-ROLE-ARN]'
CSV
IGNOREHEADER 1;

COPY customers FROM 's3://[YOUR-BUCKET-NAME]/data/customer_data.csv'
IAM_ROLE '[YOUR-IAM-ROLE-ARN]'
CSV
IGNOREHEADER 1;
```

### 4. Run Analytical Queries

Test your data warehouse with these sample queries:

```sql
-- Sales summary by customer
SELECT 
    c.first_name,
    c.last_name,
    c.city,
    COUNT(s.order_id) as total_orders,
    SUM(s.quantity * s.price) as total_revenue
FROM sales s
JOIN customers c ON s.customer_id = c.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name, c.city
ORDER BY total_revenue DESC;

-- Daily sales trend
SELECT 
    order_date,
    COUNT(order_id) as daily_orders,
    SUM(quantity * price) as daily_revenue
FROM sales
GROUP BY order_date
ORDER BY order_date;
```

## Configuration Options

### Environment Variables (for Bash Scripts)

The bash deployment script supports these environment variables:

```bash
export AWS_REGION="us-east-1"              # Target AWS region
export NAMESPACE_PREFIX="data-warehouse"    # Namespace name prefix
export WORKGROUP_PREFIX="analytics"        # Workgroup name prefix
export ADMIN_PASSWORD="YourSecurePassword"  # Admin password
export BASE_CAPACITY="128"                 # Initial compute capacity (RPUs)
```

### Terraform Variables

Customize your deployment by modifying `terraform.tfvars`:

```hcl
aws_region = "us-east-1"
namespace_name = "my-data-warehouse"
workgroup_name = "my-workgroup"
admin_password = "SecurePassword123!"
base_capacity = 128
publicly_accessible = true
```

### CDK Configuration

For CDK deployments, modify the configuration in the respective app files:

**TypeScript**: Edit values in `app.ts`
**Python**: Edit values in `app.py`

## Monitoring and Observability

The deployed infrastructure includes CloudWatch integration for monitoring:

- **Query Performance**: Monitor query execution times and resource utilization
- **Cost Tracking**: Track Redshift Processing Units (RPUs) consumption
- **Data Loading**: Monitor COPY command performance and errors
- **Security Events**: Track authentication and authorization events

Access monitoring through:

1. Amazon Redshift console → Performance tab
2. CloudWatch console → Metrics → AWS/Redshift-Serverless
3. AWS Cost Explorer for cost analysis

## Security Considerations

The deployed infrastructure implements security best practices:

- **IAM Roles**: Least privilege access for Redshift to S3
- **Encryption**: Data encrypted at rest and in transit
- **Network Security**: Configurable public/private access
- **Audit Logging**: CloudTrail integration for API calls
- **Password Policy**: Strong password requirements for admin user

### Production Security Enhancements

For production deployments, consider:

1. **VPC Configuration**: Deploy in private subnets
2. **Enhanced Monitoring**: Enable detailed query logging
3. **Multi-Factor Authentication**: Use IAM roles with MFA
4. **Data Classification**: Implement column-level security
5. **Network Isolation**: Use VPC endpoints for S3 access

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name redshift-data-warehouse

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name redshift-data-warehouse
```

### Using CDK (AWS)

```bash
# Destroy CDK stack
npx cdk destroy  # For TypeScript
# or
cdk destroy      # For Python

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

# Follow prompts to confirm resource deletion
```

## Troubleshooting

### Common Issues

1. **Namespace Creation Fails**
   - Verify IAM permissions for Redshift Serverless
   - Check for existing namespace with same name
   - Ensure AWS region supports Redshift Serverless

2. **Data Loading Errors**
   - Verify IAM role has S3 read permissions
   - Check S3 bucket exists and contains data files
   - Validate CSV format and encoding

3. **Connection Issues**
   - Verify workgroup is publicly accessible (if needed)
   - Check security group settings
   - Confirm admin credentials are correct

4. **Query Performance**
   - Monitor RPU utilization in CloudWatch
   - Consider increasing base capacity for complex queries
   - Optimize table design with sort keys and distribution keys

### Getting Help

- Review the [Amazon Redshift Serverless documentation](https://docs.aws.amazon.com/redshift/latest/mgmt/working-with-serverless.html)
- Check the [AWS Redshift troubleshooting guide](https://docs.aws.amazon.com/redshift/latest/mgmt/troubleshooting.html)
- Monitor CloudWatch logs for detailed error messages
- Use AWS Support for production issues

## Customization

### Adding More Data Sources

Extend the solution by:

1. Creating additional S3 prefixes for different data types
2. Adding more IAM policies for cross-account data access
3. Implementing AWS Glue for ETL processing
4. Connecting to Amazon Kinesis for real-time data

### Performance Optimization

For large-scale deployments:

1. **Table Design**: Use appropriate distribution and sort keys
2. **Workload Management**: Configure query queues and priorities
3. **Materialized Views**: Pre-aggregate frequently accessed data
4. **Result Caching**: Enable query result caching for repeated queries

### Integration Options

Connect your data warehouse to:

- **Amazon QuickSight**: For business intelligence dashboards
- **Amazon SageMaker**: For machine learning workflows
- **AWS Glue**: For automated ETL processes
- **Third-party BI Tools**: Tableau, Power BI, Looker

## Cost Optimization

### Redshift Serverless Pricing

- **Compute**: Pay per RPU-hour when processing queries
- **Storage**: Pay per GB stored per month
- **No charges**: When no queries are running

### Cost Management Tips

1. **Right-size Base Capacity**: Start with 128 RPUs and adjust based on usage
2. **Query Optimization**: Write efficient SQL to reduce processing time
3. **Data Lifecycle**: Use S3 lifecycle policies for infrequently accessed data
4. **Monitoring**: Set up cost alerts using AWS Budgets
5. **Scheduled Queries**: Use Amazon EventBridge for automated query scheduling

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check the AWS Redshift Serverless documentation
3. Consult CloudWatch logs for detailed error information
4. Contact AWS Support for production issues

## License

This infrastructure code is provided as-is under the MIT License. See the recipe documentation for full terms and conditions.