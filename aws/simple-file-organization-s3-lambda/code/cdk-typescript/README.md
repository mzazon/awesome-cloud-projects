# Simple File Organization CDK Application

This AWS CDK TypeScript application creates an automated file organization system using Amazon S3 and AWS Lambda. Files uploaded to the S3 bucket are automatically organized into folders based on their file extensions.

## Architecture

- **S3 Bucket**: Secure storage with versioning, encryption, and lifecycle policies
- **Lambda Function**: Python 3.12 function that organizes files by type
- **IAM Roles**: Least privilege access for Lambda to interact with S3
- **CloudWatch Logs**: Centralized logging with retention policies
- **S3 Event Notifications**: Trigger Lambda function on file uploads

## File Organization Logic

Files are automatically organized into folders based on their extensions:

- **images/**: jpg, jpeg, png, gif, bmp, tiff, svg, webp, ico, raw, heic, heif
- **documents/**: pdf, doc, docx, txt, rtf, odt, xls, xlsx, ppt, pptx, csv, md, etc.
- **videos/**: mp4, avi, mov, wmv, flv, webm, mkv, m4v, mpg, mpeg, 3gp
- **other/**: All other file types

## Prerequisites

- Node.js 18+ and npm
- AWS CLI configured with appropriate permissions
- AWS CDK CLI installed: `npm install -g aws-cdk`

## Quick Start

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Bootstrap CDK** (first time only):
   ```bash
   cdk bootstrap
   ```

3. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

4. **Test file organization**:
   ```bash
   # Upload test files to the bucket
   aws s3 cp test-image.jpg s3://your-bucket-name/
   aws s3 cp test-document.pdf s3://your-bucket-name/
   
   # Verify files were organized
   aws s3 ls s3://your-bucket-name/ --recursive
   ```

## Configuration Options

You can customize the deployment using CDK context values:

```bash
# Custom bucket name
cdk deploy -c bucketName=my-custom-bucket

# Disable versioning
cdk deploy -c enableVersioning=false

# Adjust Lambda settings
cdk deploy -c lambdaTimeout=120 -c lambdaMemorySize=512

# Enable CDK Nag security checks
cdk deploy -c enableCdkNag=true
```

## Available Commands

- `npm run build`: Compile TypeScript to JavaScript
- `npm run watch`: Watch for changes and compile
- `npm run test`: Run the Jest unit tests
- `npm run lint`: Run ESLint
- `npm run format`: Format code with Prettier
- `cdk synth`: Synthesize CloudFormation template
- `cdk deploy`: Deploy the stack
- `cdk diff`: Compare deployed stack with current state
- `cdk destroy`: Remove all resources

## Security Features

- **Encryption**: Server-side encryption enabled by default
- **Access Control**: Public access blocked, SSL enforced
- **IAM**: Least privilege roles and policies
- **Logging**: Comprehensive CloudWatch logging
- **CDK Nag**: Optional security best practices validation

## Cost Optimization

- **Lifecycle Policies**: Automatic cleanup of incomplete multipart uploads
- **Reserved Concurrency**: Prevents Lambda from overwhelming downstream services
- **Log Retention**: CloudWatch logs retained for 1 week (configurable)
- **Serverless**: Pay only for actual usage

## Monitoring and Troubleshooting

### View Lambda Logs
```bash
aws logs tail /aws/lambda/file-organizer-function --follow
```

### Check S3 Event Notifications
```bash
aws s3api get-bucket-notification-configuration --bucket your-bucket-name
```

### Monitor Lambda Metrics
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=file-organizer-function \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-02T00:00:00Z \
  --period 3600 \
  --statistics Sum
```

## Cleanup

To remove all resources:

```bash
cdk destroy
```

This will delete the S3 bucket and all its contents, Lambda function, and associated resources.

## Development

### Project Structure
```
├── app.ts                    # CDK app entry point
├── lib/
│   └── file-organizer-stack.ts # Main stack definition
├── package.json              # Dependencies and scripts
├── tsconfig.json            # TypeScript configuration
├── cdk.json                 # CDK configuration
└── README.md               # This file
```

### Adding New File Types

To add support for new file types, modify the `get_folder_for_extension` function in the Lambda code within `file-organizer-stack.ts`.

### Testing

Run unit tests:
```bash
npm test
```

### Code Quality

This project includes ESLint and Prettier for code quality:
```bash
npm run lint        # Check code style
npm run lint:fix    # Fix code style issues
npm run format      # Format code
```

## Security Considerations

- The Lambda function has minimal permissions (read/write/delete only on the specific S3 bucket)
- S3 bucket blocks all public access by default
- Server-side encryption is enabled
- SSL/TLS is enforced for all connections
- CloudWatch logs are retained for a limited time

## Production Recommendations

For production deployments, consider:

1. **Enable CDK Nag**: Use `-c enableCdkNag=true` to validate security best practices
2. **Custom KMS Keys**: Replace S3_MANAGED encryption with customer-managed KMS keys
3. **VPC Deployment**: Deploy Lambda in VPC for additional network isolation
4. **Monitoring**: Set up CloudWatch alarms for function errors and duration
5. **Backup**: Enable S3 Cross-Region Replication for disaster recovery
6. **Access Logging**: Enable S3 server access logging for audit trails

## Support

For issues or questions:
1. Check CloudWatch logs for error details
2. Verify IAM permissions are correctly applied  
3. Ensure S3 event notifications are configured
4. Review the original recipe documentation

## License

This project is licensed under the MIT License.