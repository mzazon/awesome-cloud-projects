# Simple Text Processing CDK Python Application

This AWS CDK Python application creates the infrastructure needed for simple text processing workflows using AWS CloudShell and Amazon S3. The application demonstrates how to set up a cloud-based environment for text analysis tasks without requiring local development environment setup.

## Architecture Overview

The infrastructure includes:

- **Amazon S3 Bucket**: Secure storage for input and output text files with organized folder structure
- **IAM Policies**: Proper permissions for CloudShell access to S3 resources  
- **Lifecycle Rules**: Cost optimization through automatic storage class transitions
- **Security Features**: Encryption, SSL enforcement, and public access blocking

## Prerequisites

- Python 3.8 or later
- AWS CLI configured with appropriate credentials
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- AWS account with permissions to create S3 buckets and IAM policies

## Installation and Setup

### 1. Clone and Navigate to the Directory

```bash
cd ./aws/simple-text-processing-cloudshell-s3/code/cdk-python/
```

### 2. Set up Python Virtual Environment

```bash
# Create virtual environment
python -m venv .venv

# Activate virtual environment (Linux/macOS)
source .venv/bin/activate

# Activate virtual environment (Windows)
.venv\Scripts\activate
```

### 3. Install Dependencies

```bash
# Install required packages
pip install -r requirements.txt

# Install development dependencies (optional)
pip install -e ".[dev]"
```

### 4. Bootstrap CDK (if first time using CDK in your account/region)

```bash
cdk bootstrap
```

## Deployment

### 1. Synthesize CloudFormation Template

```bash
# Generate CloudFormation template
cdk synth

# View the generated template
cdk synth --output-dir cdk.out
```

### 2. Deploy the Stack

```bash
# Deploy to default account/region
cdk deploy

# Deploy with custom context values
cdk deploy --context bucketPrefix=my-custom-prefix --context environment=production
```

### 3. View Stack Outputs

After deployment, the stack will output important information:

- **TextProcessingBucketName**: Name of the created S3 bucket
- **TextProcessingBucketArn**: ARN of the S3 bucket
- **InputFolderPath**: S3 path for input files (`s3://bucket-name/input/`)
- **OutputFolderPath**: S3 path for output files (`s3://bucket-name/output/`)
- **CloudShellAccessCommand**: AWS CLI command to access the bucket from CloudShell

## Usage

Once deployed, you can use the infrastructure for text processing:

### 1. Access AWS CloudShell

1. Log into the AWS Management Console
2. Click the CloudShell icon in the top navigation bar
3. Wait for CloudShell to initialize

### 2. Verify Bucket Access

```bash
# Use the command from stack outputs
aws s3 ls s3://your-bucket-name/

# Upload a sample file
echo "Hello, World!" > sample.txt
aws s3 cp sample.txt s3://your-bucket-name/input/
```

### 3. Process Text Files

```bash
# Download file for processing
aws s3 cp s3://your-bucket-name/input/sample.txt .

# Process with Linux tools
cat sample.txt | wc -w > word_count.txt

# Upload processed results
aws s3 cp word_count.txt s3://your-bucket-name/output/
```

## Configuration Options

### Context Variables

You can customize the deployment using CDK context variables:

- `bucketPrefix`: Custom prefix for the S3 bucket name (default: "text-processing-demo")
- `environment`: Environment tag (default: "development")
- `region`: AWS region for deployment (default: from AWS CLI config)
- `account`: AWS account ID (default: from AWS CLI config)

### Example with Custom Configuration

```bash
cdk deploy \
  --context bucketPrefix=analytics-workspace \
  --context environment=production \
  --context region=us-west-2
```

### Environment Variables

You can also set configuration through environment variables:

```bash
export CDK_DEFAULT_ACCOUNT=123456789012
export CDK_DEFAULT_REGION=us-west-2
cdk deploy
```

## Security Features

The application implements several security best practices:

### S3 Security
- **Encryption**: S3-managed encryption (SSE-S3) enabled
- **SSL Enforcement**: HTTPS required for all requests
- **Public Access**: All public access blocked
- **Bucket Policy**: Restricts access to CloudShell and account users

### IAM Security
- **Least Privilege**: Minimal required permissions for CloudShell access
- **Regional Restriction**: Access limited to deployment region
- **Service Principals**: Proper service principal configuration

## Cost Optimization

The application includes several cost optimization features:

### Lifecycle Management
- **Intelligent Tiering**: Automatic transition to IA after 30 days
- **Glacier Archive**: Transition to Glacier after 90 days
- **Cleanup**: Automatic deletion of incomplete multipart uploads

### Resource Tagging
All resources are tagged for cost tracking:
- `Project`: SimpleTextProcessing
- `Environment`: development/production
- `ManagedBy`: AWS-CDK
- `CostCenter`: DataAnalytics

## Development

### Code Quality Tools

The project includes several development tools:

```bash
# Format code
black .

# Lint code
flake8 .

# Type checking
mypy .

# Security scanning
bandit -r . -x tests/
```

### Testing

```bash
# Run unit tests
pytest tests/ -v

# Run tests with coverage
pytest tests/ -v --cov=.

# Run all quality checks
python -m pytest tests/ -v --cov=.
python -m flake8 .
python -m mypy .
python -m bandit -r . -x tests/
```

### Adding New Features

1. Create new constructs in the stack class
2. Add appropriate tests in the `tests/` directory
3. Update documentation and requirements as needed
4. Run quality checks before committing

## Troubleshooting

### Common Issues

**1. CDK Bootstrap Required**
```
Error: This stack uses assets, so the toolkit stack must be deployed
```
Solution: Run `cdk bootstrap` in your account/region

**2. Bucket Name Conflicts**
```
Error: Bucket name already exists
```
Solution: Use a custom bucket prefix with `--context bucketPrefix=unique-name`

**3. Permission Denied in CloudShell**
```
Error: Access Denied when accessing S3
```
Solution: Ensure your CloudShell session has the required IAM permissions

**4. Python Version Issues**
```
Error: Python version compatibility
```
Solution: Use Python 3.8+ and activate virtual environment

### Debug Mode

Enable debug output for troubleshooting:

```bash
# Verbose CDK output
cdk deploy --verbose

# Debug CloudFormation events
cdk deploy --debug
```

## Cleanup

To avoid ongoing costs, clean up resources when done:

```bash
# Delete the stack and all resources
cdk destroy

# Confirm deletion when prompted
# This will delete the S3 bucket and all contained objects
```

**Note**: The S3 bucket is configured with `RemovalPolicy.DESTROY` and `auto_delete_objects=True` for easy cleanup in development. For production use, consider changing to `RETAIN` policy.

## Support and Contributing

### Getting Help

- Review AWS CDK documentation: https://docs.aws.amazon.com/cdk/
- Check AWS CloudShell documentation: https://docs.aws.amazon.com/cloudshell/
- Review S3 best practices: https://docs.aws.amazon.com/s3/latest/userguide/best-practices.html

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes and add tests
4. Run quality checks
5. Submit a pull request

## License

This project is licensed under the MIT License. See LICENSE file for details.

## Related Resources

- [AWS CDK Python Reference](https://docs.aws.amazon.com/cdk/api/v2/python/)
- [AWS CloudShell User Guide](https://docs.aws.amazon.com/cloudshell/latest/userguide/)
- [Amazon S3 User Guide](https://docs.aws.amazon.com/s3/latest/userguide/)
- [Linux Text Processing Commands](https://www.gnu.org/software/gawk/manual/gawk.html)