# Simple File Organization CDK Python Application

This AWS CDK Python application implements an automated file organization system using Amazon S3 and AWS Lambda. Files uploaded to the S3 bucket are automatically organized into folders based on their file type.

## Architecture

The application creates:

- **S3 Bucket**: Secure storage with encryption, versioning, and lifecycle policies
- **Lambda Function**: Processes S3 events and organizes files by type
- **IAM Role**: Least privilege permissions for Lambda execution
- **CloudWatch Logs**: Monitoring and debugging capabilities

Files are automatically organized into these folders:
- `images/` - Image files (jpg, png, gif, etc.)
- `documents/` - Document files (pdf, doc, txt, etc.)
- `videos/` - Video files (mp4, avi, mov, etc.)
- `audio/` - Audio files (mp3, wav, flac, etc.)
- `archives/` - Archive files (zip, rar, 7z, etc.)
- `code/` - Code files (py, js, html, etc.)
- `other/` - All other file types

## Prerequisites

- AWS CLI installed and configured
- Python 3.8 or higher
- Node.js 14.x or higher (for CDK CLI)
- AWS CDK CLI installed (`npm install -g aws-cdk`)

## Setup and Deployment

1. **Clone and Navigate to Directory**:
   ```bash
   cd aws/simple-file-organization-s3-lambda/code/cdk-python/
   ```

2. **Create Virtual Environment**:
   ```bash
   python -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install Dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Bootstrap CDK (first time only)**:
   ```bash
   cdk bootstrap
   ```

5. **Synthesize CloudFormation Template**:
   ```bash
   cdk synth
   ```

6. **Deploy the Stack**:
   ```bash
   cdk deploy
   ```

   The deployment will output:
   - S3 bucket name and ARN
   - Lambda function name and ARN

## Usage

1. **Upload Files to S3 Bucket**:
   ```bash
   # Get bucket name from stack outputs
   BUCKET_NAME=$(aws cloudformation describe-stacks \
     --stack-name SimpleFileOrganizationStack \
     --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
     --output text)
   
   # Upload test files
   aws s3 cp test-image.jpg s3://${BUCKET_NAME}/
   aws s3 cp test-document.pdf s3://${BUCKET_NAME}/
   aws s3 cp test-video.mp4 s3://${BUCKET_NAME}/
   ```

2. **Verify File Organization**:
   ```bash
   # List organized files
   aws s3 ls s3://${BUCKET_NAME}/ --recursive
   ```

3. **Monitor Lambda Execution**:
   ```bash
   # View Lambda logs
   aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/SimpleFileOrganizationStack"
   ```

## Development

### Running Security Checks

The application includes CDK Nag for security best practices:

```bash
# CDK Nag runs automatically during synthesis
cdk synth
```

### Running Tests

```bash
# Install development dependencies
pip install -e ".[dev]"

# Run tests
pytest tests/

# Run with coverage
pytest --cov=app tests/
```

### Code Formatting

```bash
# Format code with Black
black app.py

# Check code style with flake8
flake8 app.py

# Type checking with mypy
mypy app.py
```

## Configuration

### Environment Variables

The application supports these environment variables:

- `CDK_DEFAULT_ACCOUNT`: AWS account ID
- `CDK_DEFAULT_REGION`: AWS region (default: us-east-1)
- `LOG_LEVEL`: Lambda logging level (default: INFO)

### Lambda Function Environment

The Lambda function includes these environment variables:

- `POWERTOOLS_SERVICE_NAME`: Service name for AWS Lambda Powertools
- `POWERTOOLS_METRICS_NAMESPACE`: CloudWatch metrics namespace
- `LOG_LEVEL`: Logging level

### Customization

To modify file type mappings, edit the `_get_target_folder()` function in the Lambda code within `app.py`.

## Cost Optimization

The application includes several cost optimization features:

1. **S3 Lifecycle Rules**: Automatically transitions files to cheaper storage classes
   - 30 days: Standard to Infrequent Access
   - 90 days: Infrequent Access to Glacier

2. **Lambda Optimization**: 
   - Right-sized memory (256 MB)
   - Timeout set to 60 seconds
   - Efficient file processing logic

3. **Monitoring**: Lambda Insights and X-Ray tracing for performance optimization

## Security Features

- **Encryption**: S3 server-side encryption enabled
- **Access Control**: Least privilege IAM permissions
- **Network Security**: S3 bucket blocks all public access
- **Monitoring**: CloudWatch logging and AWS X-Ray tracing
- **Compliance**: CDK Nag security checks enforced

## Troubleshooting

### Common Issues

1. **Lambda Timeout**: Increase timeout in `app.py` if processing large files
2. **Permission Denied**: Verify IAM permissions and S3 bucket policies
3. **File Not Moving**: Check CloudWatch logs for error messages

### Debugging

1. **View Lambda Logs**:
   ```bash
   aws logs tail /aws/lambda/SimpleFileOrganizationStack-FileOrganizerConstructLambdaFunction --follow
   ```

2. **Check S3 Event Notifications**:
   ```bash
   aws s3api get-bucket-notification-configuration --bucket ${BUCKET_NAME}
   ```

3. **Test Lambda Function**:
   ```bash
   aws lambda invoke \
     --function-name ${FUNCTION_NAME} \
     --payload file://test-event.json \
     response.json
   ```

## Cleanup

To remove all resources and avoid ongoing costs:

```bash
# Delete the CDK stack
cdk destroy

# Confirm deletion when prompted
```

**Note**: This will delete the S3 bucket and all files. Make sure to backup any important files first.

## Additional Resources

- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [AWS Solutions Constructs](https://docs.aws.amazon.com/solutions/latest/constructs/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [Amazon S3 User Guide](https://docs.aws.amazon.com/AmazonS3/latest/userguide/)
- [CDK Nag Rules](https://github.com/cdklabs/cdk-nag/blob/main/RULES.md)

## License

This project is licensed under the Apache License 2.0. See the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please read the contributing guidelines and submit pull requests for any improvements.

## Support

For issues and questions:
1. Check the troubleshooting section above
2. Review AWS documentation links
3. Submit an issue in the project repository
4. Contact the AWS CDK community for general CDK questions