# Infrastructure as Code for Data Pipeline Orchestration with Glue Workflows

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Data Pipeline Orchestration with Glue Workflows".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for creating Glue, S3, IAM, and CloudWatch resources
- For CDK implementations: Node.js (for TypeScript) or Python 3.8+
- For Terraform: Terraform CLI v1.0+

### Required AWS Permissions

Your AWS credentials need the following permissions:
- `glue:*` - For creating workflows, jobs, crawlers, and triggers
- `s3:*` - For creating and managing S3 buckets
- `iam:*` - For creating and managing IAM roles and policies
- `cloudwatch:*` - For monitoring and logging

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name glue-workflow-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=dev

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name glue-workflow-stack \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name glue-workflow-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not done before)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk outputs
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create and activate virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not done before)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk outputs
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

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will create all necessary resources and provide output
```

## Architecture Overview

The infrastructure creates:

1. **S3 Buckets**: Raw data input and processed data output buckets
2. **IAM Role**: Service role for Glue operations with appropriate permissions
3. **Glue Database**: Data catalog database for metadata management
4. **Glue Crawlers**: Source and target crawlers for schema discovery
5. **Glue ETL Job**: Data transformation job with PySpark script
6. **Glue Workflow**: Orchestration workflow with triggers
7. **Triggers**: Schedule and event-based triggers for automation

## Configuration Options

### CloudFormation Parameters

- `Environment`: Environment name (dev, staging, prod)
- `ProjectName`: Project identifier for resource naming
- `ScheduleExpression`: Cron expression for workflow scheduling
- `MaxConcurrentRuns`: Maximum concurrent workflow executions

### CDK Configuration

Modify the configuration in the CDK app files:

```typescript
// For TypeScript
const config = {
  environment: 'dev',
  projectName: 'data-pipeline',
  scheduleExpression: 'cron(0 2 * * ? *)',
  maxConcurrentRuns: 1
};
```

```python
# For Python
config = {
    'environment': 'dev',
    'project_name': 'data-pipeline',
    'schedule_expression': 'cron(0 2 * * ? *)',
    'max_concurrent_runs': 1
}
```

### Terraform Variables

Edit `terraform/variables.tf` or create a `terraform.tfvars` file:

```hcl
environment = "dev"
project_name = "data-pipeline"
schedule_expression = "cron(0 2 * * ? *)"
max_concurrent_runs = 1
aws_region = "us-east-1"
```

## Testing the Deployment

After deployment, test the workflow:

```bash
# Start workflow execution (replace with actual workflow name)
aws glue start-workflow-run --name data-pipeline-workflow-<suffix>

# Monitor workflow status
aws glue get-workflow-runs --name data-pipeline-workflow-<suffix>

# Check Data Catalog for discovered tables
aws glue get-tables --database-name workflow_database_<suffix>

# Verify processed data in S3
aws s3 ls s3://processed-data-<suffix>/output/ --recursive
```

## Monitoring and Logging

The infrastructure includes CloudWatch integration for monitoring:

```bash
# View Glue job logs
aws logs describe-log-groups --log-group-name-prefix "/aws-glue"

# Monitor workflow execution metrics
aws cloudwatch get-metric-statistics \
    --namespace "AWS/Glue" \
    --metric-name "glue.driver.aggregate.numCompletedTasks" \
    --dimensions Name=JobName,Value=data-processing-job-<suffix> \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-02T00:00:00Z \
    --period 300 \
    --statistics Sum
```

## Customization

### Adding New ETL Jobs

To add additional ETL jobs to the workflow:

1. Create new job resources in your IaC template
2. Update the workflow triggers to include the new job
3. Modify the ETL script with your transformation logic
4. Update IAM permissions if accessing new resources

### Modifying Schedule

To change the workflow schedule:

1. **CloudFormation**: Update the `ScheduleExpression` parameter
2. **CDK**: Modify the schedule expression in the configuration
3. **Terraform**: Update the `schedule_expression` variable

### Adding Data Quality Checks

Extend the workflow with data quality validation:

1. Create additional Glue jobs for data quality checks
2. Add conditional triggers based on quality results
3. Implement error handling and notification logic

## Cost Optimization

- **S3 Storage**: Use appropriate storage classes for your data lifecycle
- **Glue Jobs**: Configure optimal DPU (Data Processing Unit) allocation
- **Crawlers**: Schedule crawlers only when schema changes are expected
- **Monitoring**: Set up CloudWatch alarms to monitor costs

## Security Considerations

The infrastructure implements security best practices:

- **IAM Roles**: Least privilege access for Glue operations
- **S3 Security**: Bucket policies and access controls
- **Encryption**: Data encryption at rest and in transit
- **VPC**: Optional VPC configuration for network isolation

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name glue-workflow-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name glue-workflow-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

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

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Troubleshooting

### Common Issues

1. **IAM Permission Errors**: Ensure your AWS credentials have sufficient permissions
2. **Resource Name Conflicts**: Check for existing resources with similar names
3. **Glue Job Failures**: Review CloudWatch logs for detailed error messages
4. **Crawler Issues**: Verify S3 bucket permissions and data format

### Debugging Commands

```bash
# Check Glue job run details
aws glue get-job-runs --job-name <job-name>

# View crawler run information
aws glue get-crawler-metrics --crawler-name-list <crawler-name>

# Check workflow execution details
aws glue get-workflow-run --name <workflow-name> --run-id <run-id>
```

## Additional Resources

- [AWS Glue Developer Guide](https://docs.aws.amazon.com/glue/latest/dg/)
- [AWS Glue Workflows Documentation](https://docs.aws.amazon.com/glue/latest/dg/workflows_overview.html)
- [AWS Glue Best Practices](https://docs.aws.amazon.com/glue/latest/dg/best-practices.html)
- [AWS Glue Pricing](https://aws.amazon.com/glue/pricing/)

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult AWS Glue documentation
4. Check AWS service status for any ongoing issues

## Version Information

- **Recipe Version**: 1.2
- **Last Updated**: 2025-07-12
- **Compatible AWS CLI**: v2.0+
- **Compatible CDK**: v2.0+
- **Compatible Terraform**: v1.0+