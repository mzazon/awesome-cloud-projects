# Infrastructure as Code for Data Lake Governance with Lake Formation

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Data Lake Governance with Lake Formation".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Administrative permissions for Lake Formation, DataZone, Glue, S3, and IAM
- Node.js 18+ and npm (for CDK TypeScript)
- Python 3.8+ and pip (for CDK Python)
- Terraform 1.5+ (for Terraform implementation)
- Understanding of data governance principles and AWS security best practices
- Estimated cost: $200-400 for a 5-hour workshop

> **Important**: This solution involves complex IAM permissions and cross-service integrations. Test thoroughly in non-production environments first.

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name data-lake-governance-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=DomainName,ParameterValue=enterprise-data-governance \
                 ParameterKey=DataLakeBucketPrefix,ParameterValue=enterprise-datalake \
    --capabilities CAPABILITY_IAM \
    --capabilities CAPABILITY_NAMED_IAM

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name data-lake-governance-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name data-lake-governance-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
npx cdk bootstrap

# Synthesize CloudFormation template (optional)
npx cdk synth

# Deploy the stack
npx cdk deploy --parameters domainName=enterprise-data-governance

# View outputs
npx cdk outputs
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Synthesize CloudFormation template (optional)
cdk synth

# Deploy the stack
cdk deploy --parameters domainName=enterprise-data-governance

# View outputs
cdk outputs
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan -var="domain_name=enterprise-data-governance"

# Apply the configuration
terraform apply -var="domain_name=enterprise-data-governance"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export DOMAIN_NAME="enterprise-data-governance"
export AWS_REGION="us-east-1"  # or your preferred region

# Deploy the infrastructure
./scripts/deploy.sh

# After deployment, check the outputs
cat outputs.json
```

## Architecture Overview

This implementation creates a comprehensive data lake governance platform including:

### Core Components
- **AWS Lake Formation**: Fine-grained access control and data catalog management
- **Amazon DataZone**: Business data catalog and self-service data discovery
- **S3 Data Lake**: Multi-zone storage (raw, curated, analytics)
- **AWS Glue**: ETL jobs with lineage tracking and data catalog

### Security and Governance
- Row-level and column-level security policies
- PII data protection with data cell filters
- Automated audit logging and compliance monitoring
- IAM roles with least privilege access

### Data Pipeline
- Sample data generation and ETL processing
- Data quality monitoring with CloudWatch alerts
- Automated data lineage tracking
- Business glossary integration

## Configuration Options

### Environment Variables (for Bash scripts)

```bash
export DOMAIN_NAME="your-domain-name"           # DataZone domain name
export AWS_REGION="us-east-1"                   # AWS region
export DATA_LAKE_BUCKET_PREFIX="your-prefix"    # S3 bucket prefix (optional)
export ENABLE_SAMPLE_DATA="true"                # Generate sample data (default: true)
export EMAIL_ALERTS="your-email@example.com"    # Email for alerts (optional)
```

### CloudFormation Parameters

- `DomainName`: DataZone domain name (default: enterprise-data-governance)
- `DataLakeBucketPrefix`: S3 bucket prefix for unique naming
- `EnableSampleData`: Whether to create sample data (default: true)
- `AlertEmail`: Email address for data quality alerts (optional)

### Terraform Variables

```hcl
# terraform.tfvars example
domain_name = "enterprise-data-governance"
aws_region = "us-east-1"
data_lake_bucket_prefix = "my-company-datalake"
enable_sample_data = true
alert_email = "admin@example.com"
```

### CDK Context Variables

```json
{
  "domain-name": "enterprise-data-governance",
  "enable-sample-data": true,
  "alert-email": "admin@example.com"
}
```

## Post-Deployment Steps

### 1. Verify Lake Formation Configuration

```bash
# Check Lake Formation settings
aws lakeformation describe-resource \
    --resource-arn $(terraform output -raw data_lake_bucket_arn)

# List permissions
aws lakeformation list-permissions \
    --resource '{
        "Database": {
            "Name": "enterprise_data_catalog"
        }
    }'
```

### 2. Test Data Access

```bash
# Query customer data (should filter PII columns)
aws athena start-query-execution \
    --query-string "SELECT customer_segment, COUNT(*) FROM enterprise_data_catalog.customer_data GROUP BY customer_segment" \
    --result-configuration "OutputLocation=$(terraform output -raw athena_results_location)"
```

### 3. Access DataZone Portal

1. Navigate to the Amazon DataZone console
2. Open your domain: `enterprise-data-governance`
3. Explore the business glossary and data catalog
4. Review data lineage information

### 4. Monitor Data Quality

```bash
# Check CloudWatch metrics for ETL jobs
aws cloudwatch get-metric-statistics \
    --namespace AWS/Glue \
    --metric-name glue.ALL.job.success \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 3600 \
    --statistics Sum
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name data-lake-governance-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name data-lake-governance-stack
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
npx cdk destroy --force
```

### Using CDK Python

```bash
cd cdk-python/
source .venv/bin/activate  # Activate virtual environment
cdk destroy --force
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="domain_name=enterprise-data-governance"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm all resources are removed
aws s3 ls | grep enterprise-datalake
```

## Troubleshooting

### Common Issues

1. **Lake Formation Permissions**
   - Ensure the executing user has Lake Formation admin permissions
   - Verify IAM roles have correct trust relationships

2. **DataZone Domain Creation**
   - DataZone requires specific IAM permissions
   - Domain names must be globally unique within your account

3. **S3 Bucket Conflicts**
   - Bucket names must be globally unique
   - Use the provided random suffix generation

4. **ETL Job Failures**
   - Check CloudWatch logs for Glue job execution details
   - Verify S3 permissions for the service role

### Debugging Commands

```bash
# Check IAM role policies
aws iam get-role --role-name LakeFormationServiceRole

# Verify S3 bucket permissions
aws s3api get-bucket-policy --bucket $(terraform output -raw data_lake_bucket_name)

# Check Glue job status
aws glue get-job-runs --job-name CustomerDataETLWithLineage

# View CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix /aws/glue
```

## Security Considerations

- All S3 buckets use server-side encryption (AES-256)
- IAM roles follow least privilege principle
- Lake Formation provides fine-grained access control
- PII data is protected with column-level filters
- Audit trails are enabled for all data access

## Cost Optimization

- Glue jobs use minimal DPU settings for cost efficiency
- S3 storage uses standard tier with lifecycle policies
- DataZone charges based on active users and data assets
- CloudWatch logs have 30-day retention to manage costs

## Support

For issues with this infrastructure code:

1. Review the [original recipe documentation](../advanced-data-lake-governance-lake-formation-datazone.md)
2. Check AWS service documentation:
   - [Lake Formation Developer Guide](https://docs.aws.amazon.com/lake-formation/)
   - [DataZone User Guide](https://docs.aws.amazon.com/datazone/)
   - [Glue Developer Guide](https://docs.aws.amazon.com/glue/)
3. Verify IAM permissions and service quotas
4. Check CloudWatch logs for detailed error messages

## Advanced Features

### Enable Cross-Account Data Sharing

```bash
# Add external account to Lake Formation trusted owners
aws lakeformation put-data-lake-settings \
    --data-lake-settings '{
        "TrustedResourceOwners": ["123456789012", "987654321098"]
    }'
```

### Configure Data Quality Rules

```bash
# Create Glue DataBrew profile for data quality analysis
aws databrew create-profile-job \
    --name customer-data-profile \
    --dataset-name customer_data \
    --role-arn $(terraform output -raw glue_service_role_arn)
```

### Set Up Real-time Monitoring

```bash
# Enable VPC Flow Logs for network monitoring
aws ec2 create-flow-logs \
    --resource-type VPC \
    --resource-ids $(terraform output -raw vpc_id) \
    --traffic-type ALL \
    --log-destination-type s3 \
    --log-destination $(terraform output -raw data_lake_bucket_arn)/vpc-flow-logs/
```

This infrastructure provides a production-ready foundation for enterprise data lake governance. Customize the configurations based on your specific organizational requirements and security policies.