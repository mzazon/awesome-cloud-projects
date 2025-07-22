# IoT Analytics Pipelines CDK Python Application

This CDK Python application demonstrates building IoT analytics pipelines using AWS IoT Analytics and provides a modern alternative using Kinesis Data Streams and Amazon Timestream.

## Architecture Overview

The application creates two parallel pipelines:

1. **Legacy Pipeline (IoT Analytics)**: Uses AWS IoT Analytics components including Channel, Pipeline, Datastore, and Dataset
2. **Modern Pipeline**: Uses Kinesis Data Streams, Lambda, and Amazon Timestream for real-time processing

## Prerequisites

- AWS CLI v2 installed and configured
- Python 3.7+ installed
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Sufficient AWS permissions for IoT, Kinesis, Lambda, and Timestream services

## Installation

1. **Clone and navigate to the directory**:
   ```bash
   cd cdk-python/
   ```

2. **Create a Python virtual environment**:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Bootstrap CDK (if not already done)**:
   ```bash
   cdk bootstrap
   ```

## Deployment

1. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

2. **Confirm deployment** when prompted.

## Configuration

The application uses a configurable unique suffix for resource naming. You can customize this by modifying the `cdk.json` file:

```json
{
  "context": {
    "unique_suffix": "your-custom-suffix"
  }
}
```

## Usage

### Testing the Legacy IoT Analytics Pipeline

1. **Send data to IoT Analytics**:
   ```bash
   aws iot-data publish \
     --topic "topic/sensor/data" \
     --payload '{"timestamp": "2024-01-01T12:00:00Z", "deviceId": "sensor001", "temperature": 25.5, "humidity": 60.2}'
   ```

2. **Check the IoT Analytics channel**:
   ```bash
   aws iotanalytics describe-channel --channel-name iot-sensor-channel-demo
   ```

### Testing the Modern Kinesis Pipeline

1. **Send data to Kinesis**:
   ```bash
   aws iot-data publish \
     --topic "topic/sensor/data/kinesis" \
     --payload '{"timestamp": "2024-01-01T12:00:00Z", "deviceId": "sensor001", "temperature": 26.3, "humidity": 58.9}'
   ```

2. **Query Timestream data**:
   ```bash
   aws timestream-query query \
     --query-string "SELECT * FROM \"iot-sensor-db-demo\".\"sensor-data\" WHERE time > ago(1h) ORDER BY time DESC LIMIT 10"
   ```

## Monitoring

- **Lambda Function Logs**: Check CloudWatch Logs for the `ProcessIoTData` function
- **Kinesis Metrics**: Monitor shard utilization and throughput in CloudWatch
- **Timestream Metrics**: Track write throughput and storage usage

## Stack Outputs

The stack provides the following outputs:

- `IoTAnalyticsChannelName`: Name of the IoT Analytics Channel
- `IoTAnalyticsDatastoreName`: Name of the IoT Analytics Datastore
- `KinesisStreamName`: Name of the Kinesis Data Stream
- `TimestreamDatabaseName`: Name of the Timestream Database
- `LambdaFunctionName`: Name of the Lambda Function
- `IoTAnalyticsTopicName`: IoT Topic for IoT Analytics pipeline
- `KinesisTopicName`: IoT Topic for Kinesis pipeline

## Cleanup

To remove all resources created by this stack:

```bash
cdk destroy
```

## Cost Considerations

- **IoT Analytics**: Charges for data ingestion, processing, and storage
- **Kinesis Data Streams**: Charges per shard hour and data ingestion
- **Lambda**: Charges for execution time and memory usage
- **Timestream**: Charges for memory and magnetic storage, plus queries
- **IoT Core**: Charges for message publishing and rules execution

## Security Best Practices

This application implements several security best practices:

1. **Least Privilege IAM**: Each service has minimal required permissions
2. **Resource Isolation**: Resources are properly scoped and tagged
3. **Encryption**: Uses default AWS encryption for data at rest and in transit
4. **VPC Endpoints**: Consider adding VPC endpoints for enhanced security in production

## Troubleshooting

### Common Issues

1. **Lambda Function Errors**: Check CloudWatch Logs for detailed error messages
2. **Timestream Write Errors**: Ensure proper IAM permissions for the Lambda function
3. **IoT Rules Not Triggering**: Verify topic names and rule SQL syntax

### Debugging Tips

1. **Enable detailed logging** in the Lambda function
2. **Use CloudWatch Insights** to query Lambda logs
3. **Monitor Kinesis shard iterator age** for processing delays

## Architecture Migration

As AWS IoT Analytics reaches end-of-support on December 15, 2025, this application demonstrates how to migrate to modern alternatives:

1. **Replace IoT Analytics Channel** with Kinesis Data Streams
2. **Replace IoT Analytics Pipeline** with Lambda functions
3. **Replace IoT Analytics Datastore** with Amazon Timestream
4. **Replace IoT Analytics Dataset** with direct Timestream queries

## Further Reading

- [AWS IoT Analytics Documentation](https://docs.aws.amazon.com/iotanalytics/)
- [Amazon Kinesis Data Streams Documentation](https://docs.aws.amazon.com/kinesis/)
- [Amazon Timestream Documentation](https://docs.aws.amazon.com/timestream/)
- [AWS CDK Python Reference](https://docs.aws.amazon.com/cdk/api/v2/python/)

## License

This code is provided under the MIT License. See the LICENSE file for details.