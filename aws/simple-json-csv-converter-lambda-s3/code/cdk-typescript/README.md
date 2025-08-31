# JSON to CSV Converter - CDK TypeScript Implementation

This directory contains a complete AWS CDK TypeScript application that deploys a serverless JSON to CSV converter using AWS Lambda and S3.

## Architecture

The CDK application creates the following resources:

- **Input S3 Bucket**: Receives JSON files with versioning and encryption enabled
- **Output S3 Bucket**: Stores converted CSV files with versioning and encryption enabled
- **Lambda Function**: Processes JSON files and converts them to CSV format (Python 3.12 runtime)
- **IAM Role**: Provides least privilege access for Lambda to read from input bucket and write to output bucket
- **S3 Event Notification**: Automatically triggers Lambda function when JSON files are uploaded

## Prerequisites

Before deploying this CDK application, ensure you have:

1. **AWS CLI** installed and configured with appropriate credentials
2. **Node.js** (version 18 or later) and npm installed
3. **AWS CDK** CLI installed globally: `npm install -g aws-cdk`
4. **TypeScript** installed globally: `npm install -g typescript`
5. **AWS account** with permissions to create IAM roles, Lambda functions, and S3 buckets

## Installation and Deployment

### 1. Install Dependencies

```bash
cd aws/simple-json-csv-converter-lambda-s3/code/cdk-typescript/
npm install
```

### 2. Bootstrap CDK (if not done previously)

```bash
cdk bootstrap
```

### 3. Build the TypeScript Code

```bash
npm run build
```

### 4. Review the CloudFormation Template

```bash
cdk synth
```

### 5. Deploy the Stack

```bash
cdk deploy
```

During deployment, CDK will show you the resources that will be created and ask for confirmation. Type `y` to proceed.

### 6. Note the Output Values

After successful deployment, CDK will display output values including:
- Input bucket name
- Output bucket name  
- Lambda function name and ARN

## Testing the Deployment

### 1. Create a Test JSON File

```bash
cat > sample-data.json << EOF
[
  {
    "id": 1,
    "name": "John Doe",
    "email": "john@example.com",
    "department": "Engineering"
  },
  {
    "id": 2,
    "name": "Jane Smith",
    "email": "jane@example.com",
    "department": "Marketing"
  }
]
EOF
```

### 2. Upload to Input Bucket

```bash
# Replace with your actual input bucket name from CDK output
aws s3 cp sample-data.json s3://json-input-XXXXXXXX/
```

### 3. Verify Conversion

Wait a few seconds, then check the output bucket:

```bash
# Replace with your actual output bucket name from CDK output
aws s3 ls s3://csv-output-XXXXXXXX/

# Download and view the converted CSV file
aws s3 cp s3://csv-output-XXXXXXXX/sample-data.csv ./
cat sample-data.csv
```

### 4. Monitor Lambda Function

Check CloudWatch logs for the Lambda function:

```bash
# Replace with your actual function name from CDK output
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/json-csv-converter"
```

## Customization

### Environment Variables

The Lambda function uses the following environment variable:
- `OUTPUT_BUCKET`: Set automatically by CDK to the output bucket name

### Lambda Function Code

The Lambda function code is embedded in the CDK application. To modify the conversion logic:

1. Edit the `code: lambda.Code.fromInline()` section in `app.ts`
2. Rebuild and redeploy: `npm run build && cdk deploy`

### Resource Configuration

Key configuration options in `app.ts`:

```typescript
// Lambda function settings
timeout: cdk.Duration.seconds(60),     // Adjust timeout as needed
memorySize: 256,                       // Adjust memory allocation
runtime: lambda.Runtime.PYTHON_3_12,  // Python runtime version

// S3 bucket settings
versioned: true,                       // Enable versioning
encryption: s3.BucketEncryption.S3_MANAGED,  // Server-side encryption
```

## Cost Optimization

This solution is designed for cost efficiency:

- **Lambda**: Pay only for execution time and requests
- **S3**: Standard storage class with lifecycle rules for incomplete uploads
- **CloudWatch**: Basic logging included in Lambda pricing

Estimated costs for testing: $0.01-$0.10 per month

## Security Features

The CDK implementation includes several security best practices:

- **Least Privilege IAM**: Lambda role has minimal required permissions
- **S3 Encryption**: Both buckets use server-side encryption
- **Public Access Blocked**: S3 buckets block all public access
- **VPC Integration**: Can be extended to run Lambda in VPC if needed

## Monitoring and Debugging

### CloudWatch Logs

Lambda function logs are automatically sent to CloudWatch:

```bash
# View recent log events
aws logs tail /aws/lambda/json-csv-converter-XXXXXXXX --follow
```

### CloudWatch Metrics

Monitor Lambda performance metrics:
- Duration
- Error rate
- Invocation count
- Concurrent executions

### X-Ray Tracing

To enable X-Ray tracing, add to the Lambda function configuration:

```typescript
tracing: lambda.Tracing.ACTIVE,
```

## Cleanup

To remove all resources and avoid ongoing charges:

```bash
cdk destroy
```

This will delete all resources including S3 buckets and their contents.

## Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure your AWS credentials have sufficient permissions
2. **Bucket Name Conflicts**: The CDK uses unique suffixes, but if conflicts occur, modify the bucket names in `app.ts`
3. **Lambda Timeout**: Increase timeout value if processing large JSON files
4. **Memory Errors**: Increase Lambda memory allocation for large files

### Debug Steps

1. Check CloudWatch logs for detailed error messages
2. Verify S3 event notifications are configured correctly
3. Test Lambda function directly with sample S3 events
4. Ensure IAM permissions are correctly configured

### Support

For additional help:
- Review the original recipe documentation
- Check AWS CDK documentation: https://docs.aws.amazon.com/cdk/
- AWS Lambda documentation: https://docs.aws.amazon.com/lambda/

## Advanced Features

### Extensions

Consider these enhancements for production use:

1. **Dead Letter Queue**: Handle failed processing attempts
2. **Input Validation**: Validate JSON structure before processing  
3. **Batch Processing**: Combine multiple small files
4. **Multiple Formats**: Support XML, YAML input formats
5. **Data Transformation**: Add custom data transformation rules

### Integration

This CDK stack can be integrated with:
- **Step Functions**: For complex workflow orchestration
- **EventBridge**: For event-driven architecture patterns
- **API Gateway**: For REST API access to trigger conversions
- **SQS**: For queued processing and retry logic

## Version Information

- **CDK Version**: 2.100.0
- **TypeScript**: ~5.2.2
- **Node.js**: 20.6.2 or later
- **AWS Lambda Runtime**: Python 3.12