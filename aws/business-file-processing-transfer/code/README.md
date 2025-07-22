# Infrastructure as Code for Business File Processing with Transfer Family

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Business File Processing with Transfer Family".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a fully automated file processing pipeline that:

- Provides secure SFTP endpoints via AWS Transfer Family
- Automatically validates, processes, and routes business files
- Uses Step Functions for workflow orchestration
- Leverages Lambda functions for custom processing logic
- Implements comprehensive monitoring and alerting
- Follows AWS security and compliance best practices

## Prerequisites

### Required Tools

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - AWS Transfer Family (create servers, users)
  - Step Functions (create state machines)
  - Lambda (create functions, roles)
  - S3 (create buckets, objects)
  - IAM (create roles, policies)
  - EventBridge (create rules, targets)
  - CloudWatch (create alarms)
  - SNS (create topics)

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI with CloudFormation permissions
- Understanding of YAML syntax

#### CDK TypeScript
- Node.js 18+ installed
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- TypeScript knowledge

#### CDK Python
- Python 3.8+ installed
- AWS CDK v2 installed (`pip install aws-cdk-lib`)
- Python development experience

#### Terraform
- Terraform 1.0+ installed
- Understanding of HCL syntax

#### Bash Scripts
- Bash shell environment
- AWS CLI configured with appropriate permissions

### Cost Considerations

Estimated monthly costs for development environment:
- AWS Transfer Family SFTP endpoint: ~$22/month ($0.30/hour)
- Lambda executions: ~$1-5/month (depends on file volume)
- S3 storage: ~$1-10/month (depends on file sizes)
- Step Functions executions: ~$1-3/month
- CloudWatch logs and monitoring: ~$1-2/month

**Total estimated cost: $26-42/month for development environment**

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name file-processing-pipeline \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=my-file-processing

# Monitor deployment progress
aws cloudformation describe-stack-events \
    --stack-name file-processing-pipeline

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name file-processing-pipeline \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# Get deployment outputs
cdk ls
```

### Using CDK Python
```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# Get deployment outputs
cdk ls
```

### Using Terraform
```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Deploy the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will:
# 1. Create S3 buckets for file storage
# 2. Deploy Lambda functions with processing logic
# 3. Create IAM roles and policies
# 4. Set up Step Functions workflow
# 5. Configure Transfer Family SFTP server
# 6. Establish EventBridge integration
# 7. Configure monitoring and alerting
```

## Post-Deployment Configuration

### 1. Set Up SFTP User Authentication

After deployment, configure SFTP users for your business partners:

```bash
# Get the Transfer Family server ID from outputs
TRANSFER_SERVER_ID="<server-id-from-outputs>"

# Create SSH key pair for SFTP authentication
ssh-keygen -t rsa -b 2048 -f sftp-user-key

# Import public key to Transfer Family user
aws transfer import-ssh-public-key \
    --server-id $TRANSFER_SERVER_ID \
    --user-name businesspartner \
    --ssh-public-key-body "$(cat sftp-user-key.pub)"
```

### 2. Test the File Processing Pipeline

```bash
# Create a test CSV file
cat > test-financial-data.csv << 'EOF'
transaction_id,amount,currency,date
TX001,1500.00,USD,2025-07-12
TX002,2750.50,USD,2025-07-12
TX003,890.25,EUR,2025-07-12
EOF

# Upload via SFTP (replace endpoint with your server's endpoint)
sftp -i sftp-user-key businesspartner@<transfer-server-endpoint>
> put test-financial-data.csv
> quit

# Or upload directly to S3 for testing
aws s3 cp test-financial-data.csv s3://<landing-bucket-name>/
```

### 3. Monitor Processing Results

```bash
# Check Step Functions execution status
aws stepfunctions list-executions \
    --state-machine-arn <state-machine-arn> \
    --max-items 5

# View processed files
aws s3 ls s3://<processed-bucket-name>/ --recursive

# Check archived files
aws s3 ls s3://<archive-bucket-name>/ --recursive

# Monitor CloudWatch logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/file-processing"
```

## Cleanup

### Using CloudFormation
```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name file-processing-pipeline

# Monitor deletion progress
aws cloudformation describe-stack-events \
    --stack-name file-processing-pipeline
```

### Using CDK
```bash
# Navigate to CDK directory (TypeScript or Python)
cd cdk-typescript/  # or cd cdk-python/

# Destroy the infrastructure
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform
```bash
# Navigate to Terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts
```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will safely remove all resources in reverse order:
# 1. EventBridge rules and Step Functions
# 2. Transfer Family servers and users
# 3. Lambda functions
# 4. S3 buckets and contents
# 5. IAM roles and policies
# 6. CloudWatch alarms and SNS topics
```

## Customization

### Environment Variables

All implementations support customization through variables:

- **ProjectName**: Prefix for resource naming (default: `file-processing`)
- **Environment**: Deployment environment (default: `dev`)
- **AlertEmail**: Email address for SNS notifications
- **FileRetentionDays**: Days to retain files in S3 (default: `30`)
- **ProcessingTimeout**: Lambda function timeout (default: `300` seconds)

### CloudFormation Parameters
```bash
aws cloudformation create-stack \
    --stack-name file-processing-pipeline \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=ProjectName,ParameterValue=my-company-files \
        ParameterKey=Environment,ParameterValue=production \
        ParameterKey=AlertEmail,ParameterValue=admin@company.com
```

### CDK Context Variables
```bash
# CDK TypeScript/Python
cdk deploy -c projectName=my-company-files -c environment=production
```

### Terraform Variables
```bash
# Using terraform.tfvars file
echo 'project_name = "my-company-files"' > terraform.tfvars
echo 'environment = "production"' >> terraform.tfvars
echo 'alert_email = "admin@company.com"' >> terraform.tfvars

terraform apply
```

### Bash Script Environment Variables
```bash
# Set environment variables before running deploy.sh
export PROJECT_NAME="my-company-files"
export ENVIRONMENT="production"
export ALERT_EMAIL="admin@company.com"

./scripts/deploy.sh
```

## File Processing Logic

### Supported File Formats

The default implementation supports CSV files but can be extended for:
- JSON data files
- XML documents
- Excel spreadsheets (with additional Lambda layers)
- Fixed-width text files

### Business Rules Engine

The processing Lambda functions implement configurable business rules:

1. **File Validation**: Format, size, and schema validation
2. **Data Transformation**: Standardization and enrichment
3. **Routing Logic**: Content-based routing to appropriate destinations
4. **Error Handling**: Retry logic and dead letter processing

### Extending Processing Logic

To customize the file processing logic:

1. **Modify Lambda Functions**: Update the Python code in the respective IaC templates
2. **Add New Processing Steps**: Extend the Step Functions state machine definition
3. **Configure Business Rules**: Update environment variables and configuration files
4. **Add New Destinations**: Extend routing logic for additional downstream systems

## Security Features

### Data Protection
- Encryption in transit (SFTP/TLS)
- Encryption at rest (S3, Lambda environment variables)
- IAM least privilege access
- VPC endpoint support (configurable)

### Compliance
- CloudTrail integration for audit logging
- S3 access logging
- CloudWatch detailed monitoring
- SNS notifications for security events

### Access Control
- IAM roles with minimal required permissions
- Resource-based policies for cross-service access
- SFTP user authentication via SSH keys or Active Directory
- Optional multi-factor authentication support

## Monitoring and Troubleshooting

### Key Metrics to Monitor
- Step Functions execution success rate
- Lambda function duration and error rate
- Transfer Family data transfer volume
- S3 storage growth and costs
- File processing latency

### Common Issues

1. **SFTP Connection Failures**
   - Verify Transfer Family server status
   - Check SSH key configuration
   - Validate user permissions

2. **File Processing Errors**
   - Review CloudWatch logs for Lambda functions
   - Check Step Functions execution history
   - Validate file format and schema

3. **Performance Issues**
   - Monitor Lambda memory usage and duration
   - Review S3 request patterns
   - Check EventBridge rule evaluation

### Debug Commands
```bash
# View Step Functions execution details
aws stepfunctions describe-execution \
    --execution-arn <execution-arn>

# Get Lambda function logs
aws logs filter-log-events \
    --log-group-name "/aws/lambda/<function-name>" \
    --start-time $(date -d '1 hour ago' +%s)000

# Check Transfer Family server logs
aws logs filter-log-events \
    --log-group-name "/aws/transfer/<server-id>" \
    --start-time $(date -d '1 hour ago' +%s)000
```

## Production Considerations

### High Availability
- Deploy across multiple Availability Zones
- Use S3 Cross-Region Replication for critical data
- Implement Lambda Reserved Concurrency for predictable performance
- Configure Transfer Family in multiple regions if needed

### Performance Optimization
- Use S3 Transfer Acceleration for global file uploads
- Implement Lambda Provisioned Concurrency for consistent performance
- Configure appropriate Step Functions timeouts
- Use S3 Intelligent Tiering for cost optimization

### Disaster Recovery
- Regular backup of configuration and code
- Cross-region replication of processed data
- Documented recovery procedures
- Regular testing of backup and restore processes

## Support

For issues with this infrastructure code:

1. **AWS Service Issues**: Refer to AWS documentation and support
2. **Infrastructure Code Issues**: Check the logs and validate configurations
3. **Recipe Questions**: Refer to the original recipe documentation
4. **Performance Tuning**: Review AWS Well-Architected Framework guidance

## Additional Resources

- [AWS Transfer Family User Guide](https://docs.aws.amazon.com/transfer/latest/userguide/)
- [AWS Step Functions Developer Guide](https://docs.aws.amazon.com/step-functions/latest/dg/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [AWS CloudFormation User Guide](https://docs.aws.amazon.com/cloudformation/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/)