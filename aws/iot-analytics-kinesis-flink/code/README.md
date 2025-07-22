# Infrastructure as Code for Processing IoT Analytics with Kinesis and Flink

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Processing IoT Analytics with Kinesis and Flink".

## Architecture Overview

This solution creates a comprehensive real-time IoT analytics pipeline that processes streaming sensor data from manufacturing equipment. The architecture includes:

- **Amazon Kinesis Data Streams** for high-throughput data ingestion
- **Amazon Managed Service for Apache Flink** for real-time stream processing and analytics
- **AWS Lambda** for event-driven processing and anomaly detection
- **Amazon S3** for data storage and archival
- **Amazon SNS** for real-time alerting
- **CloudWatch** for monitoring and dashboards

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### Required Tools
- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Kinesis Data Streams
  - Managed Service for Apache Flink
  - Lambda functions
  - S3 buckets
  - IAM roles and policies
  - SNS topics
  - CloudWatch alarms and dashboards

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI v2 or AWS Console access
- CloudFormation stack creation permissions

#### CDK TypeScript
- Node.js (version 18 or later)
- AWS CDK v2 installed globally: `npm install -g aws-cdk`
- TypeScript: `npm install -g typescript`

#### CDK Python
- Python 3.8 or later
- AWS CDK v2 installed: `pip install aws-cdk-lib`
- Virtual environment recommended

#### Terraform
- Terraform v1.0 or later
- AWS provider configured

### Estimated Costs
- **Development/Testing**: $50-100/month for moderate data volumes
- **Production**: Scales with data throughput and retention requirements
- **Key cost factors**: Kinesis shard hours, Lambda executions, S3 storage, Flink compute units

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name iot-analytics-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com

# Wait for deployment to complete
aws cloudformation wait stack-create-complete \
    --stack-name iot-analytics-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name iot-analytics-stack \
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

# Deploy the stack
cdk deploy

# Get stack outputs
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

# Deploy the stack
cdk deploy

# Get stack outputs
cdk list
```

### Using Terraform
```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
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

# Set required environment variables
export NOTIFICATION_EMAIL="your-email@example.com"
export AWS_REGION="us-east-1"

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
aws kinesis describe-stream --stream-name iot-analytics-stream
```

## Configuration Options

### Environment Variables
All implementations support these environment variables:

```bash
# Required
export NOTIFICATION_EMAIL="your-email@example.com"    # Email for SNS alerts
export AWS_REGION="us-east-1"                         # AWS region

# Optional
export PROJECT_NAME="my-iot-analytics"                # Custom project name
export KINESIS_SHARD_COUNT="2"                        # Number of Kinesis shards
export LAMBDA_MEMORY_SIZE="256"                       # Lambda memory in MB
export S3_RETENTION_DAYS="30"                         # S3 object retention
```

### CloudFormation Parameters
```yaml
Parameters:
  NotificationEmail:
    Type: String
    Description: Email address for SNS notifications
  
  ProjectName:
    Type: String
    Default: iot-analytics
    Description: Name prefix for all resources
  
  KinesisShardCount:
    Type: Number
    Default: 2
    Description: Number of Kinesis shards
```

### Terraform Variables
```hcl
variable "notification_email" {
  description = "Email address for SNS notifications"
  type        = string
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "iot-analytics"
}

variable "kinesis_shard_count" {
  description = "Number of Kinesis shards"
  type        = number
  default     = 2
}
```

## Testing the Deployment

### 1. Verify Infrastructure
```bash
# Check Kinesis stream status
aws kinesis describe-stream --stream-name iot-analytics-stream

# Check Lambda function
aws lambda get-function --function-name iot-analytics-processor

# Check S3 bucket
aws s3 ls iot-analytics-data-bucket

# Check SNS topic
aws sns list-topics | grep iot-analytics-alerts
```

### 2. Test with Sample Data
```bash
# Send test IoT data
python3 << 'EOF'
import boto3
import json
from datetime import datetime

kinesis = boto3.client('kinesis')

# Sample IoT sensor data
sample_data = {
    'device_id': 'sensor-1001',
    'timestamp': datetime.now().isoformat(),
    'sensor_type': 'temperature',
    'value': 75.5,
    'unit': '°C',
    'location': 'factory-floor-1'
}

# Send to Kinesis
kinesis.put_record(
    StreamName='iot-analytics-stream',
    Data=json.dumps(sample_data),
    PartitionKey=sample_data['device_id']
)

print("Test data sent successfully!")
EOF
```

### 3. Monitor Processing
```bash
# Check Lambda logs
aws logs tail /aws/lambda/iot-analytics-processor --follow

# Check S3 for processed data
aws s3 ls s3://iot-analytics-data-bucket/raw-data/ --recursive

# Check CloudWatch dashboard
aws cloudwatch get-dashboard --dashboard-name iot-analytics-dashboard
```

## Monitoring and Alerting

### CloudWatch Metrics
The deployment includes monitoring for:
- Kinesis stream incoming/outgoing records
- Lambda function invocations, errors, and duration
- Flink application processing metrics
- S3 object counts and sizes

### Alarms
Configured alarms include:
- High Kinesis record volume
- Lambda function errors
- Flink application failures
- S3 storage anomalies

### Dashboard
Access the CloudWatch dashboard at:
```
https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=iot-analytics-dashboard
```

## Troubleshooting

### Common Issues

#### 1. IAM Permissions
```bash
# Check current IAM permissions
aws sts get-caller-identity
aws iam get-user

# Verify required policies are attached
aws iam list-attached-user-policies --user-name $(aws sts get-caller-identity --query 'Arn' --output text | cut -d'/' -f2)
```

#### 2. Kinesis Stream Issues
```bash
# Check stream status
aws kinesis describe-stream --stream-name iot-analytics-stream

# Monitor shard utilization
aws kinesis get-metrics --stream-name iot-analytics-stream
```

#### 3. Lambda Function Issues
```bash
# Check function configuration
aws lambda get-function-configuration --function-name iot-analytics-processor

# View recent logs
aws logs filter-log-events \
    --log-group-name /aws/lambda/iot-analytics-processor \
    --start-time $(date -d '1 hour ago' +%s)000
```

#### 4. Flink Application Issues
```bash
# Check application status
aws kinesisanalyticsv2 describe-application --application-name iot-analytics-flink

# View application metrics
aws logs filter-log-events \
    --log-group-name /aws/kinesisanalytics/iot-analytics-flink \
    --start-time $(date -d '1 hour ago' +%s)000
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name iot-analytics-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name iot-analytics-stack
```

### Using CDK
```bash
# From the CDK directory
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform
```bash
# From the terraform directory
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts
```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

### Manual Cleanup (if needed)
```bash
# Remove any remaining S3 objects
aws s3 rm s3://iot-analytics-data-bucket --recursive

# Delete S3 bucket
aws s3 rb s3://iot-analytics-data-bucket

# Remove CloudWatch log groups
aws logs delete-log-group --log-group-name /aws/lambda/iot-analytics-processor
aws logs delete-log-group --log-group-name /aws/kinesisanalytics/iot-analytics-flink
```

## Customization

### Adding New Sensor Types
To support additional sensor types, modify the Lambda function code:

1. **CloudFormation**: Update the Lambda function code in the template
2. **CDK**: Modify the Lambda function definition in the CDK code
3. **Terraform**: Update the Lambda function in `terraform/main.tf`

### Scaling Configuration
Adjust resources based on expected load:

```bash
# Increase Kinesis shards for higher throughput
export KINESIS_SHARD_COUNT=4

# Increase Lambda memory for complex processing
export LAMBDA_MEMORY_SIZE=512

# Adjust Flink parallelism for stream processing
export FLINK_PARALLELISM=4
```

### Custom Alerting
Add custom SNS topics or integrate with other notification systems:

```bash
# Add additional SNS topics
aws sns create-topic --name critical-alerts
aws sns create-topic --name maintenance-alerts

# Subscribe different endpoints
aws sns subscribe --topic-arn arn:aws:sns:region:account:critical-alerts \
    --protocol sms --notification-endpoint +1234567890
```

## Security Considerations

### IAM Best Practices
- All resources use least-privilege IAM roles
- Cross-service access is properly configured
- Service-linked roles are used where appropriate

### Data Encryption
- S3 buckets use server-side encryption
- Kinesis streams support encryption at rest
- Lambda environment variables are encrypted

### Network Security
- VPC endpoints can be configured for private connectivity
- Security groups restrict access to necessary ports
- CloudTrail logs all API calls for auditing

## Cost Optimization

### Recommendations
1. **Kinesis Shards**: Start with 2 shards, scale based on throughput
2. **Lambda Memory**: Use 256MB initially, optimize based on performance
3. **S3 Storage**: Configure lifecycle policies for cost-effective archival
4. **Flink Compute**: Use appropriate parallelism based on data volume

### Monitoring Costs
```bash
# Check current costs
aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE
```

## Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review CloudWatch logs and metrics
3. Consult the original recipe documentation
4. Reference AWS service documentation:
   - [Amazon Kinesis Data Streams](https://docs.aws.amazon.com/kinesis/latest/dev/)
   - [Amazon Managed Service for Apache Flink](https://docs.aws.amazon.com/managed-flink/latest/java/)
   - [AWS Lambda](https://docs.aws.amazon.com/lambda/latest/dg/)
   - [Amazon S3](https://docs.aws.amazon.com/s3/latest/userguide/)

## Contributing

To contribute improvements to this infrastructure code:
1. Test changes in a development environment
2. Validate with all supported deployment methods
3. Update documentation as needed
4. Follow AWS security best practices