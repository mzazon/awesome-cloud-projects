# Enterprise Oracle Database Connectivity with VPC Lattice and S3 - CDK Python

This directory contains the AWS CDK Python implementation for deploying enterprise-grade Oracle Database@AWS connectivity infrastructure with VPC Lattice, S3 backup, and Redshift analytics.

## Overview

This CDK application implements the complete infrastructure required for the "Enterprise Oracle Database Connectivity with VPC Lattice and S3" recipe, providing:

- **Secure S3 Backup Bucket**: Enterprise-grade bucket with versioning, encryption, and intelligent lifecycle policies
- **Amazon Redshift Analytics Cluster**: Encrypted data warehouse for Oracle data analytics with Zero-ETL integration
- **IAM Security**: Least-privilege roles with CDK NAG compliance validation
- **Comprehensive Monitoring**: CloudWatch dashboards and logging for operational excellence
- **Encryption at Rest and Transit**: KMS encryption for all sensitive data and communications
- **Secrets Management**: AWS Secrets Manager for secure credential handling

## Architecture Components

### Core Infrastructure
- **KMS Key**: Customer-managed encryption key for all services
- **S3 Bucket**: Backup storage with lifecycle transitions (Standard → IA → Glacier → Deep Archive)
- **Redshift Cluster**: Single-node analytics cluster with enterprise security
- **IAM Roles**: Service roles with minimal required permissions

### Monitoring & Security
- **CloudWatch Log Groups**: Centralized logging for Oracle operations
- **CloudWatch Dashboard**: Real-time metrics and monitoring widgets
- **Secrets Manager**: Secure storage for Redshift credentials
- **CDK NAG**: Security compliance validation with suppression documentation

## Prerequisites

Before deploying this CDK application, ensure you have:

1. **AWS CLI v2** installed and configured
2. **Node.js 18+** and **Python 3.8+** installed
3. **AWS CDK v2** installed globally: `npm install -g aws-cdk`
4. **Appropriate AWS permissions** for:
   - Oracle Database@AWS management
   - VPC Lattice operations
   - S3, Redshift, IAM, and KMS resources
   - CloudWatch and Secrets Manager
5. **CDK Bootstrap** completed in your target account/region

## Installation and Setup

### 1. Clone and Navigate to Directory

```bash
cd aws/enterprise-oracle-connectivity-lattice-s3/code/cdk-python/
```

### 2. Create Virtual Environment

```bash
# Create Python virtual environment
python3 -m venv .venv

# Activate virtual environment
# On macOS/Linux:
source .venv/bin/activate
# On Windows:
.venv\Scripts\activate
```

### 3. Install Dependencies

```bash
# Upgrade pip and install requirements
python -m pip install --upgrade pip
pip install -r requirements.txt
```

### 4. Bootstrap CDK (if not already done)

```bash
cdk bootstrap
```

## Configuration

### Environment Variables

Set the following environment variables to customize the deployment:

```bash
# Required: AWS account and region
export CDK_DEFAULT_ACCOUNT="123456789012"
export CDK_DEFAULT_REGION="us-east-1"

# Optional: Customize project settings
export PROJECT_NAME="oracle-enterprise"
export ENVIRONMENT_NAME="dev"
```

### CDK Context Parameters

You can also configure the deployment via CDK context in `cdk.json`:

```json
{
  "projectName": "oracle-enterprise",
  "environmentName": "production"
}
```

Or pass them via command line:

```bash
cdk deploy --context projectName=oracle-enterprise --context environmentName=prod
```

## Deployment

### 1. Synthesize CloudFormation Template

```bash
# Validate and generate CloudFormation templates
cdk synth

# Review the generated CloudFormation template
ls cdk.out/
```

### 2. Preview Changes

```bash
# See what will be deployed (if stack already exists)
cdk diff
```

### 3. Deploy Infrastructure

```bash
# Deploy the complete stack
cdk deploy

# Deploy with automatic approval (for CI/CD)
cdk deploy --require-approval never
```

The deployment will create resources in the following order:
1. KMS encryption key
2. IAM roles and policies
3. Secrets Manager secret for Redshift
4. S3 backup bucket with lifecycle policies
5. Redshift analytics cluster
6. CloudWatch monitoring resources

### 4. Verify Deployment

After successful deployment, verify the created resources:

```bash
# List CloudFormation stacks
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE

# Verify S3 bucket
aws s3 ls | grep oracle-enterprise-backup

# Check Redshift cluster
aws redshift describe-clusters --cluster-identifier oracle-analytics-*

# View CloudWatch dashboard
aws cloudwatch list-dashboards --dashboard-name-prefix OracleAWSIntegration
```

## Stack Outputs

The deployment provides these important outputs:

| Output | Description |
|--------|-------------|
| `S3BackupBucketName` | Name of the S3 bucket for Oracle backups |
| `S3BackupBucketArn` | ARN of the S3 backup bucket |
| `RedshiftClusterIdentifier` | Identifier of the Redshift analytics cluster |
| `RedshiftClusterEndpoint` | Endpoint for connecting to Redshift cluster |
| `RedshiftRoleArn` | IAM role ARN for Redshift cluster operations |
| `CloudWatchDashboardUrl` | Direct URL to CloudWatch monitoring dashboard |
| `SecretsManagerSecretArn` | ARN of the Redshift credentials secret |
| `KMSKeyId` | KMS key ID for encryption operations |

## Post-Deployment Configuration

After the CDK deployment completes, you'll need to configure Oracle Database@AWS integration:

### 1. Enable S3 Access for Oracle Database@AWS

```bash
# Get the S3 bucket name from stack outputs
S3_BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name oracle-enterprise-dev-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`S3BackupBucketName`].OutputValue' \
    --output text)

# Enable S3 access for your ODB network
aws odb update-odb-network \
    --odb-network-id ${ODB_NETWORK_ID} \
    --s3-access ENABLED
```

### 2. Configure S3 Access Policy

```bash
# Create S3 policy for Oracle Database access
cat > s3-oracle-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${S3_BUCKET_NAME}",
                "arn:aws:s3:::${S3_BUCKET_NAME}/*"
            ]
        }
    ]
}
EOF

# Apply the policy to ODB network
aws odb update-odb-network \
    --odb-network-id ${ODB_NETWORK_ID} \
    --s3-policy-document file://s3-oracle-policy.json
```

### 3. Enable Zero-ETL Integration

```bash
# Enable Zero-ETL access for Redshift integration
aws odb update-odb-network \
    --odb-network-id ${ODB_NETWORK_ID} \
    --zero-etl-access ENABLED
```

## CDK NAG Security Compliance

This CDK application includes CDK NAG for security best practices validation. The following suppressions are applied with justification:

| Rule | Suppression Reason |
|------|-------------------|
| `AwsSolutions-S3-1` | Server access logging not required for backup bucket as events are monitored via CloudWatch |
| `AwsSolutions-RS-1` | Redshift cluster encrypted with customer-managed KMS key |
| `AwsSolutions-RS-2` | Single node configuration acceptable for development/cost optimization |
| `AwsSolutions-IAM4` | AWS managed policies required for Redshift service operations |
| `AwsSolutions-IAM5` | Wildcard permissions necessary for Redshift cross-service access |

### Running Security Validation

```bash
# CDK NAG runs automatically during synth/deploy
cdk synth  # Will show CDK NAG findings

# Generate detailed security report
cdk synth --app "python app.py" --output cdk.out --verbose
```

## Monitoring and Operations

### CloudWatch Dashboard

Access the monitoring dashboard using the URL from stack outputs:

```bash
# Get dashboard URL
aws cloudformation describe-stacks \
    --stack-name oracle-enterprise-dev-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`CloudWatchDashboardUrl`].OutputValue' \
    --output text
```

The dashboard includes:
- S3 bucket request metrics
- Redshift cluster CPU and connection metrics
- Oracle backup event counters
- Storage utilization trends

### Log Monitoring

```bash
# View Oracle operation logs
aws logs describe-log-groups --log-group-name-prefix "/aws/oracle-database"

# Stream real-time logs
aws logs tail /aws/oracle-database/oracle-enterprise-dev --follow
```

### Accessing Redshift Credentials

```bash
# Retrieve Redshift credentials from Secrets Manager
SECRET_ARN=$(aws cloudformation describe-stacks \
    --stack-name oracle-enterprise-dev-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`SecretsManagerSecretArn`].OutputValue' \
    --output text)

aws secretsmanager get-secret-value --secret-id ${SECRET_ARN}
```

## Cost Optimization

This deployment includes several cost optimization features:

### S3 Lifecycle Management
- Day 0-30: Standard storage
- Day 30-90: Infrequent Access (IA)
- Day 90-365: Glacier storage
- Day 365+: Deep Archive storage

### Redshift Optimization
- Single-node cluster for development workloads
- Pause/resume capability (manual)
- Performance monitoring for right-sizing

### Resource Tagging
All resources are tagged for cost allocation:
- `Project`: oracle-enterprise
- `Environment`: dev/prod
- `Purpose`: Oracle Database Integration

## Troubleshooting

### Common Issues

1. **CDK Bootstrap Required**
   ```
   Error: Need to perform AWS CDK bootstrap
   Solution: Run `cdk bootstrap` before deployment
   ```

2. **Insufficient Permissions**
   ```
   Error: Access denied for IAM/KMS operations
   Solution: Ensure your AWS credentials have appropriate permissions
   ```

3. **Region Availability**
   ```
   Error: Oracle Database@AWS not available in region
   Solution: Deploy to a supported region (us-east-1, us-west-2, etc.)
   ```

4. **Resource Limits**
   ```
   Error: Service limit exceeded
   Solution: Request service limit increases via AWS Support
   ```

### Debugging CDK Issues

```bash
# Enable verbose CDK logging
cdk synth --verbose

# Check CDK version compatibility
cdk --version
npm list -g aws-cdk

# Validate Python dependencies
pip check
```

## Cleanup

To avoid ongoing AWS charges, destroy the stack when no longer needed:

```bash
# Destroy all resources
cdk destroy

# Force destroy without confirmation (use carefully)
cdk destroy --force
```

**Note**: Some resources may need manual cleanup:
- S3 bucket objects (if `auto_delete_objects=False`)
- CloudWatch logs (based on retention settings)
- Secrets Manager secrets (recovery period applies)

## Development and Testing

### Running Tests

```bash
# Install development dependencies
pip install -r requirements.txt

# Run unit tests
python -m pytest tests/ -v

# Run with coverage
python -m pytest tests/ --cov=. --cov-report=html
```

### Code Quality

```bash
# Format code
black app.py

# Lint code
flake8 app.py

# Type checking
mypy app.py

# Security scanning
bandit -r .
```

### Customization

To customize this CDK application for your environment:

1. **Modify Resource Names**: Update the `unique_id` generation or use custom naming
2. **Adjust Instance Sizes**: Change Redshift node types based on workload requirements
3. **Enhance Monitoring**: Add custom CloudWatch alarms and SNS notifications
4. **Security Hardening**: Implement additional security groups and NACLs as needed

## Additional Resources

- [AWS CDK Python Reference](https://docs.aws.amazon.com/cdk/api/v2/python/)
- [Oracle Database@AWS Documentation](https://docs.aws.amazon.com/odb/)
- [VPC Lattice User Guide](https://docs.aws.amazon.com/vpc-lattice/)
- [CDK NAG Rules Reference](https://github.com/cdklabs/cdk-nag)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)

## Support

For issues with this CDK implementation:
1. Check the troubleshooting section above
2. Review AWS CDK documentation
3. Consult the original recipe documentation
4. Open an issue with detailed error messages and stack traces