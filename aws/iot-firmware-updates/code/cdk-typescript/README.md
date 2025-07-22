# IoT Firmware Updates with Device Management Jobs - CDK TypeScript

This CDK TypeScript application deploys a complete IoT firmware update system using AWS IoT Device Management Jobs, AWS Signer, S3, and Lambda. The solution enables secure over-the-air (OTA) firmware updates for IoT devices at scale.

## Architecture

The solution deploys the following components:

- **S3 Bucket**: Secure storage for firmware packages with versioning and encryption
- **AWS Signer**: Code signing profile for firmware authenticity verification
- **Lambda Function**: Orchestrates firmware update jobs with comprehensive management capabilities
- **IoT Things & Thing Groups**: Device management and organization for targeted updates
- **IAM Roles**: Least-privilege access for IoT Jobs and Lambda execution
- **CloudWatch Dashboard**: Monitoring and observability for update campaigns
- **SNS Topic**: Notifications for job status changes
- **EventBridge Rules**: Automated event handling for job lifecycle management

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18 or later
- CDK CLI installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for IoT, S3, Lambda, IAM, and CloudWatch

## Installation

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Bootstrap CDK (if not done previously)**:
   ```bash
   npm run bootstrap
   ```

3. **Build the project**:
   ```bash
   npm run build
   ```

## Deployment

### Quick Start

Deploy to development environment:
```bash
npm run deploy:dev
```

Deploy to production environment:
```bash
npm run deploy:prod
```

### Custom Deployment

Deploy with specific context:
```bash
cdk deploy --context environment=staging --context account=123456789012 --context region=us-west-2
```

### Environment-Specific Configuration

The stack supports different environments through CDK context:

- **Development**: `--context environment=dev`
- **Production**: `--context environment=prod`
- **Staging**: `--context environment=staging`

Each environment gets isolated resources with unique naming.

## Usage

### 1. Upload Firmware

Upload your firmware binary to the S3 bucket:

```bash
# Get bucket name from stack outputs
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name IoTFirmwareUpdatesStack-dev \
    --query 'Stacks[0].Outputs[?OutputKey==`FirmwareBucketName`].OutputValue' \
    --output text)

# Upload firmware
aws s3 cp your-firmware.bin s3://${BUCKET_NAME}/firmware/your-firmware-v1.0.0.bin
```

### 2. Sign Firmware

Start a signing job using AWS Signer:

```bash
# Get signing profile name
SIGNING_PROFILE=$(aws cloudformation describe-stacks \
    --stack-name IoTFirmwareUpdatesStack-dev \
    --query 'Stacks[0].Outputs[?OutputKey==`SigningProfileName`].OutputValue' \
    --output text)

# Start signing job
aws signer start-signing-job \
    --source "s3={bucketName=${BUCKET_NAME},key=firmware/your-firmware-v1.0.0.bin}" \
    --destination "s3={bucketName=${BUCKET_NAME},prefix=signed-firmware/}" \
    --profile-name ${SIGNING_PROFILE}
```

### 3. Create Firmware Update Job

Use the Lambda function to create an IoT Job:

```bash
# Get Lambda function name
FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name IoTFirmwareUpdatesStack-dev \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

# Get Thing Group name
THING_GROUP=$(aws cloudformation describe-stacks \
    --stack-name IoTFirmwareUpdatesStack-dev \
    --query 'Stacks[0].Outputs[?OutputKey==`ThingGroupName`].OutputValue' \
    --output text)

# Create firmware update job
aws lambda invoke \
    --function-name ${FUNCTION_NAME} \
    --payload '{
        "action": "create_job",
        "firmware_version": "1.0.0",
        "thing_group": "'${THING_GROUP}'",
        "s3_bucket": "'${BUCKET_NAME}'",
        "s3_key": "signed-firmware/your-firmware-v1.0.0.bin"
    }' \
    response.json

# View response
cat response.json
```

### 4. Monitor Job Progress

Check job status:

```bash
# Extract job ID from response
JOB_ID=$(cat response.json | jq -r '.body' | jq -r '.job_id')

# Check job status
aws lambda invoke \
    --function-name ${FUNCTION_NAME} \
    --payload '{
        "action": "check_job_status",
        "job_id": "'${JOB_ID}'"
    }' \
    status.json

cat status.json
```

### 5. View Dashboard

Access the CloudWatch dashboard for real-time monitoring:

```bash
# Get dashboard URL
aws cloudformation describe-stacks \
    --stack-name IoTFirmwareUpdatesStack-dev \
    --query 'Stacks[0].Outputs[?OutputKey==`DashboardURL`].OutputValue' \
    --output text
```

## Lambda Function API

The firmware update manager Lambda function supports the following actions:

### Create Job
```json
{
  "action": "create_job",
  "firmware_version": "1.0.0",
  "thing_group": "firmware-update-group-abc123",
  "s3_bucket": "firmware-updates-abc123",
  "s3_key": "signed-firmware/firmware-v1.0.0.bin"
}
```

### Check Job Status
```json
{
  "action": "check_job_status",
  "job_id": "firmware-update-1.0.0-def456"
}
```

### Cancel Job
```json
{
  "action": "cancel_job",
  "job_id": "firmware-update-1.0.0-def456"
}
```

### List Jobs
```json
{
  "action": "list_jobs"
}
```

## Device Integration

Devices should implement the following workflow:

1. **Subscribe to Job Topics**:
   - `$aws/things/{thingName}/jobs/notify-next`
   - `$aws/things/{thingName}/jobs/{jobId}/get/accepted`

2. **Process Job Documents**:
   ```python
   def process_job(job_document):
       firmware = job_document['firmware']
       
       # Download firmware from S3 URL
       download_firmware(firmware['url'])
       
       # Verify signature using AWS Signer
       verify_signature(firmware_file)
       
       # Install firmware
       install_firmware(firmware_file)
       
       # Report success
       update_job_status('SUCCEEDED')
   ```

3. **Report Job Status**:
   - `$aws/things/{thingName}/jobs/{jobId}/update`

## Security Features

- **Firmware Signing**: All firmware is cryptographically signed using AWS Signer
- **Secure Transport**: All communication uses TLS encryption
- **IAM Least Privilege**: Roles have minimal required permissions
- **S3 Security**: Bucket blocks public access and enforces SSL
- **VPC Isolation**: Optional VPC deployment for enhanced network security

## Monitoring and Observability

### CloudWatch Metrics
- IoT Jobs completion rates
- Lambda function performance
- S3 access patterns
- Error rates and failures

### CloudWatch Logs
- Lambda function execution logs
- IoT device communication logs
- Job execution details

### SNS Notifications
- Job completion notifications
- Failure alerts
- Status change updates

## Cost Optimization

- **S3 Intelligent Tiering**: Automatically moves old firmware to cheaper storage classes
- **Lambda Reserved Concurrency**: Prevents unexpected charges from traffic spikes
- **CloudWatch Log Retention**: Configurable retention periods to manage costs
- **Job Rollout Controls**: Gradual deployment reduces resource consumption

## Troubleshooting

### Common Issues

1. **Job Creation Fails**:
   - Verify IAM permissions for Lambda function
   - Check S3 bucket access permissions
   - Ensure Thing Group exists

2. **Devices Don't Receive Jobs**:
   - Verify device certificates and policies
   - Check MQTT connection status
   - Validate Thing Group membership

3. **Signing Fails**:
   - Verify signing profile exists
   - Check S3 object permissions
   - Ensure firmware file is accessible

### Debug Commands

```bash
# Check Lambda logs
aws logs describe-log-streams \
    --log-group-name /aws/lambda/firmware-update-manager-abc123

# List IoT Jobs
aws iot list-jobs --status IN_PROGRESS

# Check Thing Group membership
aws iot list-things-in-thing-group \
    --thing-group-name firmware-update-group-abc123
```

## Development

### Local Development

```bash
# Install dependencies
npm install

# Run tests
npm test

# Lint code
npm run lint

# Format code
npm run format

# Watch for changes
npm run watch
```

### Testing

The solution includes comprehensive tests:

```bash
# Unit tests
npm test

# Integration tests (requires AWS credentials)
npm run test:integration

# Load tests
npm run test:load
```

## Cleanup

Remove all resources:

```bash
# Development environment
npm run destroy:dev

# Production environment
npm run destroy:prod

# Manual cleanup if needed
cdk destroy --all --force
```

## Advanced Configuration

### Custom Rollout Strategies

Modify the Lambda function to implement custom rollout logic:

```typescript
jobExecutionsRolloutConfig: {
  maximumPerMinute: 50,
  exponentialRate: {
    baseRatePerMinute: 10,
    incrementFactor: 1.5,
    rateIncreaseCriteria: {
      numberOfNotifiedThings: 100,
      numberOfSucceededThings: 95
    }
  }
}
```

### Custom Abort Conditions

Configure automatic job cancellation:

```typescript
abortConfig: {
  criteriaList: [
    {
      failureType: 'FAILED',
      action: 'CANCEL',
      thresholdPercentage: 10.0,
      minNumberOfExecutedThings: 10
    }
  ]
}
```

### Multi-Region Deployment

Deploy to multiple regions for global device management:

```bash
cdk deploy --context region=us-east-1
cdk deploy --context region=eu-west-1
cdk deploy --context region=ap-southeast-1
```

## Support

For issues and questions:

1. Check the [AWS IoT Developer Guide](https://docs.aws.amazon.com/iot/latest/developerguide/)
2. Review [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
3. Submit issues to the [recipe repository](https://github.com/aws-samples/recipes/issues)

## License

This project is licensed under the MIT License - see the LICENSE file for details.