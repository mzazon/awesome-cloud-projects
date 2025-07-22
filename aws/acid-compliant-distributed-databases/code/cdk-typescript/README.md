# CDK TypeScript - Building ACID-Compliant Distributed Databases with Amazon QLDB

This CDK TypeScript application creates a complete infrastructure for building ACID-compliant distributed databases using Amazon QLDB with cryptographic verification, real-time journal streaming, and comprehensive audit capabilities.

## Architecture Overview

The CDK application deploys the following AWS resources:

- **Amazon QLDB Ledger**: Fully managed ledger database with cryptographic verification
- **IAM Role**: Service role for QLDB operations with least privilege permissions
- **S3 Bucket**: Encrypted storage for journal exports with lifecycle policies
- **Kinesis Data Stream**: Real-time streaming of journal data with encryption
- **CloudWatch Log Group**: Centralized logging for monitoring and auditing

## Prerequisites

1. **AWS CLI**: Version 2.x installed and configured
2. **Node.js**: Version 18.x or later
3. **AWS CDK**: Version 2.100.0 or later
4. **TypeScript**: Version 5.x or later
5. **AWS Account**: With appropriate permissions for QLDB, IAM, S3, and Kinesis

### Required AWS Permissions

Your AWS credentials must have permissions for:
- `qldb:*` - QLDB operations
- `iam:CreateRole`, `iam:AttachRolePolicy`, `iam:PutRolePolicy` - IAM management
- `s3:CreateBucket`, `s3:PutBucketPolicy` - S3 bucket operations
- `kinesis:CreateStream`, `kinesis:DescribeStream` - Kinesis operations
- `logs:CreateLogGroup` - CloudWatch Logs operations
- `kms:*` - KMS key operations for encryption

## Installation and Setup

1. **Clone and Navigate to Directory**:
   ```bash
   cd aws/building-acid-compliant-distributed-databases-amazon-qldb/code/cdk-typescript/
   ```

2. **Install Dependencies**:
   ```bash
   npm install
   ```

3. **Configure AWS CLI** (if not already done):
   ```bash
   aws configure
   ```

4. **Bootstrap CDK** (first time only):
   ```bash
   cdk bootstrap
   ```

## Configuration Options

### Environment Variables

You can customize the deployment using environment variables:

```bash
# Environment name for resource tagging
export ENVIRONMENT_NAME=production

# Application name for resource naming
export APPLICATION_NAME=financial

# Number of Kinesis shards (default: 1)
export KINESIS_SHARD_COUNT=2

# Enable deletion protection (default: true)
export ENABLE_DELETION_PROTECTION=true
```

### CDK Context Parameters

Alternatively, use CDK context parameters:

```bash
cdk deploy -c environment=staging -c application=banking -c kinesisShardCount=2
```

## Deployment

### Standard Deployment

1. **Synthesize CloudFormation Template** (optional but recommended):
   ```bash
   npm run synth
   ```

2. **Deploy the Stack**:
   ```bash
   npm run deploy
   ```

   Or using CDK directly:
   ```bash
   cdk deploy
   ```

### Customized Deployment

Deploy with custom configuration:

```bash
cdk deploy \
  -c environment=production \
  -c application=trading \
  -c kinesisShardCount=3 \
  -c enableDeletionProtection=true
```

### Review Changes Before Deployment

```bash
cdk diff
```

## Post-Deployment Operations

After successful deployment, the stack outputs provide important information and CLI commands:

### 1. Create QLDB Tables and Indexes

```bash
# Note: Table creation requires programmatic access using AWS SDK
# The following tables should be created via application code:
# - Accounts (with index on accountId)
# - Transactions (with indexes on transactionId, fromAccountId, toAccountId)
# - AuditLog (with index on timestamp)
```

### 2. Start Journal Streaming

Use the output command `StartStreamingCommand` or run:

```bash
# Get the exact command from stack outputs
aws cloudformation describe-stacks \
  --stack-name QLDBFinancialLedgerStack \
  --query 'Stacks[0].Outputs[?OutputKey==`StartStreamingCommand`].OutputValue' \
  --output text
```

### 3. Export Journal Data

Use the output command `ExportJournalCommand` or run:

```bash
# Get the exact command from stack outputs
aws cloudformation describe-stacks \
  --stack-name QLDBFinancialLedgerStack \
  --query 'Stacks[0].Outputs[?OutputKey==`ExportJournalCommand`].OutputValue' \
  --output text
```

### 4. Generate Cryptographic Digest

```bash
# Get ledger name from outputs
LEDGER_NAME=$(aws cloudformation describe-stacks \
  --stack-name QLDBFinancialLedgerStack \
  --query 'Stacks[0].Outputs[?OutputKey==`LedgerName`].OutputValue' \
  --output text)

# Generate digest
aws qldb get-digest --name $LEDGER_NAME
```

## Resource Details

### QLDB Ledger Configuration

- **Permissions Mode**: STANDARD (for production workloads)
- **Deletion Protection**: Enabled by default
- **Encryption**: AWS managed KMS keys
- **Tags**: Environment, Application, Project metadata

### S3 Bucket Security

- **Encryption**: SSE-S3 server-side encryption
- **Public Access**: Completely blocked
- **Versioning**: Enabled for data protection
- **Lifecycle Policy**: Automatic cleanup after 90 days
- **SSL Enforcement**: Required for all requests

### Kinesis Stream Configuration

- **Encryption**: AWS managed encryption at rest
- **Retention**: 7 days for journal data
- **Shard Count**: Configurable (default: 1)
- **Aggregation**: Enabled for optimized throughput

### IAM Role Permissions

The QLDB service role has minimal required permissions:

- **S3 Access**: PutObject, GetObject, ListBucket on export bucket only
- **Kinesis Access**: PutRecord, PutRecords, DescribeStream on journal stream only
- **CloudWatch Logs**: CreateLogGroup, CreateLogStream, PutLogEvents for monitoring

## Monitoring and Troubleshooting

### CloudWatch Logs

Monitor QLDB operations in the created log group:

```bash
# Get log group name
LOG_GROUP=$(aws cloudformation describe-stacks \
  --stack-name QLDBFinancialLedgerStack \
  --query 'Stacks[0].Outputs[?OutputKey==`LogGroupName`].OutputValue' \
  --output text)

# View recent logs
aws logs tail $LOG_GROUP --follow
```

### Verify Resource Creation

```bash
# Check QLDB ledger status
aws qldb describe-ledger --name $LEDGER_NAME

# Check S3 bucket
aws s3 ls s3://$(aws cloudformation describe-stacks \
  --stack-name QLDBFinancialLedgerStack \
  --query 'Stacks[0].Outputs[?OutputKey==`ExportBucketName`].OutputValue' \
  --output text)

# Check Kinesis stream
aws kinesis describe-stream --stream-name $(aws cloudformation describe-stacks \
  --stack-name QLDBFinancialLedgerStack \
  --query 'Stacks[0].Outputs[?OutputKey==`JournalStreamName`].OutputValue' \
  --output text)
```

### Common Issues and Solutions

1. **Permission Denied Errors**:
   - Ensure your AWS credentials have the required permissions
   - Check that the CDK execution role has necessary permissions

2. **Resource Name Conflicts**:
   - The stack uses a unique suffix to avoid naming conflicts
   - If conflicts occur, try deploying to a different region or account

3. **Deletion Protection**:
   - To delete the stack, first disable deletion protection on the QLDB ledger
   - Run: `aws qldb update-ledger --name $LEDGER_NAME --no-deletion-protection`

## Cost Optimization

### QLDB Pricing Considerations

- **I/O Requests**: Charged per million requests
- **Storage**: Charged per GB-month
- **Journal Streaming**: Additional charges for Kinesis usage

### Cost Management Tips

1. **Monitor Usage**: Use AWS Cost Explorer to track QLDB costs
2. **Optimize Queries**: Use indexes efficiently to reduce I/O requests
3. **Lifecycle Policies**: S3 bucket includes automatic cleanup after 90 days
4. **Stream Management**: Stop journal streaming when not needed for development

## Security Best Practices

### Data Protection

- All data is encrypted at rest using AWS managed keys
- In-transit encryption for all API communications
- No public access to any storage resources

### Access Control

- IAM roles follow least privilege principle
- Service-to-service authentication only
- No embedded credentials in code or configuration

### Compliance Features

- Immutable transaction records for audit trails
- Cryptographic verification of data integrity
- Complete history preservation for regulatory compliance

## Development and Testing

### Local Development

```bash
# Compile TypeScript
npm run build

# Watch mode for development
npm run watch

# Run tests
npm test
```

### Validate CloudFormation Template

```bash
# Generate CloudFormation template
cdk synth > template.yaml

# Validate template
aws cloudformation validate-template --template-body file://template.yaml
```

## Cleanup

### Disable Deletion Protection First

```bash
# Get ledger name
LEDGER_NAME=$(aws cloudformation describe-stacks \
  --stack-name QLDBFinancialLedgerStack \
  --query 'Stacks[0].Outputs[?OutputKey==`LedgerName`].OutputValue' \
  --output text)

# Disable deletion protection
aws qldb update-ledger --name $LEDGER_NAME --no-deletion-protection
```

### Delete the Stack

```bash
npm run destroy
```

Or using CDK directly:

```bash
cdk destroy
```

### Verify Cleanup

```bash
# Confirm all resources are deleted
aws cloudformation describe-stacks --stack-name QLDBFinancialLedgerStack
```

## Integration Examples

### Programmatic Access

```typescript
import { QLDBSession } from 'amazon-qldb-driver-nodejs';

const qldbDriver = new QLDBSession({
    region: 'us-east-1',
    ledgerName: 'financial-ledger-xyz123'
});

// Execute PartiQL queries
await qldbDriver.executeLambda(async (txn) => {
    await txn.execute('CREATE TABLE Accounts');
    await txn.execute('CREATE INDEX ON Accounts (accountId)');
});
```

### Real-time Processing

```typescript
import { KinesisClient, GetRecordsCommand } from '@aws-sdk/client-kinesis';

const kinesis = new KinesisClient({ region: 'us-east-1' });

// Process journal records from Kinesis stream
const records = await kinesis.send(new GetRecordsCommand({
    ShardIterator: shardIterator
}));

records.Records?.forEach(record => {
    const journalBlock = JSON.parse(record.Data.toString());
    // Process QLDB journal data
});
```

## Support and Documentation

- **AWS QLDB Documentation**: [QLDB Developer Guide](https://docs.aws.amazon.com/qldb/latest/developerguide/)
- **CDK Documentation**: [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/)
- **Recipe Documentation**: See the main recipe markdown file for detailed implementation guidance

## Contributing

When modifying this CDK application:

1. Follow TypeScript best practices
2. Update this README for any configuration changes
3. Test thoroughly in a development environment
4. Ensure all resources follow AWS security best practices
5. Update cost estimates if resource configurations change

## License

This code is provided under the Apache 2.0 License. See the LICENSE file for details.