# Infrastructure as Code for ACID-Compliant Distributed Databases with Amazon QLDB

This directory contains Infrastructure as Code (IaC) implementations for the recipe "ACID-Compliant Distributed Databases with Amazon QLDB".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amazon QLDB (full access)
  - IAM (role creation and policy management)
  - Amazon S3 (bucket creation and object management)
  - Amazon Kinesis (stream creation and management)
  - CloudFormation (for CloudFormation deployments)
- For CDK deployments: Node.js 18+ and Python 3.8+
- For Terraform deployments: Terraform 1.0+
- Estimated cost: $10-50 for QLDB usage, S3 storage, and Kinesis streaming (4 hours)

## Solution Overview

This infrastructure creates a comprehensive ACID-compliant ledger database solution with:

- **Amazon QLDB Ledger**: Immutable, cryptographically verifiable transaction database
- **IAM Roles**: Secure service-to-service authentication for journal streaming and exports
- **Amazon Kinesis**: Real-time journal data streaming for analytics and monitoring
- **Amazon S3**: Long-term archival storage for journal exports with encryption
- **Cryptographic Verification**: Built-in digest generation and Merkle proof validation

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name qldb-acid-database \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=LedgerName,ParameterValue=financial-ledger \
                 ParameterKey=Environment,ParameterValue=production \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name qldb-acid-database

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name qldb-acid-database \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy --parameters LedgerName=financial-ledger

# Verify deployment
npx cdk list
```

### Using CDK Python (AWS)

```bash
cd cdk-python/

# Create and activate virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters LedgerName=financial-ledger

# Verify deployment
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="ledger_name=financial-ledger" \
               -var="environment=production"

# Apply the configuration
terraform apply -var="ledger_name=financial-ledger" \
                -var="environment=production"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts to configure ledger name and environment
```

## Post-Deployment Configuration

After infrastructure deployment, you'll need to:

1. **Create Database Tables**:
   ```bash
   # Use QLDB console or SDK to create tables
   # See the main recipe for PartiQL table creation scripts
   ```

2. **Configure Journal Streaming** (if not auto-enabled):
   ```bash
   # Get the stream role ARN from outputs
   ROLE_ARN=$(aws cloudformation describe-stacks \
       --stack-name qldb-acid-database \
       --query 'Stacks[0].Outputs[?OutputKey==`StreamRoleArn`].OutputValue' \
       --output text)
   
   # Start streaming to Kinesis
   aws qldb stream-journal-to-kinesis \
       --ledger-name your-ledger-name \
       --role-arn $ROLE_ARN \
       --kinesis-configuration file://kinesis-config.json \
       --stream-name ledger-journal-stream
   ```

3. **Insert Sample Data**:
   ```bash
   # Use the sample data files from the main recipe
   # Connect via QLDB console or SDK to insert financial records
   ```

## Validation & Testing

### Verify QLDB Ledger

```bash
# Check ledger status
aws qldb describe-ledger --name your-ledger-name

# Generate cryptographic digest
aws qldb get-digest --name your-ledger-name
```

### Test Journal Streaming

```bash
# Check Kinesis stream
aws kinesis describe-stream --stream-name your-kinesis-stream-name

# List journal streams
aws qldb list-journal-kinesis-streams-for-ledger \
    --ledger-name your-ledger-name
```

### Verify S3 Export Capability

```bash
# List S3 bucket contents
aws s3 ls s3://your-export-bucket-name/

# Test export permissions
aws qldb export-journal-to-s3 \
    --name your-ledger-name \
    --inclusive-start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
    --exclusive-end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --role-arn your-role-arn \
    --s3-export-configuration file://s3-export-config.json
```

## Security Considerations

- **Encryption**: All data is encrypted at rest and in transit
- **IAM Roles**: Least privilege access for QLDB operations
- **S3 Bucket Policies**: Restricted access to authorized services only
- **Deletion Protection**: QLDB ledger created with deletion protection enabled
- **Network Security**: Consider VPC endpoints for private connectivity

## Monitoring and Observability

The infrastructure includes monitoring capabilities:

- **CloudWatch Metrics**: Automatic metrics for QLDB operations
- **Journal Streaming**: Real-time transaction monitoring via Kinesis
- **Audit Trails**: Complete transaction history in immutable journal
- **CloudTrail Integration**: API call logging for compliance

## Cost Optimization

- **QLDB Pricing**: Based on I/O requests and storage usage
- **Kinesis Costs**: Consider shard count based on data volume
- **S3 Storage**: Use lifecycle policies for long-term archival
- **Monitoring**: Set up billing alerts for cost control

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name qldb-acid-database

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name qldb-acid-database
```

### Using CDK (AWS)

```bash
cd cdk-typescript/ # or cdk-python/

# Destroy the stack
npx cdk destroy  # or: cdk destroy for Python

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy -var="ledger_name=financial-ledger" \
                  -var="environment=production"

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Customization

### Key Variables/Parameters

- **LedgerName**: Name for the QLDB ledger (default: financial-ledger)
- **Environment**: Deployment environment (dev/test/prod)
- **DeletionProtection**: Enable/disable ledger deletion protection
- **KinesisShardCount**: Number of Kinesis shards for streaming
- **S3BucketPrefix**: Prefix for S3 export bucket names
- **Tags**: Custom resource tags for cost allocation

### Configuration Files

Customize these files based on your requirements:

- `kinesis-config.json`: Kinesis streaming configuration
- `s3-export-config.json`: S3 export settings
- `terraform.tfvars`: Terraform variable values
- Environment-specific parameter files for CloudFormation

## Troubleshooting

### Common Issues

1. **Ledger Creation Fails**:
   - Check IAM permissions for QLDB operations
   - Verify region availability for QLDB service

2. **Journal Streaming Issues**:
   - Validate IAM role trust relationships
   - Check Kinesis stream capacity and limits

3. **S3 Export Failures**:
   - Verify S3 bucket permissions and encryption settings
   - Check IAM role policies for S3 access

### Debug Commands

```bash
# Check CloudFormation events
aws cloudformation describe-stack-events \
    --stack-name qldb-acid-database

# View QLDB ledger details
aws qldb describe-ledger --name your-ledger-name

# Check IAM role policies
aws iam get-role-policy \
    --role-name your-role-name \
    --policy-name your-policy-name
```

## Best Practices

- **Data Modeling**: Design tables for optimal PartiQL query performance
- **Transaction Patterns**: Implement proper ACID transaction boundaries
- **Verification**: Regular cryptographic digest verification for compliance
- **Backup Strategy**: Combine journal streaming and S3 exports for data durability
- **Security**: Regular review of IAM policies and access patterns

## Additional Resources

- [Amazon QLDB Developer Guide](https://docs.aws.amazon.com/qldb/latest/developerguide/)
- [QLDB PartiQL Reference](https://docs.aws.amazon.com/qldb/latest/developerguide/ql-reference.html)
- [Journal Streaming Documentation](https://docs.aws.amazon.com/qldb/latest/developerguide/streams.html)
- [Data Verification Guide](https://docs.aws.amazon.com/qldb/latest/developerguide/verification.html)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Refer to the original recipe documentation
3. Consult AWS documentation for specific services
4. Contact AWS Support for service-related issues

## Version Information

- **Recipe Version**: 1.1
- **IaC Generator Version**: 1.3
- **Last Updated**: 2025-07-12
- **Compatible AWS Regions**: All regions where QLDB is available

> **Note**: AWS announced end-of-support for QLDB on July 31, 2025. Consider migration strategies to Amazon Aurora PostgreSQL or other alternatives for new projects.