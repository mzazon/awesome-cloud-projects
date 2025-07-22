# Infrastructure as Code for IoT Dashboard Visualization with QuickSight

This directory contains Infrastructure as Code (IaC) implementations for the recipe "IoT Dashboard Visualization with QuickSight".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - IoT Core (things, policies, rules)
  - Kinesis Data Streams and Firehose
  - S3 (bucket creation and management)
  - AWS Glue (databases and tables)
  - Amazon QuickSight (account and data sources)
  - IAM (roles and policies)
  - Athena (query execution)
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.5+ (for Terraform implementation)
- Estimated cost: $15-25 for running this solution

> **Note**: QuickSight requires an active subscription. The first 30 days are free for new users, after which standard pricing applies.

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the complete IoT visualization infrastructure
aws cloudformation create-stack \
    --stack-name iot-quicksight-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=QuickSightUserEmail,ParameterValue=your-email@example.com
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# View stack outputs
cdk outputs
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# View stack outputs
cdk outputs
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will prompt for required parameters
# Follow the on-screen instructions for completion
```

## Post-Deployment Steps

After successful deployment, complete these steps to activate the solution:

1. **Generate Test Data**:
   ```bash
   # Publish sample IoT sensor data
   aws iot-data publish \
       --topic "topic/sensor/data" \
       --payload '{
           "device_id": "sensor-001",
           "temperature": 25,
           "humidity": 60,
           "pressure": 1013,
           "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'"
       }'
   ```

2. **Access QuickSight**:
   - Log into the AWS Console
   - Navigate to QuickSight
   - Create a new analysis using the configured data source
   - Build visualizations using the IoT sensor data

3. **Verify Data Flow**:
   ```bash
   # Check S3 for stored IoT data
   aws s3 ls s3://your-bucket-name/iot-data/ --recursive
   
   # Query data through Athena
   aws athena start-query-execution \
       --query-string "SELECT * FROM iot_analytics_db.iot_sensor_data LIMIT 10" \
       --result-configuration OutputLocation=s3://your-bucket-name/athena-results/
   ```

## Configuration Options

### CloudFormation Parameters

- `QuickSightUserEmail`: Email address for QuickSight user notifications
- `EnvironmentName`: Environment prefix for resource naming (default: dev)
- `KinesisShardCount`: Number of Kinesis shards (default: 1)
- `S3BucketName`: Custom S3 bucket name (optional)

### CDK Configuration

Edit the `cdk.json` file to customize deployment:

```json
{
  "app": "npx ts-node app.ts",
  "context": {
    "quicksight-user-email": "your-email@example.com",
    "environment-name": "dev",
    "kinesis-shard-count": 1
  }
}
```

### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
quicksight_user_email = "your-email@example.com"
environment_name      = "dev"
kinesis_shard_count   = 1
aws_region           = "us-east-1"
```

## Architecture Overview

The deployed infrastructure includes:

- **IoT Core**: Device connectivity and message routing
- **Kinesis Data Streams**: Real-time data streaming
- **Kinesis Data Firehose**: Data delivery to S3
- **S3 Bucket**: Data lake storage with time-based partitioning
- **AWS Glue**: Data catalog and schema management
- **Amazon QuickSight**: Business intelligence and visualization
- **IAM Roles**: Secure service-to-service communication

## Monitoring and Troubleshooting

### Key Metrics to Monitor

1. **IoT Core Metrics**:
   - Message publish rate
   - Rules engine execution success/failure
   - Connection counts

2. **Kinesis Metrics**:
   - Incoming records per second
   - Iterator age (data freshness)
   - Throttled records

3. **S3 Metrics**:
   - Object count growth
   - Storage utilization
   - Request rates

### Common Issues

1. **No Data in QuickSight**:
   - Verify IoT devices are publishing to the correct topic
   - Check Kinesis stream is receiving data
   - Ensure Firehose is delivering to S3
   - Confirm Glue table schema matches data structure

2. **QuickSight Connection Errors**:
   - Verify QuickSight has permissions to access Athena
   - Check if S3 bucket policy allows QuickSight access
   - Ensure Glue Data Catalog is properly configured

3. **High Costs**:
   - Monitor Kinesis shard usage and scale down if needed
   - Implement S3 lifecycle policies for data archival
   - Review QuickSight user license requirements

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name iot-quicksight-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name iot-quicksight-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK (AWS)

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the infrastructure
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Security Considerations

This infrastructure implements several security best practices:

- **Least Privilege IAM**: Each service has minimal required permissions
- **Encryption**: Data encrypted in transit and at rest
- **Network Security**: VPC endpoints for secure service communication
- **Access Control**: QuickSight row-level security for data access
- **Audit Logging**: CloudTrail integration for API call monitoring

## Cost Optimization

To minimize costs:

1. **Use appropriate Kinesis shard counts**: Start with 1 shard and scale based on throughput
2. **Implement S3 lifecycle policies**: Archive old data to cheaper storage classes
3. **Monitor QuickSight usage**: Use Author vs Reader licenses appropriately
4. **Set up billing alerts**: Monitor spending on streaming and storage services

## Customization

### Adding New Sensor Types

To support additional IoT sensors:

1. Update the Glue table schema to include new fields
2. Modify the IoT Rules Engine SQL query to handle new data formats
3. Update QuickSight datasets to include new sensor metrics
4. Create additional visualizations for new sensor types

### Scaling for Production

For production deployments:

1. **Increase Kinesis shards**: Scale based on expected message volume
2. **Implement data retention policies**: Archive or delete old data automatically
3. **Add monitoring and alerting**: Set up CloudWatch alarms for key metrics
4. **Enable VPC endpoints**: Reduce data transfer costs and improve security
5. **Implement backup strategies**: Regular backups of Glue catalog and QuickSight assets

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation for solution context
2. Review AWS service documentation for specific configuration details
3. Consult the troubleshooting section above for common issues
4. Verify all prerequisites are met before deployment

## Additional Resources

- [AWS IoT Core Documentation](https://docs.aws.amazon.com/iot/)
- [Amazon Kinesis Documentation](https://docs.aws.amazon.com/kinesis/)
- [Amazon QuickSight Documentation](https://docs.aws.amazon.com/quicksight/)
- [AWS Glue Documentation](https://docs.aws.amazon.com/glue/)
- [IoT Analytics Best Practices](https://docs.aws.amazon.com/iot-analytics/latest/userguide/best-practices.html)