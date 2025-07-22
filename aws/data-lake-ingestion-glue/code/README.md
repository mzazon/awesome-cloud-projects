# Infrastructure as Code for Data Lake Ingestion Pipelines with Glue

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Data Lake Ingestion Pipelines with Glue".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This IaC deploys a complete serverless data lake ingestion pipeline with:

- **S3 Data Lake**: Multi-layer storage (Bronze, Silver, Gold)
- **AWS Glue Crawler**: Automated schema discovery and cataloging
- **AWS Glue ETL Jobs**: PySpark-based data transformation pipeline
- **AWS Glue Workflows**: Orchestrated pipeline execution
- **AWS Glue Data Catalog**: Centralized metadata management
- **IAM Roles**: Least-privilege security configuration
- **CloudWatch Monitoring**: Job execution and performance monitoring
- **SNS Alerts**: Automated failure notifications
- **Athena Integration**: SQL querying capabilities

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - IAM (roles, policies)
  - S3 (bucket creation and management)
  - AWS Glue (jobs, crawlers, workflows, data catalog)
  - CloudWatch (alarms, logs)
  - SNS (topics, subscriptions)
  - Athena (workgroups, queries)
- For CDK implementations: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+
- Estimated deployment cost: $15-25 (depends on data volume and job runtime)

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name data-lake-pipeline \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=datalake \
                 ParameterKey=Environment,ParameterValue=dev \
                 ParameterKey=NotificationEmail,ParameterValue=your-email@example.com

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name data-lake-pipeline \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name data-lake-pipeline \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK directory
cd cdk-typescript/

# Install dependencies
npm install

# Configure deployment parameters (optional)
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy the stack
cdk deploy DataLakePipelineStack \
    --parameters notificationEmail=your-email@example.com \
    --parameters projectName=datalake \
    --parameters environment=dev

# View stack outputs
cdk ls --long
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

# Configure deployment parameters
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy the stack
cdk deploy DataLakePipelineStack \
    --parameters notificationEmail=your-email@example.com \
    --parameters projectName=datalake \
    --parameters environment=dev

# View stack outputs
cdk ls --long
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_NAME="datalake"
export ENVIRONMENT="dev"
export NOTIFICATION_EMAIL="your-email@example.com"
export AWS_REGION="us-east-1"  # or your preferred region

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
./scripts/deploy.sh --status
```

## Post-Deployment Setup

After successful deployment, complete these steps:

1. **Upload Sample Data** (if not included in deployment):
   ```bash
   # Get bucket name from outputs
   S3_BUCKET=$(aws cloudformation describe-stacks \
       --stack-name data-lake-pipeline \
       --query 'Stacks[0].Outputs[?OutputKey==`DataLakeBucket`].OutputValue' \
       --output text)
   
   # Upload sample data (customize as needed)
   aws s3 cp sample-data/ s3://${S3_BUCKET}/raw-data/ --recursive
   ```

2. **Start Initial Crawler Run**:
   ```bash
   # Get crawler name from outputs
   CRAWLER_NAME=$(aws cloudformation describe-stacks \
       --stack-name data-lake-pipeline \
       --query 'Stacks[0].Outputs[?OutputKey==`CrawlerName`].OutputValue' \
       --output text)
   
   # Start crawler
   aws glue start-crawler --name ${CRAWLER_NAME}
   ```

3. **Trigger Initial ETL Job**:
   ```bash
   # Get job name from outputs
   ETL_JOB_NAME=$(aws cloudformation describe-stacks \
       --stack-name data-lake-pipeline \
       --query 'Stacks[0].Outputs[?OutputKey==`ETLJobName`].OutputValue' \
       --output text)
   
   # Start ETL job
   aws glue start-job-run --job-name ${ETL_JOB_NAME}
   ```

4. **Confirm SNS Subscription**:
   - Check your email for SNS subscription confirmation
   - Click the confirmation link to receive alerts

## Validation and Testing

### Verify Data Catalog

```bash
# List databases
aws glue get-databases

# List tables in the data lake database
DATABASE_NAME=$(aws cloudformation describe-stacks \
    --stack-name data-lake-pipeline \
    --query 'Stacks[0].Outputs[?OutputKey==`DatabaseName`].OutputValue' \
    --output text)

aws glue get-tables --database-name ${DATABASE_NAME}
```

### Test Athena Queries

```bash
# Get Athena workgroup
WORKGROUP_NAME=$(aws cloudformation describe-stacks \
    --stack-name data-lake-pipeline \
    --query 'Stacks[0].Outputs[?OutputKey==`AthenaWorkgroup`].OutputValue' \
    --output text)

# Run sample query
aws athena start-query-execution \
    --query-string "SELECT COUNT(*) FROM ${DATABASE_NAME}.silver_events" \
    --work-group ${WORKGROUP_NAME}
```

### Monitor Pipeline Execution

```bash
# Check workflow runs
WORKFLOW_NAME=$(aws cloudformation describe-stacks \
    --stack-name data-lake-pipeline \
    --query 'Stacks[0].Outputs[?OutputKey==`WorkflowName`].OutputValue' \
    --output text)

aws glue get-workflow-runs --name ${WORKFLOW_NAME}

# Check CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix "/aws-glue/"
```

## Cleanup

### Using CloudFormation

```bash
# Empty S3 bucket first (required for deletion)
S3_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name data-lake-pipeline \
    --query 'Stacks[0].Outputs[?OutputKey==`DataLakeBucket`].OutputValue' \
    --output text)

aws s3 rm s3://${S3_BUCKET} --recursive

# Delete the stack
aws cloudformation delete-stack --stack-name data-lake-pipeline

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name data-lake-pipeline \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# For TypeScript
cd cdk-typescript/
cdk destroy DataLakePipelineStack

# For Python
cd cdk-python/
cdk destroy DataLakePipelineStack
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm cleanup completion
./scripts/destroy.sh --verify
```

## Customization

### Key Configuration Parameters

| Parameter | Description | Default | CloudFormation | CDK | Terraform |
|-----------|-------------|---------|----------------|-----|-----------|
| Project Name | Prefix for resource names | `datalake` | ✅ | ✅ | ✅ |
| Environment | Environment tag (dev/staging/prod) | `dev` | ✅ | ✅ | ✅ |
| AWS Region | Deployment region | `us-east-1` | ✅ | ✅ | ✅ |
| Notification Email | SNS alert email | Required | ✅ | ✅ | ✅ |
| Glue Job Capacity | DPU allocation for ETL jobs | `5` | ✅ | ✅ | ✅ |
| Crawler Schedule | Cron expression for crawler | `cron(0 6 * * ? *)` | ✅ | ✅ | ✅ |
| Data Retention | S3 lifecycle policy days | `90` | ✅ | ✅ | ✅ |

### Advanced Customization

1. **ETL Job Modifications**:
   - Update `etl-script.py` in the scripts directory
   - Modify transformation logic for your data formats
   - Add custom data quality rules

2. **Schema Evolution**:
   - Configure crawler schema change policies
   - Implement schema versioning strategies
   - Add data validation rules

3. **Security Enhancements**:
   - Enable S3 encryption with customer-managed KMS keys
   - Implement VPC endpoints for private communication
   - Add IAM policies for cross-account access

4. **Performance Optimization**:
   - Adjust Glue job worker types and counts
   - Implement data partitioning strategies
   - Configure columnar storage optimizations

## Architecture Components

### Core Infrastructure

- **S3 Data Lake**: Hierarchical storage with Bronze/Silver/Gold layers
- **IAM Service Role**: Least-privilege access for Glue services
- **Glue Database**: Centralized metadata catalog

### Data Processing

- **Glue Crawler**: Automated schema discovery and cataloging
- **Glue ETL Job**: PySpark-based data transformation pipeline
- **Glue Workflow**: Orchestrated execution with dependency management

### Monitoring and Operations

- **CloudWatch Alarms**: Job failure and performance monitoring
- **SNS Topic**: Automated alert notifications
- **CloudWatch Logs**: Detailed execution logging

### Analytics Integration

- **Athena Workgroup**: SQL query interface for data lake
- **Query Result Location**: S3 bucket for Athena query results

## Troubleshooting

### Common Issues

1. **IAM Permission Errors**:
   ```bash
   # Verify IAM role policies
   aws iam get-role-policy --role-name <GlueRoleName> --policy-name GlueS3Access
   ```

2. **Crawler Failures**:
   ```bash
   # Check crawler logs
   aws glue get-crawler --name <CrawlerName>
   aws logs filter-log-events --log-group-name "/aws-glue/crawlers"
   ```

3. **ETL Job Failures**:
   ```bash
   # Check job run details
   aws glue get-job-runs --job-name <JobName>
   aws logs filter-log-events --log-group-name "/aws-glue/jobs/output"
   ```

4. **S3 Access Issues**:
   ```bash
   # Verify bucket permissions
   aws s3api get-bucket-policy --bucket <BucketName>
   ```

### Support Resources

- [AWS Glue Developer Guide](https://docs.aws.amazon.com/glue/latest/dg/what-is-glue.html)
- [AWS Glue Data Catalog Best Practices](https://docs.aws.amazon.com/glue/latest/dg/best-practices-catalog.html)
- [AWS Glue ETL Programming Guide](https://docs.aws.amazon.com/glue/latest/dg/aws-glue-programming.html)
- [Amazon Athena User Guide](https://docs.aws.amazon.com/athena/latest/ug/what-is.html)

## Support

For issues with this infrastructure code:

1. Review the troubleshooting section above
2. Check AWS service status and limits
3. Refer to the original recipe documentation
4. Consult AWS documentation for specific services
5. Use AWS Support for production issues

## Security Considerations

- All IAM roles follow least-privilege principles
- S3 buckets include public access blocking by default
- CloudWatch logs retention is configured appropriately
- SNS topics use encryption in transit
- Glue jobs run in isolated execution environments

## Cost Optimization

- Implement S3 lifecycle policies for cost-effective storage
- Use Glue job bookmarking to process only changed data
- Configure appropriate Glue job capacity and timeout settings
- Monitor CloudWatch usage and adjust retention periods
- Consider Reserved Capacity for predictable workloads