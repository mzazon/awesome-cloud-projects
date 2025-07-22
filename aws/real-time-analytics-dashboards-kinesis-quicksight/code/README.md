# Infrastructure as Code for Building Real-time Analytics Dashboards with Kinesis Analytics and QuickSight

This directory contains Infrastructure as Code (IaC) implementations for the recipe Building Real-time Analytics Dashboards with Kinesis Analytics and QuickSight.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a complete real-time analytics pipeline that:

- Ingests streaming data using Amazon Kinesis Data Streams
- Processes data in real-time with Amazon Managed Service for Apache Flink
- Stores processed analytics in Amazon S3
- Visualizes real-time metrics with Amazon QuickSight dashboards

## Prerequisites

- AWS CLI v2 installed and configured with appropriate credentials
- AWS account with permissions for:
  - Kinesis Data Streams
  - Managed Service for Apache Flink (Kinesis Analytics v2)
  - S3
  - QuickSight
  - IAM roles and policies
  - CloudWatch Logs
- For CDK deployments: Node.js 18+ and npm
- For CDK Python: Python 3.8+ and pip
- For Terraform: Terraform 1.0+
- Appropriate AWS permissions for resource creation
- Estimated cost: $50-100/month for moderate data volumes (1GB/day processing)

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure stack
aws cloudformation create-stack \
    --stack-name real-time-analytics-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=EnvironmentName,ParameterValue=dev

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name real-time-analytics-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name real-time-analytics-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# View outputs
cdk list
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

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

# Apply the infrastructure
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

# Monitor deployment progress
# The script will provide status updates and resource information
```

## Post-Deployment Setup

### QuickSight Configuration

After infrastructure deployment, complete QuickSight setup manually:

1. **Access QuickSight Console**:
   - Navigate to AWS QuickSight in your target region
   - Sign up for QuickSight if not already configured

2. **Create Data Source**:
   - Create new data source pointing to the deployed S3 bucket
   - Use the QuickSight manifest file uploaded during deployment
   - Select JSON format for data parsing

3. **Create Dataset**:
   - Create dataset from the analytics-results/ folder
   - Configure automatic refresh for real-time updates
   - Set appropriate refresh intervals (1-5 minutes)

4. **Build Dashboard**:
   - Create visualizations for real-time metrics
   - Configure auto-refresh settings
   - Set up threshold-based alerts

### Data Generation Testing

Use the included sample data generator to test the pipeline:

```bash
# Generate sample streaming data
python3 scripts/generate_sample_data.py

# Monitor data flow through CloudWatch
aws logs tail /aws/kinesis-analytics/[FlinkAppName] --follow
```

## Validation & Testing

### Verify Kinesis Data Stream

```bash
# Check stream status
aws kinesis describe-stream --stream-name [StreamName]

# List recent records
aws kinesis get-records --shard-iterator [ShardIterator]
```

### Verify Flink Application

```bash
# Check application status
aws kinesisanalyticsv2 describe-application --application-name [FlinkAppName]

# Monitor application logs
aws logs describe-log-groups --log-group-name-prefix "/aws/kinesis-analytics/"
```

### Verify S3 Data Processing

```bash
# List processed analytics files
aws s3 ls s3://[AnalyticsBucket]/analytics-results/ --recursive

# Download sample processed data
aws s3 cp s3://[AnalyticsBucket]/analytics-results/ . --recursive
```

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name real-time-analytics-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name real-time-analytics-stack
```

### Using CDK

```bash
# Navigate to CDK directory (TypeScript or Python)
cd cdk-typescript/  # or cd cdk-python/

# Destroy the infrastructure
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Customization

### Configuration Parameters

Each implementation supports customization through variables:

- **Environment Name**: Prefix for resource naming
- **Stream Shard Count**: Number of Kinesis shards (affects throughput)
- **Flink Parallelism**: Processing parallelism for the Flink application
- **S3 Lifecycle**: Data retention and archival policies
- **Monitoring Level**: CloudWatch logging and metrics detail

### CloudFormation Parameters

```yaml
Parameters:
  EnvironmentName:
    Type: String
    Default: dev
  StreamShardCount:
    Type: Number
    Default: 2
  FlinkParallelism:
    Type: Number
    Default: 1
```

### CDK Configuration

```typescript
// cdk-typescript/lib/config.ts
export const config = {
  environmentName: 'dev',
  streamShardCount: 2,
  flinkParallelism: 1,
  enableAutoScaling: true
};
```

### Terraform Variables

```hcl
# terraform/variables.tf
variable "environment_name" {
  description = "Environment name for resource naming"
  type        = string
  default     = "dev"
}

variable "stream_shard_count" {
  description = "Number of Kinesis shards"
  type        = number
  default     = 2
}
```

## Security Considerations

This implementation follows AWS security best practices:

- **IAM Roles**: Least privilege access for all services
- **S3 Encryption**: Server-side encryption enabled by default
- **VPC Configuration**: Network isolation where applicable
- **Access Logging**: Comprehensive logging for audit trails
- **Resource Tagging**: Consistent tagging for governance

## Cost Optimization

### Expected Costs

- **Kinesis Data Streams**: ~$15/month (2 shards)
- **Managed Service for Apache Flink**: ~$20-40/month (1 KPU)
- **S3 Storage**: ~$5/month (moderate data volume)
- **QuickSight**: ~$12/month (Standard Edition)
- **Data Transfer**: ~$5/month (regional transfer)

### Cost Optimization Tips

1. **Right-size Kinesis Shards**: Monitor utilization and adjust shard count
2. **Configure S3 Lifecycle**: Archive older data to IA/Glacier storage classes
3. **Optimize Flink Parallelism**: Use auto-scaling to reduce costs during low traffic
4. **QuickSight SPICE**: Cache frequently accessed data to reduce query costs

## Monitoring and Observability

### CloudWatch Metrics

Monitor these key metrics:

- **Kinesis**: IncomingRecords, WriteProvisionedThroughputExceeded
- **Flink**: Uptime, CheckpointDuration, BackPressure
- **S3**: NumberOfObjects, BucketSizeBytes
- **Application**: Custom business metrics

### Logging

Comprehensive logging is configured for:

- Flink application logs (CloudWatch Logs)
- Kinesis Data Streams metrics
- S3 access logs
- QuickSight usage logs

### Alerting

Set up CloudWatch alarms for:

- Flink application failures
- Kinesis throttling
- S3 storage growth
- Dashboard refresh failures

## Troubleshooting

### Common Issues

1. **Flink Application Won't Start**:
   - Check IAM role permissions
   - Verify S3 bucket accessibility
   - Review application logs in CloudWatch

2. **No Data in QuickSight**:
   - Verify S3 data is being written
   - Check QuickSight manifest configuration
   - Ensure proper data source permissions

3. **High Costs**:
   - Review Kinesis shard utilization
   - Optimize Flink parallelism settings
   - Configure S3 lifecycle policies

### Debug Commands

```bash
# Check Flink application logs
aws logs tail /aws/kinesis-analytics/[AppName] --follow

# Verify Kinesis metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Kinesis \
    --metric-name IncomingRecords \
    --dimensions Name=StreamName,Value=[StreamName]

# Test S3 connectivity
aws s3 ls s3://[BucketName] --recursive
```

## Support

For issues with this infrastructure code:

1. Refer to the original recipe documentation
2. Check AWS service documentation:
   - [Kinesis Data Streams Developer Guide](https://docs.aws.amazon.com/kinesis/latest/dev/)
   - [Managed Service for Apache Flink Developer Guide](https://docs.aws.amazon.com/managed-flink/latest/java/what-is.html)
   - [QuickSight User Guide](https://docs.aws.amazon.com/quicksight/latest/user/)
3. Review CloudWatch logs and metrics
4. Check AWS Service Health Dashboard for service issues

## Additional Resources

- [Apache Flink Documentation](https://flink.apache.org/documentation.html)
- [Real-time Analytics Best Practices](https://aws.amazon.com/big-data/datalakes-and-analytics/real-time-analytics/)
- [Kinesis Data Streams Pricing](https://aws.amazon.com/kinesis/data-streams/pricing/)
- [QuickSight Pricing](https://aws.amazon.com/quicksight/pricing/)