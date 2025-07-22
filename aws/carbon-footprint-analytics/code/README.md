# Infrastructure as Code for Intelligent Sustainability Dashboards

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Carbon Footprint Analytics with QuickSight".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution creates an automated sustainability intelligence platform that:

- Collects carbon footprint data from AWS Customer Carbon Footprint Tool
- Correlates emissions data with cost optimization opportunities
- Processes data through Lambda functions with automated scheduling
- Stores analytics data in S3 with intelligent partitioning
- Visualizes insights through Amazon QuickSight dashboards
- Provides monitoring and alerting through CloudWatch

## Prerequisites

- AWS account with billing access and appropriate permissions for:
  - Cost Management Console access
  - QuickSight Standard edition permissions
  - Lambda execution and S3 access permissions
  - IAM role and policy creation permissions
  - EventBridge and CloudWatch permissions
- AWS CLI installed and configured (or AWS CloudShell)
- Basic understanding of AWS sustainability concepts and carbon footprint methodology
- Knowledge of data visualization principles and QuickSight dashboard creation
- Estimated cost: $50-100/month for QuickSight Standard edition, Lambda executions, and S3 storage

> **Important**: This recipe follows AWS Well-Architected Framework sustainability principles. Review the [AWS Well-Architected Framework Sustainability Pillar](https://docs.aws.amazon.com/wellarchitected/latest/sustainability-pillar/) for comprehensive guidance.

## Quick Start

### Using CloudFormation (AWS)

Deploy the complete sustainability analytics infrastructure:

```bash
aws cloudformation create-stack \
    --stack-name sustainability-dashboard-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=BucketName,ParameterValue=sustainability-analytics-$(date +%s) \
                 ParameterKey=Environment,ParameterValue=production
```

Monitor deployment progress:

```bash
aws cloudformation describe-stack-events \
    --stack-name sustainability-dashboard-stack \
    --query 'StackEvents[?ResourceStatus==`CREATE_COMPLETE`]'
```

### Using CDK TypeScript (AWS)

Install dependencies and deploy:

```bash
cd cdk-typescript/
npm install
npm run build
```

Configure your AWS environment and deploy:

```bash
# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the sustainability dashboard stack
cdk deploy SustainabilityDashboardStack \
    --parameters bucketName=sustainability-analytics-$(date +%s) \
    --parameters environment=production
```

View deployment outputs:

```bash
cdk describe SustainabilityDashboardStack
```

### Using CDK Python (AWS)

Set up Python environment and install dependencies:

```bash
cd cdk-python/
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

Deploy the infrastructure:

```bash
# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy with custom parameters
cdk deploy \
    -c bucket_name=sustainability-analytics-$(date +%s) \
    -c environment=production
```

### Using Terraform

Initialize and deploy the infrastructure:

```bash
cd terraform/
terraform init
```

Create a terraform.tfvars file:

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values
```

Plan and apply the deployment:

```bash
# Review planned changes
terraform plan

# Apply the infrastructure
terraform apply
```

Verify deployment:

```bash
terraform output
```

### Using Bash Scripts

Make scripts executable and deploy:

```bash
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy with environment configuration
./scripts/deploy.sh production
```

The deployment script will:
1. Create all required AWS resources
2. Configure automated data collection
3. Set up monitoring and alerting
4. Provide QuickSight setup instructions

## Post-Deployment Configuration

### QuickSight Setup

After infrastructure deployment, complete these QuickSight configuration steps:

1. **Sign up for QuickSight** (if not already configured):
   - Navigate to QuickSight service in AWS Console
   - Choose Standard edition ($18/month per user)
   - Grant S3 access permissions during setup
   - Enable access to Cost Explorer data

2. **Create Data Source**:
   - Go to QuickSight Console: `https://{region}.quicksight.aws.amazon.com/`
   - Click "Datasets" → "New dataset" → "S3"
   - Upload manifest file from your S3 bucket
   - Name: "Sustainability Analytics Dataset"

3. **Build Dashboard Visualizations**:
   - Time series charts for cost trends by service
   - Bar charts for regional cost comparisons
   - KPI cards for optimization opportunities
   - Heat maps for service-region carbon intensity

4. **Configure Refresh Schedule**:
   - Set monthly refresh to align with AWS carbon footprint data
   - Configure incremental refresh for cost data

### Testing the Solution

1. **Verify Lambda Function**:
   ```bash
   aws lambda invoke \
       --function-name sustainability-data-processor-* \
       --payload '{"bucket_name":"your-bucket-name","trigger_source":"test"}' \
       test-response.json
   
   cat test-response.json
   ```

2. **Check S3 Data Collection**:
   ```bash
   aws s3 ls s3://your-sustainability-bucket/sustainability-analytics/ --recursive
   ```

3. **Monitor CloudWatch Alarms**:
   ```bash
   aws cloudwatch describe-alarms \
       --alarm-names "SustainabilityDataProcessingFailure-*" \
       --query 'MetricAlarms[0].{State:StateValue,Threshold:Threshold}'
   ```

## Customization

### Environment Variables

The solution supports customization through these key parameters:

- **BucketName**: Name for the sustainability analytics data lake
- **Environment**: Deployment environment (development, staging, production)
- **DataRetentionDays**: How long to retain processed data (default: 2555 days / 7 years)
- **ProcessingFrequency**: How often to collect data (default: monthly)
- **AlertEmail**: Email address for sustainability alerts

### Cost Optimization

To optimize costs for this solution:

1. **S3 Storage Classes**: Configure intelligent tiering for long-term data
2. **Lambda Memory**: Adjust based on actual processing requirements
3. **QuickSight Usage**: Use Standard edition and monitor user access
4. **CloudWatch Logs**: Set appropriate log retention periods
5. **Monitoring**: Use custom metrics sparingly to control costs

### Security Best Practices

The solution implements these security controls:

- **Least Privilege IAM**: Minimal permissions for each component
- **Encryption**: S3 and Lambda use AWS managed encryption
- **VPC Integration**: Optional VPC deployment for enhanced security
- **Access Logging**: CloudTrail integration for audit trails
- **Resource Tagging**: Comprehensive tagging for governance

## Monitoring and Troubleshooting

### CloudWatch Dashboards

The solution creates dashboards for:
- Lambda function performance and errors
- S3 data ingestion metrics
- Cost Explorer API usage
- QuickSight refresh status

### Common Issues

1. **Lambda Timeout**: Increase timeout if processing large datasets
2. **S3 Access Errors**: Verify IAM permissions for bucket access
3. **Cost Explorer Limits**: Monitor API throttling and implement backoff
4. **QuickSight Refresh Failures**: Check data source connectivity

### Log Locations

- **Lambda Logs**: `/aws/lambda/sustainability-data-processor-*`
- **EventBridge Logs**: Monitor rule execution history
- **S3 Access Logs**: Enable for detailed access monitoring
- **CloudWatch Metrics**: Custom namespace `SustainabilityAnalytics`

## Cleanup

### Using CloudFormation (AWS)

```bash
aws cloudformation delete-stack --stack-name sustainability-dashboard-stack
```

Monitor deletion:

```bash
aws cloudformation describe-stack-events \
    --stack-name sustainability-dashboard-stack \
    --query 'StackEvents[?ResourceStatus==`DELETE_COMPLETE`]'
```

### Using CDK (AWS)

```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy SustainabilityDashboardStack
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual QuickSight Cleanup

QuickSight resources must be deleted manually:

1. Navigate to QuickSight Console: `https://{region}.quicksight.aws.amazon.com/`
2. Delete dashboard: `sustainability-dashboard-*`
3. Delete dataset: `sustainability-analytics-*`
4. Delete data source: `sustainability-analytics-*`

> **Warning**: QuickSight charges continue until resources are explicitly deleted.

## Support and Documentation

### AWS Documentation References

- [AWS Customer Carbon Footprint Tool](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/tracking-carbon-emissions.html)
- [Amazon QuickSight User Guide](https://docs.aws.amazon.com/quicksight/)
- [AWS Cost Explorer API Reference](https://docs.aws.amazon.com/aws-cost-management/latest/APIReference/)
- [AWS Well-Architected Sustainability Pillar](https://docs.aws.amazon.com/wellarchitected/latest/sustainability-pillar/)

### Best Practices

- Review carbon footprint data monthly when AWS updates are available
- Correlate cost optimization with sustainability impact
- Use QuickSight's machine learning insights for anomaly detection
- Implement automated alerting for sustainability threshold breaches
- Regular review of cost optimization recommendations

### Contributing

For issues with this infrastructure code:
1. Check AWS service limits and quotas
2. Verify IAM permissions and resource access
3. Review CloudWatch logs for detailed error information
4. Consult the original recipe documentation for implementation details

## Version Information

- **Recipe Version**: 1.0
- **Last Updated**: 2025-07-12
- **AWS CLI Version**: 2.0+
- **CDK Version**: 2.0+
- **Terraform Version**: 1.0+
- **Python Version**: 3.9+ (for CDK Python and Lambda functions)
- **Node.js Version**: 18+ (for CDK TypeScript)

This infrastructure code follows AWS best practices for security, scalability, and cost optimization while enabling comprehensive sustainability analytics and reporting capabilities.