# Infrastructure as Code for Blockchain Audit Trails for Compliance

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Blockchain Audit Trails for Compliance".

## Overview

This solution creates a comprehensive blockchain-based audit trail system using Amazon QLDB for immutable ledger records, AWS CloudTrail for API activity logging, and EventBridge for real-time compliance monitoring. The architecture ensures cryptographic proof of data integrity, provides tamper-evident audit logs, and enables automated compliance reporting that meets SOX, PCI-DSS, and other regulatory requirements.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Components

The infrastructure deploys the following resources:

- **Amazon QLDB Ledger** - Immutable blockchain ledger for audit records
- **AWS CloudTrail** - API activity logging with log file validation
- **AWS Lambda** - Audit event processing function
- **Amazon EventBridge** - Real-time event routing and processing
- **Amazon S3** - Secure storage for audit logs and reports
- **Amazon Kinesis Data Firehose** - Streaming delivery for compliance data
- **Amazon Athena** - Serverless query engine for compliance analysis
- **Amazon CloudWatch** - Monitoring, dashboards, and alerting
- **Amazon SNS** - Notification system for compliance alerts
- **IAM Roles and Policies** - Secure access control

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- AWS account with permissions to create QLDB, CloudTrail, Lambda, EventBridge, S3, Kinesis, Athena, CloudWatch, SNS, and IAM resources
- For CDK implementations: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+
- Estimated cost: $25-50/month for development/testing environment

> **Important**: Amazon QLDB has been deprecated and will reach end-of-support on July 31, 2025. For production use, consider migrating to Amazon Aurora PostgreSQL with audit features as recommended by AWS.

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name blockchain-audit-trails \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters \
        ParameterKey=Environment,ParameterValue=development \
        ParameterKey=NotificationEmail,ParameterValue=your-email@example.com

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name blockchain-audit-trails

# Get outputs
aws cloudformation describe-stacks \
    --stack-name blockchain-audit-trails \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Set environment variables (optional)
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Bootstrap CDK (first time only)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy --parameters notificationEmail=your-email@example.com

# View outputs
npx cdk outputs
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set environment variables (optional)
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters notificationEmail=your-email@example.com

# View outputs
cdk outputs
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
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

# Follow the prompts and provide required parameters
```

## Configuration

### Environment Variables

All implementations support the following environment variables:

```bash
export AWS_REGION=us-east-1                    # AWS region for deployment
export ENVIRONMENT=development                 # Environment tag (development/staging/production)
export NOTIFICATION_EMAIL=your-email@example.com  # Email for compliance alerts
export LEDGER_NAME_PREFIX=compliance-audit     # Prefix for QLDB ledger name
export ENABLE_DELETION_PROTECTION=true         # Enable deletion protection for QLDB
```

### Parameters

Key parameters that can be customized:

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| Environment | Environment tag for resources | development | No |
| NotificationEmail | Email address for compliance alerts | - | Yes |
| LedgerNamePrefix | Prefix for QLDB ledger name | compliance-audit | No |
| EnableDeletionProtection | Enable deletion protection for QLDB | true | No |
| LogRetentionDays | CloudWatch log retention period | 30 | No |
| AuditDataRetentionDays | S3 audit data retention period | 2555 (7 years) | No |

## Validation & Testing

After deployment, validate the solution:

### 1. Verify QLDB Ledger

```bash
# Check ledger status
aws qldb describe-ledger --name compliance-audit-ledger-XXXXXX

# Verify encryption is enabled
aws qldb describe-ledger --name compliance-audit-ledger-XXXXXX \
    --query 'EncryptionDescription.EncryptionStatus'
```

### 2. Test CloudTrail Logging

```bash
# Check CloudTrail status
aws cloudtrail get-trail-status --name compliance-audit-trail-XXXXXX

# Verify recent events
aws cloudtrail lookup-events \
    --lookup-attributes AttributeKey=EventName,AttributeValue=CreateRole \
    --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%SZ)
```

### 3. Test Lambda Processing

```bash
# Invoke Lambda function with test event
aws lambda invoke \
    --function-name audit-processor-XXXXXX \
    --payload '{"detail":{"eventName":"TestEvent","eventSource":"test.service"}}' \
    /tmp/lambda-response.json

# Check function logs
aws logs tail /aws/lambda/audit-processor-XXXXXX --follow
```

### 4. Verify Compliance Dashboard

```bash
# Check CloudWatch dashboard
aws cloudwatch get-dashboard --dashboard-name ComplianceAuditDashboard

# View recent metrics
aws cloudwatch get-metric-statistics \
    --namespace ComplianceAudit \
    --metric-name AuditRecordsProcessed \
    --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --period 300 \
    --statistics Sum
```

## Monitoring and Alerting

The solution includes comprehensive monitoring:

### CloudWatch Dashboard

- Audit record processing metrics
- Lambda function performance
- Error rates and trends
- Recent audit processing logs

### CloudWatch Alarms

- Audit processing failures
- Lambda function errors
- QLDB ledger issues
- CloudTrail logging failures

### SNS Notifications

Email alerts are sent for:
- Audit processing failures
- Compliance violations
- System health issues
- Critical security events

## Security Features

### Data Protection

- **Encryption at Rest**: All data encrypted using AWS managed keys
- **Encryption in Transit**: TLS encryption for all data transfers
- **Immutable Storage**: QLDB provides tamper-evident audit trails
- **Access Control**: Least privilege IAM roles and policies

### Compliance Controls

- **Audit Trail Integrity**: Cryptographic verification of audit records
- **Log File Validation**: CloudTrail log file validation enabled
- **Retention Policies**: Configurable data retention for compliance
- **Access Logging**: Comprehensive logging of all system access

## Cost Optimization

### Resource Optimization

- **Serverless Architecture**: Pay-per-use Lambda and Athena
- **Intelligent Tiering**: S3 lifecycle policies for cost optimization
- **Right-sizing**: Appropriately sized resources for workload
- **Monitoring**: CloudWatch metrics to track usage and costs

### Estimated Costs (Monthly)

| Service | Development | Production |
|---------|-------------|------------|
| QLDB | $5-10 | $50-200 |
| Lambda | $1-5 | $10-50 |
| S3 | $2-5 | $20-100 |
| CloudTrail | $2-5 | $10-50 |
| Other Services | $5-15 | $25-100 |
| **Total** | **$15-40** | **$115-500** |

## Troubleshooting

### Common Issues

#### 1. QLDB Access Denied

```bash
# Check IAM permissions
aws iam get-role-policy \
    --role-name audit-processor-XXXXXX-role \
    --policy-name audit-processor-XXXXXX-policy
```

#### 2. Lambda Function Timeouts

```bash
# Check function configuration
aws lambda get-function-configuration \
    --function-name audit-processor-XXXXXX

# Increase timeout if needed
aws lambda update-function-configuration \
    --function-name audit-processor-XXXXXX \
    --timeout 120
```

#### 3. CloudTrail Not Logging

```bash
# Verify trail configuration
aws cloudtrail describe-trails \
    --trail-name-list compliance-audit-trail-XXXXXX

# Check S3 bucket policy
aws s3api get-bucket-policy \
    --bucket compliance-audit-bucket-XXXXXX
```

### Log Locations

- **Lambda Logs**: `/aws/lambda/audit-processor-XXXXXX`
- **CloudTrail Logs**: S3 bucket `compliance-audit-bucket-XXXXXX/cloudtrail-logs/`
- **Compliance Reports**: S3 bucket `compliance-audit-bucket-XXXXXX/compliance-reports/`

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name blockchain-audit-trails

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name blockchain-audit-trails
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
npx cdk destroy
```

### Using CDK Python

```bash
cd cdk-python/
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

> **Warning**: Cleanup will permanently delete all audit data. Ensure you have exported any required compliance reports before proceeding.

## Customization

### Extending the Solution

1. **Multi-Region Replication**: Deploy the stack in multiple regions for disaster recovery
2. **Advanced Analytics**: Add machine learning models for anomaly detection
3. **Integration**: Connect with existing SIEM or compliance tools
4. **Custom Reports**: Develop additional compliance report formats

### Modifying Resources

- Edit parameter values in `terraform.tfvars` (Terraform) or `cdk.context.json` (CDK)
- Update resource configurations in the respective implementation files
- Refer to AWS documentation for advanced configuration options

## Support and Documentation

### AWS Documentation

- [Amazon QLDB Developer Guide](https://docs.aws.amazon.com/qldb/latest/developerguide/)
- [AWS CloudTrail User Guide](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [Amazon EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)

### Compliance Resources

- [AWS Compliance Programs](https://aws.amazon.com/compliance/programs/)
- [AWS Security Best Practices](https://aws.amazon.com/architecture/security-identity-compliance/)
- [SOX Compliance on AWS](https://aws.amazon.com/compliance/sox/)
- [PCI DSS on AWS](https://aws.amazon.com/compliance/pci-dss-level-1-faqs/)

### Migration from QLDB

Since Amazon QLDB is deprecated, consider these alternatives:

- [Amazon Aurora PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.AuroraPostgreSQL.html) with audit features
- [Amazon DynamoDB](https://docs.aws.amazon.com/dynamodb/) with DynamoDB Streams for audit trails
- [Amazon OpenSearch Service](https://docs.aws.amazon.com/opensearch-service/) for searchable audit logs

For issues with this infrastructure code, refer to the original recipe documentation or open an issue in the repository.