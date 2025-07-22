# Infrastructure as Code for IoT Telemetry Analytics with Kinesis and Timestream

This directory contains Infrastructure as Code (IaC) implementations for the recipe "IoT Telemetry Analytics with Kinesis and Timestream".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - IoT Analytics (create/delete channels, pipelines, datastores, datasets)
  - IoT Core (create/delete rules)
  - Kinesis (create/delete streams)
  - Timestream (create/delete databases and tables)
  - Lambda (create/delete functions)
  - IAM (create/delete roles and policies)
- Basic understanding of IoT concepts and time-series data
- Estimated cost: $20-40 for resources created during deployment

> **Warning**: AWS IoT Analytics will reach end-of-support on December 15, 2025. This implementation includes both legacy IoT Analytics components and modern alternatives using Kinesis Data Streams and Amazon Timestream.

## Quick Start

### Using CloudFormation
```bash
aws cloudformation create-stack \
    --stack-name iot-analytics-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=RandomSuffix,ParameterValue=$(aws secretsmanager get-random-password --exclude-punctuation --exclude-uppercase --password-length 6 --require-each-included-type --output text --query RandomPassword)
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install
npx cdk bootstrap  # Only needed once per AWS account/region
npx cdk deploy
```

### Using CDK Python
```bash
cd cdk-python/
pip install -r requirements.txt
npx cdk bootstrap  # Only needed once per AWS account/region
npx cdk deploy
```

### Using Terraform
```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

### Using Bash Scripts
```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Architecture

The solution implements both legacy IoT Analytics components and modern alternatives:

### Legacy Components (End-of-Support Dec 2025)
- **IoT Analytics Channel**: Collects raw IoT data
- **IoT Analytics Pipeline**: Processes and transforms data
- **IoT Analytics Datastore**: Stores processed data
- **IoT Analytics Dataset**: Provides SQL interface for queries

### Modern Alternative Components
- **Kinesis Data Streams**: Real-time data ingestion
- **Lambda Function**: Custom data processing logic
- **Amazon Timestream**: Purpose-built time-series database

### Supporting Services
- **IoT Core**: Device connectivity and message routing
- **IoT Rules Engine**: Routes data to appropriate services
- **IAM Roles**: Secure service-to-service communication

## Validation & Testing

After deployment, you can validate the solution:

1. **Check IoT Analytics Resources**:
   ```bash
   aws iotanalytics describe-channel --channel-name <channel-name>
   aws iotanalytics describe-pipeline --pipeline-name <pipeline-name>
   aws iotanalytics describe-datastore --datastore-name <datastore-name>
   ```

2. **Test Data Processing**:
   ```bash
   # Send test data to IoT Analytics
   aws iotanalytics batch-put-message \
       --channel-name <channel-name> \
       --messages '[{"messageId": "test001", "payload": "'$(echo -n '{"deviceId": "sensor001", "temperature": 25.5}' | base64)'"}]'
   
   # Send test data to Kinesis
   aws kinesis put-record \
       --stream-name <stream-name> \
       --partition-key sensor001 \
       --data '{"deviceId": "sensor001", "temperature": 26.3}'
   ```

3. **Query Results**:
   ```bash
   # Query IoT Analytics dataset
   aws iotanalytics get-dataset-content \
       --dataset-name <dataset-name> \
       --version-id '$LATEST'
   
   # Query Timestream data
   aws timestream-query query \
       --query-string "SELECT * FROM \"<database>\".\"<table>\" WHERE time > ago(1h)"
   ```

## Cleanup

### Using CloudFormation
```bash
aws cloudformation delete-stack --stack-name iot-analytics-stack
```

### Using CDK
```bash
# From the cdk-typescript/ or cdk-python/ directory
npx cdk destroy
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

## Customization

### Key Variables/Parameters

- **RandomSuffix**: Unique identifier for resource names
- **AWS Region**: Target deployment region
- **Retention Periods**: Data retention for channels and datastores
- **Shard Count**: Number of shards for Kinesis stream
- **Lambda Runtime**: Python runtime version for processing function
- **Memory/Magnetic Store Retention**: Timestream data retention settings

### Example Customizations

1. **Multi-Region Deployment**: Deploy to multiple regions for high availability
2. **Enhanced Processing**: Add more sophisticated data transformation logic
3. **Security Hardening**: Implement VPC endpoints and enhanced IAM policies
4. **Monitoring**: Add CloudWatch alarms and dashboards
5. **Cost Optimization**: Implement lifecycle policies and right-sizing

## Migration from IoT Analytics

Since AWS IoT Analytics reaches end-of-support on December 15, 2025, consider migrating to the modern alternative components:

1. **Data Ingestion**: Replace IoT Analytics channels with Kinesis Data Streams
2. **Processing**: Replace pipelines with Lambda functions or Kinesis Data Analytics
3. **Storage**: Replace datastores with Amazon Timestream for time-series data
4. **Analytics**: Use Amazon Athena, QuickSight, or SageMaker for analysis

## Security Considerations

- All IAM roles follow least privilege principle
- Service-to-service communication uses IAM roles (no hard-coded credentials)
- Timestream data is encrypted at rest and in transit
- Lambda function has minimal required permissions
- IoT rules include proper topic filtering

## Performance Optimization

- Kinesis shard count can be adjusted based on data volume
- Lambda function memory and timeout can be optimized
- Timestream memory/magnetic store retention can be tuned for cost/performance
- Consider using Kinesis Data Firehose for high-throughput, low-latency scenarios

## Monitoring and Troubleshooting

- CloudWatch metrics available for all services
- Lambda function logs in CloudWatch Logs
- Kinesis stream metrics for throughput monitoring
- Timestream query performance metrics
- IoT Analytics pipeline execution logs

## Support

For issues with this infrastructure code, refer to:
- [Original recipe documentation](../iot-analytics-pipelines-aws-iot-analytics.md)
- [AWS IoT Analytics documentation](https://docs.aws.amazon.com/iotanalytics/)
- [Amazon Kinesis documentation](https://docs.aws.amazon.com/kinesis/)
- [Amazon Timestream documentation](https://docs.aws.amazon.com/timestream/)
- [AWS IoT Core documentation](https://docs.aws.amazon.com/iot/)

## Cost Estimation

Estimated monthly costs (us-east-1, moderate usage):
- IoT Analytics: $30-50/month (legacy, end-of-support)
- Kinesis Data Streams: $15-25/month
- Lambda: $5-15/month
- Timestream: $20-40/month
- IoT Core: $5-10/month

Total estimated cost: $75-140/month for the complete solution.

> **Note**: Costs vary based on data volume, query frequency, and retention periods. Use AWS Cost Calculator for precise estimates.