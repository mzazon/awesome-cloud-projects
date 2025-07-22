# Intelligent Document Processing with Amazon Textract - CDK TypeScript

This CDK TypeScript application implements an intelligent document processing pipeline using Amazon Textract. The solution automatically extracts text, handwriting, and structured data from documents uploaded to S3.

## Architecture

This application creates:

- **S3 Bucket**: Secure document storage with versioning and lifecycle policies
- **Lambda Function**: Serverless processing function with Textract integration
- **IAM Roles**: Least-privilege security configuration
- **Event Notifications**: Automated processing triggers
- **CloudWatch Logs**: Comprehensive monitoring and logging

## Prerequisites

1. AWS CLI v2 installed and configured
2. Node.js 18.x or later
3. AWS CDK v2 CLI installed (`npm install -g aws-cdk`)
4. Appropriate AWS permissions for creating S3, Lambda, IAM, and CloudWatch resources

## Quick Start

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Build the application**:
   ```bash
   npm run build
   ```

3. **Bootstrap CDK (first time only)**:
   ```bash
   npm run bootstrap
   ```

4. **Deploy the stack**:
   ```bash
   npm run deploy
   ```

5. **Test the solution**:
   ```bash
   # Upload a document to the documents/ prefix
   aws s3 cp test-document.pdf s3://<bucket-name>/documents/
   
   # Check processing results
   aws s3 ls s3://<bucket-name>/results/
   ```

## Configuration

The stack accepts several configuration parameters that can be customized in the `app.ts` file:

- `resourcePrefix`: Naming prefix for all resources (default: 'textract-processing')
- `enableVersioning`: Enable S3 bucket versioning (default: true)
- `lambdaTimeout`: Lambda function timeout in seconds (default: 60)
- `lambdaMemorySize`: Lambda memory allocation in MB (default: 256)
- `logRetention`: CloudWatch log retention period (default: 1 week)

## Usage

### Document Upload

Upload documents to the `documents/` prefix in the created S3 bucket:

```bash
aws s3 cp document.pdf s3://<bucket-name>/documents/
```

Supported formats: PDF, PNG, JPG, JPEG, TIFF, TIF

### Processing Results

Results are automatically saved to the `results/` prefix as JSON files containing:

- Extracted text content
- Confidence scores and statistics
- Document metadata
- Processing status

### Monitoring

Monitor processing through:

- CloudWatch Logs: `/aws/lambda/<function-name>`
- Lambda metrics in CloudWatch
- S3 bucket metrics and events

## Development

### Available Scripts

- `npm run build`: Compile TypeScript to JavaScript
- `npm run watch`: Watch for changes and auto-compile
- `npm run test`: Run unit tests
- `npm run synth`: Synthesize CloudFormation template
- `npm run diff`: Compare deployed stack with current state
- `npm run deploy`: Deploy the stack
- `npm run destroy`: Delete the stack

### Testing

Run unit tests:
```bash
npm test
```

Synthesize CloudFormation template for review:
```bash
npm run synth
```

## Security

The application implements security best practices:

- S3 bucket with encryption at rest and in transit
- Block all public access on S3 bucket
- IAM roles with least-privilege access
- VPC deployment options available
- Comprehensive logging and monitoring

## Cost Optimization

The solution includes cost optimization features:

- S3 lifecycle policies for automatic archiving
- Serverless Lambda with pay-per-use pricing
- Efficient resource sizing and timeouts
- Automatic cleanup of temporary resources

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure your AWS credentials have sufficient permissions
2. **Bootstrap Required**: Run `cdk bootstrap` if you haven't used CDK in your account/region
3. **Timeout Errors**: Increase Lambda timeout for large documents
4. **Unsupported Format**: Verify document format is supported by Textract

### Logs

Check CloudWatch logs for detailed error information:
```bash
aws logs tail /aws/lambda/<function-name> --follow
```

## Cleanup

To remove all resources:

```bash
npm run destroy
```

This will delete all created resources except for CloudWatch logs (which have a retention period).

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## Support

For issues and questions:

1. Check the AWS CDK documentation
2. Review CloudWatch logs for errors
3. Consult the Amazon Textract documentation
4. Check AWS service limits and quotas