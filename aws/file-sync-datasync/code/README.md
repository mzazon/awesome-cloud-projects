# Infrastructure as Code for File System Sync with DataSync and EFS

This directory contains Infrastructure as Code (IaC) implementations for the recipe "File System Sync with DataSync and EFS".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for DataSync, EFS, VPC, S3, and IAM services
- Administrative access to create VPCs, security groups, and IAM roles
- Basic understanding of AWS networking and file systems

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI with CloudFormation permissions
- IAM permissions to create stacks with CAPABILITY_IAM

#### CDK TypeScript
- Node.js 18+ and npm installed
- AWS CDK CLI installed: `npm install -g aws-cdk`
- TypeScript installed: `npm install -g typescript`

#### CDK Python
- Python 3.8+ installed
- AWS CDK CLI installed: `pip install aws-cdk-lib`
- Virtual environment recommended

#### Terraform
- Terraform 1.5+ installed
- AWS provider 5.0+ support

## Quick Start

### Using CloudFormation
```bash
# Create the stack with required capabilities
aws cloudformation create-stack \
    --stack-name datasync-efs-sync-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=datasync-demo

# Monitor stack creation
aws cloudformation wait stack-create-complete \
    --stack-name datasync-efs-sync-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name datasync-efs-sync-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# List stack outputs
cdk ls --long
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# List stack outputs
cdk ls --long
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will create all resources and display connection information
```

## Post-Deployment Steps

After deploying the infrastructure, you can test the synchronization:

1. **Upload test files to the source S3 bucket**:
   ```bash
   # Get bucket name from outputs
   SOURCE_BUCKET=$(aws cloudformation describe-stacks \
       --stack-name datasync-efs-sync-stack \
       --query 'Stacks[0].Outputs[?OutputKey==`SourceBucketName`].OutputValue' \
       --output text)
   
   # Upload test files
   echo "Test file content" > test-file.txt
   aws s3 cp test-file.txt s3://${SOURCE_BUCKET}/
   ```

2. **Execute the DataSync task**:
   ```bash
   # Get task ARN from outputs
   TASK_ARN=$(aws cloudformation describe-stacks \
       --stack-name datasync-efs-sync-stack \
       --query 'Stacks[0].Outputs[?OutputKey==`DataSyncTaskArn`].OutputValue' \
       --output text)
   
   # Start task execution
   aws datasync start-task-execution --task-arn ${TASK_ARN}
   ```

3. **Monitor synchronization progress**:
   ```bash
   # List recent task executions
   aws datasync list-task-executions --task-arn ${TASK_ARN}
   ```

## Architecture Overview

The deployed infrastructure includes:

- **VPC and Networking**: Private subnet with security groups for EFS access
- **Amazon EFS**: Encrypted file system with mount targets
- **S3 Source Bucket**: Source storage with sample data
- **DataSync Task**: Configured synchronization between S3 and EFS
- **IAM Roles**: Service roles for DataSync operations
- **CloudWatch Logs**: Monitoring and logging for transfer operations

## Configuration Options

### CloudFormation Parameters
- `ProjectName`: Prefix for resource names (default: datasync-efs)
- `VpcCidr`: CIDR block for VPC (default: 10.0.0.0/16)
- `EfsPerformanceMode`: EFS performance mode (generalPurpose or maxIO)
- `EfsThroughputMode`: EFS throughput mode (bursting or provisioned)

### CDK/Terraform Variables
- `project_name`: Project name prefix for resources
- `vpc_cidr`: VPC CIDR block
- `efs_performance_mode`: EFS performance configuration
- `enable_encryption`: Enable encryption at rest (default: true)
- `datasync_log_level`: DataSync logging level (OFF, BASIC, TRANSFER)

## Monitoring and Troubleshooting

### CloudWatch Metrics
Monitor these key metrics:
- `AWS/DataSync/BytesTransferred`: Amount of data synchronized
- `AWS/EFS/DataReadIOBytes`: EFS read operations
- `AWS/EFS/TotalIOTime`: File system performance

### Logs
- DataSync task execution logs in CloudWatch Logs
- VPC Flow Logs for network troubleshooting
- EFS performance metrics

### Common Issues
1. **Task execution fails**: Check IAM permissions and network connectivity
2. **Slow transfers**: Review bandwidth settings and network configuration
3. **Access denied**: Verify security group rules and IAM policies

## Cleanup

### Using CloudFormation
```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name datasync-efs-sync-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name datasync-efs-sync-stack
```

### Using CDK
```bash
# Destroy the CDK stack
cd cdk-typescript/  # or cdk-python/
cdk destroy

# Confirm when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts
```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm resource deletion when prompted
```

## Cost Considerations

### Primary Cost Components
- **DataSync**: $0.0125 per GB transferred
- **EFS Storage**: $0.30 per GB-month (Standard class)
- **VPC**: No additional charges for basic VPC resources
- **S3**: Standard storage and request charges

### Cost Optimization Tips
- Use EFS Infrequent Access storage class for rarely accessed files
- Schedule DataSync tasks during off-peak hours
- Implement S3 lifecycle policies for source data
- Monitor transfer volumes with CloudWatch alarms

## Security Features

### Implemented Security Controls
- **Encryption**: EFS encrypted at rest with AWS managed keys
- **Network Security**: VPC isolation with security groups
- **IAM**: Least privilege access for DataSync service role
- **Audit Logging**: CloudTrail integration for API calls

### Additional Security Recommendations
- Use customer-managed KMS keys for enhanced encryption control
- Implement VPC endpoints for S3 access
- Enable CloudTrail for comprehensive audit logging
- Regular review of IAM permissions

## Customization

### Adding Custom Data Sources
Modify the Terraform/CloudFormation templates to:
- Add additional S3 buckets as data sources
- Configure on-premises NFS locations with DataSync agents
- Implement custom file filtering rules

### Scaling Considerations
- Multiple EFS mount targets across availability zones
- DataSync task scheduling for large datasets
- EFS performance mode selection based on workload

### Integration Options
- Lambda functions for automated task triggering
- SNS notifications for task completion
- CloudWatch Events for scheduled synchronization

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS DataSync documentation: https://docs.aws.amazon.com/datasync/
3. Consult AWS EFS documentation: https://docs.aws.amazon.com/efs/
4. AWS Support (for account-specific issues)

## Version History

- **v1.1**: Initial infrastructure code generation
- Supports AWS DataSync, EFS, and S3 integration
- Includes comprehensive monitoring and security controls