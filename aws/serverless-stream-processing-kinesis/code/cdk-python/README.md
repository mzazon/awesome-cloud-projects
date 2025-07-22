# CDK Python - Real-time Data Processing with Kinesis and Lambda

This CDK Python application deploys a complete serverless real-time data processing pipeline using Amazon Kinesis Data Streams and AWS Lambda.

## Architecture

The application creates the following AWS resources:

- **Amazon Kinesis Data Stream**: Multi-shard stream for high-throughput data ingestion
- **AWS Lambda Function**: Serverless data processor with automatic scaling
- **Amazon S3 Bucket**: Storage for processed data with lifecycle policies
- **IAM Roles**: Least privilege access for Lambda execution
- **CloudWatch Logs**: Centralized logging with retention policies
- **Event Source Mapping**: Connects Kinesis stream to Lambda function

## Prerequisites

- Python 3.8 or later
- AWS CLI configured with appropriate permissions
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- Virtual environment (recommended)

## Required AWS Permissions

Your AWS credentials must have permissions for:
- IAM role creation and policy attachment
- Kinesis stream creation and management
- Lambda function creation and configuration
- S3 bucket creation and object management
- CloudWatch logs creation

## Installation

1. **Clone and navigate to the project directory**:
   ```bash
   cd aws/real-time-data-processing-kinesis-lambda/code/cdk-python/
   ```

2. **Create and activate a virtual environment**:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Bootstrap CDK (first time only)**:
   ```bash
   cdk bootstrap
   ```

## Configuration

The application uses context values defined in `cdk.json`. You can override these values:

### Default Configuration
- **Stream Name**: `realtime-data-stream`
- **Shard Count**: 3
- **Lambda Timeout**: 60 seconds
- **Lambda Memory**: 256 MB
- **Batch Size**: 100 records
- **Max Batching Window**: 5 seconds

### Custom Configuration

Override context values using CDK context flags:

```bash
cdk deploy -c stream_name=my-custom-stream -c shard_count=5 -c lambda_memory=512
```

Or set environment-specific values:

```bash
cdk deploy -c environment=production -c shard_count=10
```

## Deployment

1. **Review the resources that will be created**:
   ```bash
   cdk diff
   ```

2. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

3. **Confirm deployment** when prompted (or use `--require-approval never`)

## Testing the Pipeline

After deployment, you can test the pipeline using the included data generator:

1. **Create a test data generator**:
   ```python
   # data_generator.py
   import boto3
   import json
   import time
   import random
   from datetime import datetime
   
   kinesis_client = boto3.client('kinesis')
   STREAM_NAME = 'realtime-data-stream'  # Use your stream name
   
   def generate_sample_data():
       return {
           "device_id": f"device_{random.randint(1, 100)}",
           "temperature": round(random.uniform(18.0, 35.0), 2),
           "humidity": round(random.uniform(30.0, 80.0), 2),
           "timestamp": datetime.utcnow().isoformat(),
           "location": {
               "lat": round(random.uniform(-90, 90), 6),
               "lon": round(random.uniform(-180, 180), 6)
           },
           "battery_level": random.randint(10, 100)
       }
   
   def send_records_to_kinesis(num_records=50):
       for i in range(num_records):
           data = generate_sample_data()
           kinesis_client.put_record(
               StreamName=STREAM_NAME,
               Data=json.dumps(data),
               PartitionKey=data['device_id']
           )
           time.sleep(0.1)
   
   if __name__ == "__main__":
       send_records_to_kinesis()
   ```

2. **Run the data generator**:
   ```bash
   python data_generator.py
   ```

3. **Monitor the pipeline**:
   ```bash
   # Check Lambda logs
   aws logs tail /aws/lambda/kinesis-data-processor --follow
   
   # Check processed data in S3
   aws s3 ls s3://processed-data-{account}-{region}/processed-data/ --recursive
   ```

## Monitoring and Observability

### CloudWatch Metrics

Monitor key metrics through the AWS Console or CLI:

- **Kinesis**: IncomingRecords, IncomingBytes, IteratorAge
- **Lambda**: Invocations, Duration, Errors, Throttles
- **S3**: ObjectCount, BucketSize

### CloudWatch Logs

View function logs:
```bash
aws logs filter-log-events \
  --log-group-name /aws/lambda/kinesis-data-processor \
  --start-time $(date -d '1 hour ago' +%s)000
```

### Custom Dashboards

Create CloudWatch dashboards to visualize:
- Data processing throughput
- Lambda function performance
- Error rates and retry patterns
- Cost optimization metrics

## Customization

### Modifying the Lambda Function

The Lambda function code is embedded in the CDK stack. To modify processing logic:

1. Edit the `lambda_code` variable in `real_time_data_processing_stack.py`
2. Redeploy the stack: `cdk deploy`

### Adding More Processing Steps

Extend the pipeline by adding:
- Additional Lambda functions for different processing stages
- DynamoDB tables for real-time aggregations
- SNS notifications for alerts
- Kinesis Analytics for stream analytics

### Security Enhancements

For production deployments:
- Enable VPC configuration for Lambda
- Use AWS KMS for encryption
- Implement resource-based policies
- Add WAF protection for API endpoints
- Enable AWS Config for compliance monitoring

## Troubleshooting

### Common Issues

1. **Permission Errors**:
   ```bash
   # Check IAM policies
   aws iam get-role --role-name RealTimeDataProcessingStack-LambdaExecutionRole*
   ```

2. **Lambda Timeouts**:
   ```bash
   # Increase timeout in cdk.json
   "lambda_timeout": 300
   ```

3. **Memory Issues**:
   ```bash
   # Increase memory allocation
   "lambda_memory": 512
   ```

4. **High Iterator Age**:
   - Increase shard count
   - Optimize Lambda function performance
   - Adjust batch size and batching window

### Debug Mode

Enable verbose logging:
```bash
export CDK_DEBUG=true
cdk deploy --verbose
```

## Cost Optimization

### Kinesis Costs
- **Shard Hours**: $0.015 per shard per hour
- **PUT Payload Units**: $0.014 per million units
- **Extended Retention**: Additional charges for > 24 hours

### Lambda Costs
- **Requests**: $0.20 per 1M requests
- **Duration**: $0.0000166667 per GB-second
- **Optimize**: Right-size memory allocation

### S3 Costs
- **Storage**: Varies by storage class
- **Lifecycle Policies**: Automatically transition to cheaper storage
- **Requests**: Optimize batch sizes

## Cleanup

To avoid ongoing charges, destroy the stack:

```bash
cdk destroy
```

**Note**: This will delete all resources including data in S3. Export important data before cleanup.

## Development

### Code Quality

Run code quality checks:
```bash
# Format code
black .
isort .

# Lint code
flake8 .

# Type checking
mypy .
```

### Testing

Run unit tests:
```bash
pytest tests/ -v --cov=.
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes with tests
4. Submit a pull request

## Support

For issues and questions:
- Review AWS CDK documentation
- Check AWS service documentation
- Open GitHub issues for bugs
- Use AWS Support for production issues

## License

This project is licensed under the MIT License - see the LICENSE file for details.