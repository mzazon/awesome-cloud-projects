# AWS CLI Setup and First Commands - CDK TypeScript

This CDK TypeScript application creates the infrastructure needed for the **AWS CLI Setup and First Commands** recipe. It provides a complete environment for learning and practicing AWS CLI operations with S3.

## What This Creates

This CDK application deploys:

1. **S3 Bucket** - Encrypted bucket for practicing CLI commands
2. **IAM User** - User with appropriate permissions for CLI access
3. **Access Keys** - Programmatic access credentials for CLI configuration
4. **Sample Objects** - Pre-loaded files for testing CLI operations
5. **Security Policies** - Least-privilege policies for safe learning

## Architecture

```
┌─────────────────┐    ┌───────────────────┐    ┌─────────────────┐
│   AWS CLI       │    │   IAM User        │    │   S3 Bucket     │
│   (Local)       │───▶│   + Access Keys   │───▶│   + Sample      │
│                 │    │   + Policies      │    │     Objects     │
└─────────────────┘    └───────────────────┘    └─────────────────┘
```

## Prerequisites

- AWS CLI v2 installed locally
- Node.js 18+ and npm
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- AWS account with permissions to create IAM users, S3 buckets, and policies

## Quick Start

### 1. Install Dependencies

```bash
cd aws/aws-cli-setup-first-commands/code/cdk-typescript/
npm install
```

### 2. Bootstrap CDK (if not done before)

```bash
cdk bootstrap
```

### 3. Deploy the Infrastructure

```bash
cdk deploy
```

### 4. Configure AWS CLI

After deployment, use the stack outputs to configure your CLI:

```bash
# Use the values from CDK outputs
aws configure

# Test your configuration
aws sts get-caller-identity
aws s3 ls s3://YOUR-BUCKET-NAME/
```

## Stack Outputs

The stack provides these outputs for CLI configuration:

- **BucketName**: S3 bucket name for CLI practice
- **UserName**: IAM user name for CLI access
- **AccessKeyId**: Access Key ID for CLI configuration
- **SecretAccessKey**: Secret Access Key (store securely!)
- **Region**: AWS region for CLI configuration
- **CliConfigInstructions**: Step-by-step setup instructions

## CLI Commands to Practice

Once deployed, practice these CLI commands:

```bash
# List bucket contents
aws s3 ls s3://YOUR-BUCKET-NAME/

# Download a sample file
aws s3 cp s3://YOUR-BUCKET-NAME/sample-file.txt ./

# Upload a new file
echo "Hello from CLI!" > test-upload.txt
aws s3 cp test-upload.txt s3://YOUR-BUCKET-NAME/

# Check bucket encryption
aws s3api get-bucket-encryption --bucket YOUR-BUCKET-NAME

# List objects with metadata
aws s3api list-objects-v2 --bucket YOUR-BUCKET-NAME

# Use JMESPath queries
aws s3api list-objects-v2 --bucket YOUR-BUCKET-NAME \
    --query 'Contents[].{Name:Key,Size:Size}' --output table
```

## Security Features

This implementation includes security best practices:

- **Encryption**: S3 bucket uses AES-256 server-side encryption
- **Block Public Access**: All public access is blocked by default
- **Least Privilege**: IAM policies grant minimal required permissions
- **Versioning**: S3 versioning enabled for object history
- **Lifecycle Rules**: Automatic cleanup after 7 days to control costs

## Cost Management

To minimize costs during learning:

- **Lifecycle Rules**: Objects auto-delete after 7 days
- **Small Objects**: Sample files are minimal in size
- **Regional Deployment**: Uses your default region to avoid cross-region charges
- **Easy Cleanup**: Simple `cdk destroy` removes all resources

## Customization

### Environment Variables

Set these before deployment to customize:

```bash
export CDK_DEFAULT_REGION=us-west-2  # Change region
export CDK_DEFAULT_ACCOUNT=123456789  # Specify account
```

### Modify Resources

Edit `app.ts` to customize:

- Bucket name prefix
- IAM permissions
- Sample file content
- Lifecycle rules
- Encryption settings

## Development

### Build and Test

```bash
# Compile TypeScript
npm run build

# Run tests
npm run test

# Lint code
npm run lint

# Format code
npm run format
```

### CDK Commands

```bash
# See differences before deploy
cdk diff

# Synthesize CloudFormation template
cdk synth

# Deploy specific stack
cdk deploy AwsCliSetupStack

# View stack resources
aws cloudformation describe-stacks --stack-name AwsCliSetupStack
```

## Troubleshooting

### Common Issues

1. **Bucket Name Conflicts**
   - Solution: The CDK generates unique names automatically

2. **Permission Errors**
   - Solution: Ensure your AWS credentials have IAM and S3 permissions

3. **CLI Not Configured**
   - Solution: Use the stack outputs to run `aws configure`

4. **Region Mismatch**
   - Solution: Ensure CDK region matches your AWS CLI default region

### Verification Steps

```bash
# Verify stack exists
aws cloudformation describe-stacks --stack-name AwsCliSetupStack

# Verify bucket exists
aws s3 ls | grep cli-tutorial

# Verify IAM user exists
aws iam get-user --user-name YOUR-USER-NAME

# Test CLI access
aws sts get-caller-identity
```

## Cleanup

### Remove All Resources

```bash
# Destroy the stack
cdk destroy

# Verify cleanup
aws cloudformation list-stacks --stack-status-filter DELETE_COMPLETE
```

### Manual Cleanup (if needed)

```bash
# Delete remaining objects (if any)
aws s3 rm s3://YOUR-BUCKET-NAME/ --recursive

# Delete access keys
aws iam delete-access-key --user-name YOUR-USER-NAME --access-key-id YOUR-KEY-ID
```

## Learning Path

After mastering this basic setup, explore:

1. **AWS CLI Profiles** - Manage multiple environments
2. **Advanced S3 Commands** - Sync, lifecycle, and policies
3. **Other AWS Services** - EC2, Lambda, and CloudFormation CLI
4. **Automation Scripts** - Bash scripts using AWS CLI
5. **CI/CD Integration** - Use CLI in deployment pipelines

## Resources

- [AWS CLI User Guide](https://docs.aws.amazon.com/cli/latest/userguide/)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [S3 CLI Reference](https://docs.aws.amazon.com/cli/latest/reference/s3/)
- [IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)

## Support

- Check the [original recipe](../../aws-cli-setup-first-commands.md) for detailed explanations
- Review AWS CLI documentation for command syntax
- Use `aws help` or `aws s3 help` for inline documentation

---

**Note**: This infrastructure is designed for learning purposes. For production use, consider additional security measures like MFA, temporary credentials, and more restrictive policies.