# Infrastructure as Code for Detecting Real-time Anomalies with Kinesis Data Analytics

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Detecting Real-time Anomalies with Kinesis Data Analytics".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured
- Appropriate AWS permissions for creating Kinesis Data Streams, Managed Service for Apache Flink, CloudWatch, SNS, Lambda, S3, and IAM resources
- For CDK implementations: Node.js 18+ or Python 3.8+
- For Terraform: Terraform 1.0+
- Java 11+ and Maven for building the Flink application
- Estimated cost: $50-100/month for moderate throughput (5,000 records/minute)

## Architecture Overview

This solution implements a real-time anomaly detection system using:

- **Kinesis Data Streams**: High-throughput data ingestion
- **Managed Service for Apache Flink**: Real-time stream processing and anomaly detection
- **CloudWatch**: Monitoring, metrics, and anomaly detection
- **SNS**: Alert notifications
- **Lambda**: Event processing and alert routing
- **S3**: Application artifact storage

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name anomaly-detection-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name anomaly-detection-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name anomaly-detection-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure email for notifications
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk ls
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure email for notifications
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk ls
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="notification_email=your-email@example.com"

# Apply the configuration
terraform apply -var="notification_email=your-email@example.com"

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy the infrastructure
./scripts/deploy.sh

# The script will output resource ARNs and configuration details
```

## Post-Deployment Setup

After deploying the infrastructure, complete these additional steps:

### 1. Build and Deploy the Flink Application

```bash
# Clone or download the Flink application code
# (Generated as part of the deployment process)

# Build the application
cd flink-application/
mvn clean package

# Upload to S3 (bucket name from stack outputs)
aws s3 cp target/anomaly-detection-1.0-SNAPSHOT.jar \
    s3://YOUR-BUCKET-NAME/applications/

# Start the Flink application
aws kinesisanalyticsv2 start-application \
    --application-name YOUR-FLINK-APP-NAME \
    --run-configuration '{"FlinkRunConfiguration": {"AllowNonRestoredState": true}}'
```

### 2. Confirm SNS Email Subscription

Check your email for an SNS subscription confirmation and click the confirmation link.

### 3. Test the System

```bash
# Generate test data using the provided script
python scripts/generate-test-data.py YOUR-STREAM-NAME

# Monitor CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace "AnomalyDetection" \
    --metric-name "AnomalyCount" \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Configuration Options

### CloudFormation Parameters

- `NotificationEmail`: Email address for anomaly alerts
- `StreamShardCount`: Number of Kinesis shards (default: 2)
- `FlinkParallelism`: Flink application parallelism (default: 2)
- `AnomalyThreshold`: Threshold multiplier for anomaly detection (default: 3.0)

### CDK Context Variables

Set these in `cdk.json` or pass via command line:

```json
{
  "notificationEmail": "your-email@example.com",
  "streamShardCount": 2,
  "flinkParallelism": 2,
  "anomalyThreshold": 3.0
}
```

### Terraform Variables

Configure in `terraform.tfvars`:

```hcl
notification_email = "your-email@example.com"
stream_shard_count = 2
flink_parallelism = 2
anomaly_threshold = 3.0
aws_region = "us-east-1"
```

## Monitoring and Troubleshooting

### CloudWatch Dashboards

The deployment creates CloudWatch dashboards for monitoring:

- **Kinesis Metrics**: Stream throughput, iterator age, record processing
- **Flink Metrics**: Application health, checkpointing, processing latency
- **Anomaly Detection**: Detection rate, alert frequency, system health

### Log Locations

- **Flink Application Logs**: `/aws/kinesis-analytics/YOUR-APP-NAME`
- **Lambda Function Logs**: `/aws/lambda/YOUR-FUNCTION-NAME`
- **CloudWatch Logs**: Custom metrics and alarms

### Common Issues

1. **Flink Application Won't Start**
   - Check IAM permissions for the Flink service role
   - Verify S3 bucket access and JAR file location
   - Review application logs for specific error messages

2. **No Anomalies Detected**
   - Verify data is flowing into Kinesis stream
   - Check anomaly threshold configuration
   - Review test data patterns and generation rate

3. **Missing Email Alerts**
   - Confirm SNS subscription is active
   - Check Lambda function execution logs
   - Verify CloudWatch alarm configuration

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name anomaly-detection-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name anomaly-detection-stack
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy
```

### Using Terraform
```bash
cd terraform/
terraform destroy -var="notification_email=your-email@example.com"
```

### Using Bash Scripts
```bash
./scripts/destroy.sh
```

## Security Considerations

The infrastructure implements security best practices:

- **IAM Roles**: Least privilege access for all services
- **Encryption**: Data encrypted in transit and at rest
- **VPC**: Optional VPC deployment for network isolation
- **Resource Policies**: Service-specific access controls
- **CloudTrail Integration**: API call logging and monitoring

## Cost Optimization

To optimize costs:

1. **Right-size Kinesis Shards**: Start with 1-2 shards and scale based on throughput
2. **Flink Application Sizing**: Adjust parallelism based on processing requirements
3. **Data Retention**: Configure appropriate retention periods for logs and metrics
4. **Reserved Capacity**: Consider reserved instances for predictable workloads

## Performance Tuning

For production deployments:

1. **Kinesis Configuration**: Optimize shard count and record aggregation
2. **Flink Settings**: Tune checkpoint intervals, parallelism, and buffer sizes
3. **CloudWatch Metrics**: Adjust metric resolution and alarm sensitivity
4. **Lambda Concurrency**: Set appropriate concurrent execution limits

## Customization

### Adding New Data Sources

1. Update Kinesis stream configuration
2. Modify Flink application for new data formats
3. Adjust anomaly detection algorithms
4. Update monitoring and alerting

### Enhanced Anomaly Detection

1. Integrate with Amazon SageMaker for ML-based detection
2. Implement multi-dimensional analysis
3. Add historical pattern learning
4. Create custom detection algorithms

### Integration Options

- **Slack Notifications**: Add Slack webhook integration
- **PagerDuty**: Configure incident management integration  
- **Custom Dashboards**: Build Grafana or QuickSight dashboards
- **Data Lake**: Add Kinesis Data Firehose for historical analysis

## Support

For issues with this infrastructure code:

1. Review the [original recipe documentation](../real-time-anomaly-detection-kinesis-data-analytics.md)
2. Check AWS service documentation for specific services
3. Review CloudWatch logs for detailed error information
4. Consult AWS support for service-specific issues

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment
2. Update documentation for any new parameters or outputs
3. Follow AWS security and cost optimization best practices
4. Validate all IaC templates before deployment