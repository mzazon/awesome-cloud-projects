# Infrastructure as Code for ETL Pipelines with Glue Data Catalog

This directory contains Infrastructure as Code (IaC) implementations for the recipe "ETL Pipelines with Glue Data Catalog".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - AWS Glue (crawlers, jobs, database)
  - Amazon S3 (bucket creation and object management)
  - IAM (role creation and policy attachment)
  - Amazon Athena (query execution)
- Tool-specific prerequisites:
  - **CloudFormation**: No additional tools required
  - **CDK TypeScript**: Node.js 18+ and npm
  - **CDK Python**: Python 3.8+ and pip
  - **Terraform**: Terraform 1.0+ installed
  - **Bash Scripts**: Standard bash shell environment

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name etl-glue-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=Environment,ParameterValue=dev \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name etl-glue-stack \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name etl-glue-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack outputs
cdk list
```

### Using CDK Python (AWS)

```bash
cd cdk-python/

# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack outputs
cdk list
```

### Using Terraform

```bash
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
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
echo "Deployment completed. Check AWS Console for resource status."
```

## Architecture Overview

The infrastructure deploys the following AWS resources:

- **S3 Buckets**: Separate buckets for raw and processed data storage
- **AWS Glue Database**: Central metadata repository for data catalog
- **AWS Glue Crawlers**: Automated schema discovery for raw and processed data
- **AWS Glue ETL Job**: Serverless data transformation pipeline
- **IAM Roles and Policies**: Secure access control for Glue services
- **Sample Data**: Initial datasets for testing the ETL pipeline

## Configuration Options

### Environment Variables

The following environment variables can be customized in each implementation:

| Variable | Description | Default Value |
|----------|-------------|---------------|
| `Environment` | Deployment environment (dev/staging/prod) | dev |
| `ProjectName` | Project identifier for resource naming | etl-pipeline |
| `DataRetentionDays` | S3 object retention period | 30 |
| `GlueVersion` | AWS Glue ETL job version | 4.0 |
| `MaxRetries` | Maximum job retry attempts | 1 |
| `JobTimeout` | ETL job timeout in minutes | 60 |

### Terraform Variables

When using Terraform, customize the deployment by creating a `terraform.tfvars` file:

```hcl
environment = "production"
project_name = "my-etl-project"
aws_region = "us-west-2"
data_retention_days = 90
enable_cloudwatch_logs = true
```

### CDK Context

For CDK deployments, customize through `cdk.json` context:

```json
{
  "context": {
    "environment": "staging",
    "projectName": "analytics-pipeline",
    "enableVersioning": true,
    "logRetentionDays": 14
  }
}
```

## Testing the Deployment

After successful deployment, validate the infrastructure:

1. **Verify S3 Buckets**:
   ```bash
   aws s3 ls | grep etl-pipeline
   ```

2. **Check Glue Database**:
   ```bash
   aws glue get-databases --query 'DatabaseList[].Name'
   ```

3. **List Glue Crawlers**:
   ```bash
   aws glue list-crawlers --query 'CrawlerNames'
   ```

4. **Verify ETL Job**:
   ```bash
   aws glue list-jobs --query 'JobNames'
   ```

5. **Test Data Upload and Processing**:
   ```bash
   # Upload sample data (included in deployment)
   # Run crawler to discover schema
   # Execute ETL job
   # Query results with Athena
   ```

## Monitoring and Logging

The infrastructure includes monitoring capabilities:

- **CloudWatch Logs**: ETL job execution logs
- **CloudWatch Metrics**: Glue service metrics and performance
- **AWS Glue Console**: Visual monitoring of crawlers and jobs
- **S3 Access Logs**: Data access patterns and usage

## Cost Optimization

To optimize costs:

1. **S3 Lifecycle Policies**: Automatically transition data to cheaper storage classes
2. **Glue Job Scheduling**: Run ETL jobs only when needed
3. **Data Partitioning**: Improve query performance and reduce scanning costs
4. **Resource Monitoring**: Use AWS Cost Explorer to track spending

## Security Features

The deployment implements security best practices:

- **Least Privilege IAM**: Minimal required permissions for each service
- **Encryption**: S3 server-side encryption enabled by default
- **VPC Endpoints**: Secure communication between services (optional)
- **Access Logging**: Comprehensive audit trails for data access

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack (removes all resources)
aws cloudformation delete-stack --stack-name etl-glue-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name etl-glue-stack \
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
cd terraform/

# Plan the destruction
terraform plan -destroy

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
echo "All resources have been cleaned up."
```

## Troubleshooting

### Common Issues

1. **IAM Permissions**: Ensure your AWS credentials have sufficient permissions
2. **Resource Limits**: Check AWS service quotas for your account
3. **Region Availability**: Verify all services are available in your chosen region
4. **S3 Bucket Names**: Bucket names must be globally unique

### Debug Commands

```bash
# Check AWS CLI configuration
aws sts get-caller-identity

# Verify region setting
aws configure get region

# List IAM roles
aws iam list-roles --query 'Roles[?contains(RoleName, `Glue`)].RoleName'

# Check Glue service quotas
aws service-quotas list-service-quotas \
    --service-code glue \
    --query 'Quotas[?QuotaName==`Jobs`]'
```

### Log Locations

- **CloudFormation**: AWS CloudFormation Console → Stack Events
- **CDK**: CDK CLI output and CloudFormation events
- **Terraform**: Terraform CLI output and AWS CloudTrail
- **Glue Jobs**: CloudWatch Logs → `/aws-glue/jobs/logs-v2/`

## Customization

### Adding New Data Sources

To extend the pipeline for additional data sources:

1. Update S3 bucket paths in crawler configurations
2. Modify ETL job script to handle new data formats
3. Add new Glue tables to the data catalog
4. Update IAM permissions for new resources

### Scaling Considerations

For production deployments:

- Increase Glue job DPU allocation for larger datasets
- Implement data partitioning strategies
- Add cross-region replication for disaster recovery
- Consider using Glue workflows for complex pipelines

### Integration Options

- **Amazon QuickSight**: Connect for business intelligence dashboards
- **Amazon Redshift**: Load processed data for data warehousing
- **AWS Lake Formation**: Add fine-grained access controls
- **Amazon EventBridge**: Trigger ETL jobs based on events

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS Glue documentation: https://docs.aws.amazon.com/glue/
3. Consult AWS troubleshooting guides
4. Review CloudWatch logs for specific error messages

## Additional Resources

- [AWS Glue Best Practices](https://docs.aws.amazon.com/glue/latest/dg/best-practice-catalog.html)
- [AWS Glue ETL Job Development](https://docs.aws.amazon.com/glue/latest/dg/author-job.html)
- [AWS Glue Data Catalog](https://docs.aws.amazon.com/glue/latest/dg/populate-catalog-methods.html)
- [Cost Optimization for AWS Glue](https://aws.amazon.com/blogs/big-data/optimize-aws-glue-job-cost-and-performance/)