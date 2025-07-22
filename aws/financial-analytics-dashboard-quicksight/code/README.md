# Infrastructure as Code for Financial Analytics Dashboard with QuickSight

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Financial Analytics Dashboard with QuickSight".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution creates a sophisticated financial analytics platform that provides:

- Automated cost data collection using Cost Explorer APIs
- Real-time data processing with Lambda functions
- Advanced analytics with Amazon Athena
- Interactive dashboards with Amazon QuickSight
- Automated reporting and alerting capabilities

### Key Components

- **Data Collection**: Lambda functions for Cost Explorer API integration
- **Data Storage**: S3 buckets with lifecycle policies for cost optimization
- **Data Processing**: Automated transformation and normalization pipelines
- **Analytics Engine**: Athena workgroups and Glue data catalog
- **Visualization**: QuickSight datasets and dashboard templates
- **Automation**: EventBridge schedules for regular data updates

## Prerequisites

- AWS CLI v2 installed and configured with appropriate credentials
- AWS account with Cost Explorer enabled and QuickSight configured
- IAM permissions for Cost Explorer, QuickSight, Lambda, S3, Athena, and Glue
- Basic understanding of SQL for Athena queries and data transformations
- Estimated cost: $200-400/month for QuickSight Enterprise, S3 storage, and data processing

### Required Permissions

Your AWS credentials must have permissions for:
- Cost Explorer: Full access for data collection
- QuickSight: Admin access for data sources and dashboards
- Lambda: Function creation and execution
- S3: Bucket creation and object management
- Athena: Workgroup and query management
- Glue: Database and table creation
- EventBridge: Rule creation and management
- IAM: Role and policy management

## Quick Start

### Using CloudFormation
```bash
aws cloudformation create-stack \
    --stack-name financial-analytics-dashboard \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=production
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install
npx cdk bootstrap  # If first time using CDK in this account/region
npx cdk deploy --parameters environment=production
```

### Using CDK Python
```bash
cd cdk-python/
pip install -r requirements.txt
cdk bootstrap  # If first time using CDK in this account/region
cdk deploy --parameters environment=production
```

### Using Terraform
```bash
cd terraform/
terraform init
terraform plan -var="environment=production"
terraform apply
```

### Using Bash Scripts
```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Configuration

### Environment Variables

Before deployment, configure these environment variables:

```bash
export AWS_REGION=us-east-1  # Your preferred AWS region
export ENVIRONMENT=production  # deployment environment
export PROJECT_NAME=financial-analytics  # project identifier
```

### Customizable Parameters

- **Environment**: Deployment environment (development, staging, production)
- **Region**: AWS region for resource deployment
- **Data Retention**: S3 lifecycle policy settings for cost optimization
- **Schedule**: EventBridge schedule expressions for data collection frequency
- **QuickSight Edition**: Standard vs Enterprise Edition features

## Post-Deployment Setup

### 1. QuickSight Configuration

After infrastructure deployment, complete QuickSight setup:

1. Navigate to [QuickSight Console](https://quicksight.aws.amazon.com/)
2. Configure permissions for S3 and Athena access
3. Create analyses using the pre-configured datasets
4. Build interactive dashboards for different stakeholder groups

### 2. Initial Data Collection

Trigger initial data collection to populate dashboards:

```bash
# Using AWS CLI
aws lambda invoke \
    --function-name financial-analytics-cost-collector \
    --payload '{"source": "manual-initial"}' \
    response.json

# Wait for processing, then trigger transformation
aws lambda invoke \
    --function-name financial-analytics-data-transformer \
    --payload '{"source": "manual-initial"}' \
    response.json
```

### 3. Dashboard Creation

Create executive and operational dashboards:

1. **Executive Dashboard**: High-level cost trends, budget performance, ROI metrics
2. **Department Dashboard**: Chargeback reporting, resource allocation by team
3. **Operations Dashboard**: Service-level costs, optimization recommendations
4. **Forecasting Dashboard**: Predictive analytics and budget planning

## Validation & Testing

### Verify Data Pipeline

```bash
# Check S3 buckets were created
aws s3 ls | grep financial-analytics

# Verify Lambda functions are deployed
aws lambda list-functions --query 'Functions[?contains(FunctionName, `financial-analytics`)].[FunctionName,Runtime,LastModified]' --output table

# Test Athena connectivity
aws athena list-work-groups --query 'WorkGroups[?Name==`FinancialAnalytics`]'

# Verify QuickSight data sources
aws quicksight list-data-sources --aws-account-id $(aws sts get-caller-identity --query Account --output text)
```

### Test Data Collection

```bash
# Manually trigger data collection
aws events put-events \
    --entries '[{
        "Source": "financial.analytics",
        "DetailType": "Manual Data Collection",
        "Detail": "{\"trigger\": \"manual\"}"
    }]'
```

## Cleanup

### Using CloudFormation
```bash
aws cloudformation delete-stack --stack-name financial-analytics-dashboard
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/
npx cdk destroy  # or: cdk destroy
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

### Manual Cleanup

Some resources may require manual cleanup:

1. **QuickSight**: Remove analyses and dashboards from QuickSight console
2. **S3 Objects**: Empty S3 buckets if they contain data
3. **Cost Explorer**: No cleanup required (AWS managed service)

## Customization

### Modifying Data Collection Frequency

Update EventBridge schedules in the infrastructure code:

```yaml
# CloudFormation example
DailyCostDataCollection:
  Type: AWS::Events::Rule
  Properties:
    ScheduleExpression: "cron(0 6 * * ? *)"  # Daily at 6 AM UTC
```

### Adding Custom Metrics

Extend the data transformation Lambda to include additional metrics:

1. Modify the `data_transformer.py` function
2. Update Athena table schemas
3. Create new QuickSight datasets for custom metrics

### Multi-Account Setup

For AWS Organizations with multiple accounts:

1. Deploy in the management account
2. Configure cross-account IAM roles
3. Update Cost Explorer API calls for consolidated billing
4. Modify data transformation for account-level reporting

## Cost Optimization

### S3 Storage Costs

- Lifecycle policies automatically transition data to cheaper storage classes
- Raw data moves to Standard-IA after 30 days, Glacier after 90 days
- Processed data optimized for frequent access patterns

### Lambda Costs

- Functions use appropriate memory allocation for workload
- EventBridge schedules minimize unnecessary executions
- Data transformation uses efficient pandas operations

### QuickSight Costs

- Choose appropriate edition (Standard vs Enterprise) based on features needed
- Monitor user access patterns for cost optimization
- Use SPICE datasets for frequently accessed data

## Troubleshooting

### Common Issues

1. **QuickSight Permissions**: Ensure QuickSight service role has S3 and Athena access
2. **Cost Explorer Access**: Verify Cost Explorer is enabled in the billing console
3. **Lambda Timeouts**: Increase timeout for data processing functions if needed
4. **Athena Query Failures**: Check S3 permissions and data format consistency

### Monitoring

Set up CloudWatch alerts for:
- Lambda function errors
- S3 access denied errors
- Athena query failures
- Cost anomalies in your analytics spending

### Support Resources

- [AWS Cost Explorer Documentation](https://docs.aws.amazon.com/cost-management/latest/userguide/ce-what-is.html)
- [Amazon QuickSight User Guide](https://docs.aws.amazon.com/quicksight/latest/user/welcome.html)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/welcome.html)
- [Amazon Athena User Guide](https://docs.aws.amazon.com/athena/latest/ug/what-is.html)

## Security Considerations

### Data Protection

- All S3 buckets use server-side encryption
- Lambda functions use IAM roles with least privilege access
- QuickSight datasets implement row-level security where appropriate

### Access Control

- IAM policies follow principle of least privilege
- QuickSight user permissions configured by business role
- Cost data access restricted to authorized personnel

### Compliance

- Financial data handling follows SOX and regulatory requirements
- Audit trails maintained for all data access and modifications
- Data retention policies align with organizational requirements

## Support

For issues with this infrastructure code, refer to:
1. The original recipe documentation
2. AWS service documentation
3. Provider-specific troubleshooting guides
4. AWS Support (if you have a support plan)

## License

This infrastructure code is provided as-is for educational and implementation purposes. Ensure compliance with your organization's policies and AWS service terms.