# Real-time Anomaly Detection CDK Python Application

This AWS CDK Python application deploys a complete real-time anomaly detection system using Amazon Kinesis Data Analytics (Managed Service for Apache Flink) and supporting AWS services.

## Architecture Overview

The application creates the following AWS resources:

- **Amazon Kinesis Data Streams**: Ingests streaming transaction data
- **AWS Managed Service for Apache Flink**: Processes data and detects anomalies in real-time
- **AWS Lambda**: Processes anomaly alerts and sends notifications
- **Amazon SNS**: Distributes alerts to stakeholders
- **Amazon CloudWatch**: Monitors system health and provides dashboards
- **Amazon S3**: Stores application artifacts and processed data
- **IAM Roles and Policies**: Provides secure access between services

## Prerequisites

Before deploying this application, ensure you have:

1. **AWS CLI** installed and configured with appropriate credentials
2. **AWS CDK** installed (`npm install -g aws-cdk`)
3. **Python 3.8+** installed
4. **pip** for Python package management
5. **Docker** (optional, for local testing)

### Required AWS Permissions

Your AWS account/user needs permissions for:
- Kinesis Data Streams and Analytics
- Lambda functions
- SNS topics and subscriptions
- CloudWatch metrics and alarms
- S3 buckets and objects
- IAM roles and policies

## Installation and Setup

### 1. Clone and Navigate to the Project

```bash
git clone <repository-url>
cd aws/real-time-anomaly-detection-kinesis-data-analytics/code/cdk-python/
```

### 2. Create Python Virtual Environment

```bash
# Create virtual environment
python -m venv .venv

# Activate virtual environment
# On Windows:
.venv\Scripts\activate
# On macOS/Linux:
source .venv/bin/activate
```

### 3. Install Dependencies

```bash
# Upgrade pip
pip install --upgrade pip

# Install requirements
pip install -r requirements.txt
```

### 4. Bootstrap CDK (First-time setup)

```bash
# Bootstrap CDK in your AWS account/region
cdk bootstrap

# Verify CDK version
cdk --version
```

## Deployment

### 1. Synthesize CloudFormation Template

```bash
# Generate CloudFormation template
cdk synth

# View the generated template
cdk synth --output cdk.out
```

### 2. Deploy the Stack

```bash
# Deploy all resources
cdk deploy

# Deploy with approval for IAM changes
cdk deploy --require-approval never

# Deploy to specific environment
cdk deploy --profile my-aws-profile
```

### 3. Verify Deployment

After deployment, the CDK will output important resource identifiers:

```
✅  AnomalyDetectionStack

Outputs:
AnomalyDetectionStack.TransactionStreamName = transaction-stream-abc12345
AnomalyDetectionStack.FlinkApplicationName = anomaly-detector-abc12345
AnomalyDetectionStack.AlertsTopicArn = arn:aws:sns:us-east-1:123456789012:anomaly-alerts-abc12345
AnomalyDetectionStack.ArtifactsBucketName = anomaly-detection-artifacts-abc12345
```

## Configuration

### Environment Variables

The application supports the following environment variables:

```bash
# AWS account and region (automatically detected)
export CDK_DEFAULT_ACCOUNT="123456789012"
export CDK_DEFAULT_REGION="us-east-1"

# Application-specific settings
export ANOMALY_DETECTION_EMAIL="alerts@company.com"
export FLINK_PARALLELISM="2"
export KINESIS_SHARD_COUNT="2"
```

### Customization

You can customize the deployment by modifying the following in `app.py`:

- **Stream shard count**: Adjust throughput capacity
- **Flink parallelism**: Control processing parallelism
- **Alarm thresholds**: Modify alerting sensitivity
- **Resource naming**: Change naming patterns

## Usage

### 1. Subscribe to Alerts

```bash
# Get the SNS topic ARN from stack outputs
TOPIC_ARN=$(aws cloudformation describe-stacks \
  --stack-name AnomalyDetectionStack \
  --query 'Stacks[0].Outputs[?OutputKey==`AlertsTopicArn`].OutputValue' \
  --output text)

# Subscribe your email to alerts
aws sns subscribe \
  --topic-arn $TOPIC_ARN \
  --protocol email \
  --notification-endpoint your-email@company.com
```

### 2. Send Test Data

Create a simple data generator:

```python
import json
import boto3
import random
import time

def send_test_data():
    kinesis = boto3.client('kinesis')
    stream_name = 'transaction-stream-abc12345'  # Use your stream name
    
    for i in range(100):
        # Generate realistic transaction data
        transaction = {
            'userId': f'user{random.randint(1, 10)}',
            'amount': random.uniform(10, 5000),  # Include some anomalies
            'timestamp': int(time.time() * 1000),
            'transactionId': f'txn_{i}',
            'merchantId': f'merchant_{random.randint(1, 50)}'
        }
        
        kinesis.put_record(
            StreamName=stream_name,
            Data=json.dumps(transaction),
            PartitionKey=transaction['userId']
        )
        
        print(f"Sent transaction: {transaction}")
        time.sleep(0.1)

if __name__ == "__main__":
    send_test_data()
```

### 3. Monitor the System

- **CloudWatch Dashboard**: View real-time metrics
- **CloudWatch Logs**: Monitor Flink application logs
- **SNS Notifications**: Receive anomaly alerts via email

## Monitoring and Troubleshooting

### CloudWatch Metrics

Key metrics to monitor:

- `AnomalyDetection.AnomalyCount`: Number of detected anomalies
- `AWS/Kinesis.IncomingRecords`: Data ingestion rate
- `AWS/KinesisAnalytics.KPUs`: Processing unit utilization

### Common Issues

1. **Flink Application Not Starting**
   - Check IAM permissions
   - Verify S3 bucket contains application JAR
   - Review CloudWatch logs

2. **No Anomalies Detected**
   - Verify test data format
   - Check Flink application processing logic
   - Review detection thresholds

3. **High Costs**
   - Monitor KPU usage in CloudWatch
   - Optimize Flink parallelism settings
   - Consider data retention policies

### Debugging Commands

```bash
# Check stack status
cdk list
cdk diff

# View CloudFormation events
aws cloudformation describe-stack-events --stack-name AnomalyDetectionStack

# Check Flink application status
aws kinesisanalyticsv2 describe-application --application-name anomaly-detector-abc12345
```

## Cleanup

To avoid ongoing charges, destroy the stack when finished:

```bash
# Destroy all resources
cdk destroy

# Confirm destruction
cdk destroy --force
```

**Note**: S3 buckets with versioning enabled may require manual cleanup.

## Development

### Code Style and Linting

```bash
# Format code with Black
black app.py

# Lint with flake8
flake8 app.py

# Type checking with mypy
mypy app.py

# Security scanning
bandit -r .
```

### Testing

```bash
# Run unit tests
pytest tests/

# Run with coverage
pytest --cov=app tests/

# Run integration tests
pytest tests/integration/
```

### Adding New Features

1. Modify the stack in `app.py`
2. Update requirements if needed
3. Test locally with `cdk synth`
4. Deploy changes with `cdk deploy`

## Cost Optimization

### Estimated Costs

- **Kinesis Data Streams**: ~$15/month (2 shards)
- **Managed Service for Apache Flink**: ~$80/month (2 KPUs)
- **Lambda**: <$1/month (low invocation volume)
- **SNS**: <$1/month
- **CloudWatch**: ~$5/month
- **S3**: <$1/month

**Total**: ~$100/month for moderate throughput

### Optimization Tips

1. **Right-size resources**: Match shard count and KPUs to actual throughput
2. **Use reserved capacity**: For predictable workloads
3. **Optimize data retention**: Reduce Kinesis retention period if possible
4. **Monitor unused resources**: Regular cost analysis

## Security Considerations

- **IAM Least Privilege**: All roles follow minimum required permissions
- **Encryption**: Data encrypted in transit and at rest
- **VPC Support**: Can be deployed within VPC for network isolation
- **Access Logging**: CloudTrail integration for audit trails

## Support and Contributing

For issues or questions:

1. Check CloudWatch logs for error details
2. Review AWS documentation for service limits
3. Consult CDK documentation for construct usage
4. Open GitHub issues for bugs or feature requests

## License

This project is licensed under the MIT License. See LICENSE file for details.

## Additional Resources

- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
- [Kinesis Data Analytics Documentation](https://docs.aws.amazon.com/kinesisanalytics/)
- [Apache Flink Documentation](https://flink.apache.org/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)