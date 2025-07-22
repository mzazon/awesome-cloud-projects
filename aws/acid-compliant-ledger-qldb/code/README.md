# Infrastructure as Code for ACID-Compliant Ledger Database with QLDB

This directory contains Infrastructure as Code (IaC) implementations for the recipe "ACID-Compliant Ledger Database with QLDB".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for QLDB, IAM, S3, and Kinesis services
- For CDK deployments: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+
- Basic understanding of financial data processing and audit requirements

### Required AWS Permissions

Your AWS credentials must have permissions for:
- Amazon QLDB (create/manage ledgers, streaming, exports)
- IAM (create/manage roles and policies)
- Amazon S3 (create/manage buckets and objects)
- Amazon Kinesis (create/manage streams)
- CloudFormation (if using CloudFormation deployment)

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name qldb-financial-ledger \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=production

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name qldb-financial-ledger \
    --query 'Stacks[0].StackStatus'
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

# List deployed resources
cdk list
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment (recommended)
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# List deployed resources
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Apply the infrastructure
terraform apply

# Show deployed resources
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
aws qldb list-ledgers
```

## Architecture Overview

This IaC deploys the following AWS resources:

- **Amazon QLDB Ledger**: Immutable database with cryptographic verification
- **IAM Role**: Service role for QLDB streaming and export operations
- **Amazon S3 Bucket**: Storage for journal exports and audit archives
- **Amazon Kinesis Data Stream**: Real-time journal streaming
- **IAM Policies**: Least privilege access control for service integration

## Configuration Options

### Environment Variables

Set these environment variables before deployment:

```bash
export AWS_REGION=us-east-1
export ENVIRONMENT=production
export LEDGER_NAME=financial-ledger
export ENABLE_DELETION_PROTECTION=true
```

### CloudFormation Parameters

- `Environment`: Deployment environment (default: production)
- `LedgerName`: Name for the QLDB ledger (default: financial-ledger)
- `EnableDeletionProtection`: Enable deletion protection (default: true)
- `KinesisShardCount`: Number of Kinesis shards (default: 1)

### CDK Context Variables

```json
{
  "environment": "production",
  "ledgerName": "financial-ledger",
  "enableDeletionProtection": true,
  "kinesisShardCount": 1
}
```

### Terraform Variables

Customize deployment in `terraform.tfvars`:

```hcl
environment = "production"
ledger_name = "financial-ledger"
enable_deletion_protection = true
kinesis_shard_count = 1
aws_region = "us-east-1"
```

## Validation and Testing

### Verify QLDB Ledger

```bash
# Check ledger status
aws qldb describe-ledger --name financial-ledger

# Generate cryptographic digest
aws qldb get-digest --name financial-ledger
```

### Test Journal Streaming

```bash
# List active streams
aws qldb list-journal-kinesis-streams-for-ledger \
    --ledger-name financial-ledger

# Check Kinesis stream
aws kinesis describe-stream --stream-name financial-ledger-stream
```

### Validate S3 Export Capability

```bash
# List S3 bucket contents
aws s3 ls s3://qldb-exports-bucket/ --recursive

# Test export permissions
aws qldb describe-journal-s3-export \
    --name financial-ledger \
    --export-id <export-id>
```

## Cost Considerations

This infrastructure incurs charges for:

- **QLDB**: Storage and I/O requests (~$0.15/million requests)
- **Kinesis**: Shard hours and data ingress (~$0.015/shard/hour)
- **S3**: Storage and requests (~$0.023/GB standard storage)
- **Data Transfer**: Cross-region or internet transfer fees

Estimated monthly cost for moderate usage: $50-200

## Security Features

- **Encryption**: All data encrypted at rest and in transit
- **IAM Roles**: Least privilege access using service roles
- **Deletion Protection**: Prevents accidental ledger deletion
- **Audit Logging**: Complete transaction audit trail
- **Cryptographic Verification**: SHA-256 hash-based integrity proofs

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name qldb-financial-ledger

# Monitor deletion progress
aws cloudformation describe-stacks --stack-name qldb-financial-ledger
```

### Using CDK

```bash
# Destroy infrastructure (TypeScript)
cd cdk-typescript/
cdk destroy

# Destroy infrastructure (Python)
cd cdk-python/
cdk destroy
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
aws qldb list-ledgers
aws s3 ls | grep qldb-exports
```

## Troubleshooting

### Common Issues

1. **Insufficient Permissions**
   - Ensure your AWS credentials have all required permissions
   - Check IAM policies for QLDB, S3, Kinesis, and IAM access

2. **Ledger Creation Fails**
   - Verify ledger name uniqueness in your account
   - Check regional service availability for QLDB

3. **Streaming Setup Issues**
   - Ensure IAM role has proper trust relationship
   - Verify Kinesis stream is active before creating QLDB stream

4. **Export Failures**
   - Check S3 bucket permissions and encryption settings
   - Verify export time range is valid

### Debug Commands

```bash
# Check QLDB service status
aws qldb describe-ledger --name <ledger-name>

# Verify IAM role
aws iam get-role --role-name <role-name>

# Test S3 access
aws s3 ls s3://<bucket-name>

# Check Kinesis stream
aws kinesis describe-stream --stream-name <stream-name>
```

## Customization

### Adding Custom Tables

Modify the IaC to include table creation:

```sql
-- Add to initialization scripts
CREATE TABLE CustomTransactions;
CREATE INDEX ON CustomTransactions (customField);
```

### Enhanced Monitoring

Add CloudWatch alarms for operational monitoring:

```yaml
# CloudFormation example
QLDBStreamAlarm:
  Type: AWS::CloudWatch::Alarm
  Properties:
    AlarmName: QLDB-Stream-Errors
    MetricName: StreamErrors
    Namespace: AWS/QLDB
```

### Multi-Region Setup

For disaster recovery, deploy to multiple regions:

```bash
# Deploy to primary region
export AWS_REGION=us-east-1
terraform apply

# Deploy to secondary region
export AWS_REGION=us-west-2
terraform apply
```

## Support and Documentation

- [Amazon QLDB Developer Guide](https://docs.aws.amazon.com/qldb/latest/developerguide/)
- [QLDB API Reference](https://docs.aws.amazon.com/qldb/latest/developerguide/API_Reference.html)
- [AWS CloudFormation QLDB Resources](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/AWS_QLDB.html)
- [Recipe Documentation](../acid-compliant-distributed-databases-amazon-qldb.md)

For issues with this infrastructure code, refer to the original recipe documentation or AWS support resources.

## Important Notes

> **Warning**: QLDB announced end-of-support on July 31, 2025. Consider this for long-term projects and evaluate migration options to Amazon Aurora PostgreSQL or similar solutions.

> **Note**: This infrastructure implements financial-grade security and compliance features. Review all configurations against your organization's security policies before production deployment.

> **Tip**: Use QLDB's history() function in PartiQL queries to access complete audit trails for regulatory compliance and forensic analysis.