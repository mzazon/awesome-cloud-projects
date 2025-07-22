# Infrastructure as Code for Data Lake Fine-Grained Access Control

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Data Lake Fine-Grained Access Control".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured (or AWS CloudShell)
- AWS account with administrative access to Lake Formation, IAM, S3, and Glue services
- Appropriate IAM permissions for resource creation:
  - `AWSLakeFormationDataAdmin` or equivalent permissions
  - IAM role creation and management permissions
  - S3 bucket creation and management permissions
  - AWS Glue database and table management permissions
- Basic understanding of data lake concepts and AWS IAM permissions
- Knowledge of SQL query syntax for testing access controls

## Estimated Costs

- **S3 Storage**: $0.023 per GB/month for Standard storage
- **AWS Glue Data Catalog**: $1.00 per 100,000 requests
- **Lake Formation**: No additional charges beyond underlying services
- **Testing Resources**: Approximately $10-20 for complete testing scenario

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name lake-formation-fgac-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=DataLakeBucketName,ParameterValue=my-data-lake-bucket-$(date +%s) \
    --capabilities CAPABILITY_IAM

# Wait for stack completion
aws cloudformation wait stack-create-complete \
    --stack-name lake-formation-fgac-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name lake-formation-fgac-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# Get stack outputs
cdk ls --long
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# Get stack outputs
cdk ls --long
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan

# Apply the configuration
terraform apply

# Get outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will output important resource identifiers
# and test the fine-grained access controls
```

## Post-Deployment Configuration

After deploying the infrastructure, complete these additional configuration steps:

### 1. Configure Lake Formation Data Lake Administrator

```bash
# Get your current user ARN
CURRENT_USER_ARN=$(aws sts get-caller-identity --query Arn --output text)

# Set yourself as Lake Formation data lake administrator
aws lakeformation put-data-lake-settings \
    --data-lake-settings "DataLakeAdmins=[{DataLakePrincipalIdentifier=${CURRENT_USER_ARN}}]"
```

### 2. Upload Sample Data

```bash
# Get the S3 bucket name from stack outputs
DATA_LAKE_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name lake-formation-fgac-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`DataLakeBucket`].OutputValue' \
    --output text)

# Create sample CSV data
cat > sample_data.csv << 'EOF'
customer_id,name,email,department,salary,ssn
1,John Doe,john@example.com,Engineering,75000,123-45-6789
2,Jane Smith,jane@example.com,Marketing,65000,987-65-4321
3,Bob Johnson,bob@example.com,Finance,80000,456-78-9012
4,Alice Brown,alice@example.com,Engineering,70000,321-54-9876
5,Charlie Wilson,charlie@example.com,HR,60000,654-32-1098
EOF

# Upload sample data to S3
aws s3 cp sample_data.csv s3://${DATA_LAKE_BUCKET}/customer_data/
```

### 3. Test Fine-Grained Access Controls

```bash
# Test Data Analyst Role (should see all columns)
aws sts assume-role \
    --role-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/DataAnalystRole" \
    --role-session-name "test-session"

# Test Finance Team Role (limited columns, no SSN)
aws sts assume-role \
    --role-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/FinanceTeamRole" \
    --role-session-name "finance-session"

# Test HR Role (very limited access)
aws sts assume-role \
    --role-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/HRRole" \
    --role-session-name "hr-session"
```

## Architecture Overview

The deployed infrastructure includes:

- **S3 Data Lake Bucket**: Stores raw customer data with proper versioning and encryption
- **AWS Lake Formation**: Centralized data lake security and governance
- **AWS Glue Data Catalog**: Metadata repository with database and table definitions
- **IAM Roles**: Three different roles representing various organizational functions:
  - `DataAnalystRole`: Full access to all table columns
  - `FinanceTeamRole`: Limited column access (excludes SSN)
  - `HRRole`: Very restricted access (name and department only)
- **Lake Formation Permissions**: Fine-grained access controls at column and row levels
- **Data Cell Filters**: Row-level security filters for specific departments

## Validation and Testing

### Verify Lake Formation Configuration

```bash
# Check registered S3 locations
aws lakeformation describe-resource \
    --resource-arn "arn:aws:s3:::${DATA_LAKE_BUCKET}"

# List all Lake Formation permissions
aws lakeformation list-permissions
```

### Test Column-Level Access Control

```bash
# Query using Amazon Athena (requires Athena setup)
aws athena start-query-execution \
    --query-string "SELECT * FROM sample_database.customer_data LIMIT 5" \
    --result-configuration "OutputLocation=s3://${DATA_LAKE_BUCKET}/query-results/"
```

### Verify Row-Level Security

```bash
# Check data cell filters
aws lakeformation list-data-cells-filter \
    --table '{
        "TableCatalogId": "'$(aws sts get-caller-identity --query Account --output text)'",
        "DatabaseName": "sample_database",
        "TableName": "customer_data"
    }'
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete sample data first
aws s3 rm s3://${DATA_LAKE_BUCKET}/customer_data/ --recursive

# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name lake-formation-fgac-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name lake-formation-fgac-stack
```

### Using CDK (AWS)

```bash
# Navigate to appropriate CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Customization

### Variable Customization

Each implementation supports customization through variables:

- **CloudFormation**: Modify parameters in the template or during stack creation
- **CDK**: Edit the configuration variables in the main application files
- **Terraform**: Customize values in `terraform.tfvars` or through environment variables
- **Bash Scripts**: Edit environment variables at the top of the scripts

### Common Customizations

```bash
# Custom bucket name prefix
DATA_LAKE_BUCKET_PREFIX="my-company-data-lake"

# Custom database name
DATABASE_NAME="analytics_database"

# Custom table name
TABLE_NAME="customer_analytics"

# Custom AWS region
AWS_REGION="us-west-2"
```

### Security Customizations

- **Encryption**: All implementations include S3 bucket encryption by default
- **IAM Policies**: Modify role policies to match your organization's requirements
- **Lake Formation Permissions**: Adjust column-level and row-level access patterns
- **Data Filters**: Create custom row-level security expressions

## Troubleshooting

### Common Issues

1. **Lake Formation Permission Denied**:
   - Ensure you're designated as a Lake Formation data lake administrator
   - Verify that "Use only IAM access control" is disabled in Lake Formation settings

2. **S3 Access Issues**:
   - Check that the S3 location is properly registered with Lake Formation
   - Verify that the service-linked role has appropriate permissions

3. **Glue Catalog Issues**:
   - Ensure the Glue database and table are created successfully
   - Verify that table schema matches the uploaded data format

4. **Role Assumption Failures**:
   - Check that IAM roles have the correct trust relationships
   - Verify that your user has permission to assume the roles

### Debug Commands

```bash
# Check Lake Formation settings
aws lakeformation get-data-lake-settings

# List all registered resources
aws lakeformation list-resources

# Verify Glue database and tables
aws glue get-databases
aws glue get-tables --database-name sample_database

# Check IAM role policies
aws iam list-attached-role-policies --role-name DataAnalystRole
```

## Security Considerations

- **Least Privilege**: All IAM roles follow the principle of least privilege
- **Encryption**: S3 buckets use AES-256 encryption by default
- **Audit Trail**: Consider enabling AWS CloudTrail for Lake Formation events
- **Network Security**: Consider using VPC endpoints for enhanced security
- **Data Classification**: Implement proper data classification tags

## Best Practices

1. **Data Organization**: Structure your S3 data lake with clear partitioning schemes
2. **Permission Management**: Regularly review and audit Lake Formation permissions
3. **Cost Optimization**: Use S3 Intelligent Tiering for automatic cost optimization
4. **Monitoring**: Set up CloudWatch alarms for unusual access patterns
5. **Backup Strategy**: Implement cross-region replication for critical datasets

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS Lake Formation documentation: https://docs.aws.amazon.com/lake-formation/
3. Review AWS Glue Data Catalog documentation: https://docs.aws.amazon.com/glue/
4. Consult AWS IAM best practices: https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html

## Additional Resources

- [AWS Lake Formation Developer Guide](https://docs.aws.amazon.com/lake-formation/latest/dg/)
- [AWS Glue Developer Guide](https://docs.aws.amazon.com/glue/latest/dg/)
- [Lake Formation Security and Access Control](https://docs.aws.amazon.com/lake-formation/latest/dg/security-data-access-control.html)
- [Fine-Grained Access Control in Lake Formation](https://docs.aws.amazon.com/lake-formation/latest/dg/fine-grained-access-control.html)