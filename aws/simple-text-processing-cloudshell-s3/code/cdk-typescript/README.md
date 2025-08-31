# Simple Text Processing with CloudShell and S3 - CDK TypeScript

This directory contains a CDK TypeScript application that creates the infrastructure for simple text processing using AWS CloudShell and S3, following the recipe "Simple Text Processing with CloudShell and S3".

## Architecture

The CDK application creates:

- **S3 Bucket**: Secure storage for input and output text files with:
  - Server-side encryption (S3-managed keys)
  - Versioning enabled for data protection
  - Lifecycle policies for cost optimization
  - Organized folder structure (input/, output/, processing/)
  - EventBridge integration for monitoring

- **IAM Role**: CloudShell role with least-privilege permissions for:
  - S3 bucket read/write access
  - CloudShell environment management
  - Secure cross-service access

## Prerequisites

- AWS CLI installed and configured
- Node.js 18.x or later
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions to create IAM roles and S3 buckets

## Getting Started

### 1. Install Dependencies

```bash
npm install
```

### 2. Bootstrap CDK (if not already done)

```bash
cdk bootstrap
```

### 3. Review Infrastructure

```bash
cdk synth
```

This command compiles TypeScript and generates CloudFormation templates for review.

### 4. Deploy Infrastructure

```bash
cdk deploy
```

The deployment will create:
- S3 bucket with unique name
- IAM role for CloudShell access
- Organized folder structure
- Security configurations

### 5. Verify Deployment

After deployment, note the outputs:
- `BucketName`: Name of the created S3 bucket
- `CloudShellRoleArn`: ARN of the IAM role for CloudShell
- `UsageInstructions`: Command to list bucket contents

## Using the Infrastructure

### Access from CloudShell

1. Open AWS CloudShell from the AWS Console
2. Use the bucket name from the deployment outputs
3. Follow the recipe instructions for text processing

Example commands:
```bash
# Set environment variable with your bucket name
export BUCKET_NAME="your-bucket-name-from-outputs"

# List bucket contents
aws s3 ls s3://${BUCKET_NAME}/

# Upload sample data
aws s3 cp sales_data.txt s3://${BUCKET_NAME}/input/

# Download for processing
aws s3 cp s3://${BUCKET_NAME}/input/sales_data.txt .
```

### Security Features

- **Encryption**: All data encrypted at rest using S3-managed keys
- **Access Control**: Bucket blocks all public access
- **SSL/TLS**: Enforce SSL for all bucket requests
- **IAM**: Least-privilege role with specific S3 permissions
- **Versioning**: Enabled for data protection and recovery

### Cost Optimization

- **Lifecycle Policies**: Automatic transition to lower-cost storage classes
- **Incomplete Upload Cleanup**: Automatic cleanup of failed multipart uploads
- **Regional Deployment**: Resources created in specified region

## Development

### Project Structure

```
├── app.ts                           # Main CDK application entry point
├── lib/
│   └── simple-text-processing-stack.ts  # Stack definition with resources
├── package.json                     # Dependencies and scripts
├── tsconfig.json                    # TypeScript configuration
├── cdk.json                         # CDK configuration
└── README.md                        # This file
```

### Available Scripts

```bash
npm run build      # Compile TypeScript
npm run watch      # Watch for changes and recompile
npm run test       # Run unit tests
npm run synth      # Synthesize CloudFormation template
npm run deploy     # Deploy infrastructure
npm run destroy    # Destroy infrastructure
npm run diff       # Show differences with deployed stack
```

### Security Validation

The application includes CDK Nag for security best practices validation:

```bash
cdk synth
```

This will show any security recommendations or issues that need attention.

## Configuration Options

### Environment Variables

- `CDK_DEFAULT_ACCOUNT`: AWS account ID for deployment
- `CDK_DEFAULT_REGION`: AWS region for deployment (default: us-east-1)

### Customization

Modify `lib/simple-text-processing-stack.ts` to customize:

- Bucket naming strategy
- Lifecycle policies
- Storage classes
- IAM permissions
- Tagging strategy

## Cleanup

To remove all created resources:

```bash
cdk destroy
```

This will delete:
- S3 bucket and all contents
- IAM role and policies
- All associated resources

**Note**: The bucket is configured for automatic object deletion during stack destruction for demo purposes. In production, consider using retention policies.

## Troubleshooting

### Common Issues

1. **Bootstrap Required**: If you see bootstrap errors, run `cdk bootstrap`
2. **Permissions**: Ensure your AWS credentials have sufficient permissions
3. **Bucket Names**: Bucket names must be globally unique
4. **Region**: Ensure you're deploying to the intended region

### Getting Help

- Check CloudFormation stack events in AWS Console
- Review CDK output for detailed error messages
- Verify IAM permissions for deployment
- Check AWS service quotas and limits

## Best Practices

- **Security**: Follow least-privilege principle for IAM roles
- **Cost**: Monitor S3 storage costs and lifecycle policies
- **Monitoring**: Use CloudWatch and EventBridge for observability
- **Backup**: Consider cross-region replication for critical data
- **Documentation**: Keep infrastructure documentation up to date

## Next Steps

After successful deployment:

1. Follow the main recipe instructions for text processing workflows
2. Explore advanced Linux text processing commands in CloudShell
3. Consider automation with Lambda functions for large-scale processing
4. Implement monitoring and alerting for production workloads

For more information, refer to the complete recipe documentation.