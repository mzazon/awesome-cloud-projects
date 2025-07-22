# Data Encryption at Rest and in Transit - CDK Python Implementation

This AWS CDK Python application implements comprehensive data encryption strategies for protecting sensitive data both at rest and in transit.

## Overview

The application creates a complete encryption architecture using:

- **AWS KMS**: Customer-managed key for centralized encryption key management
- **Amazon S3**: Encrypted bucket with server-side encryption using KMS
- **Amazon RDS**: Encrypted MySQL database with performance insights
- **Amazon EC2**: Instance with encrypted EBS volumes
- **AWS Secrets Manager**: Encrypted credential storage
- **AWS CloudTrail**: Audit logging for encryption events
- **AWS Certificate Manager**: SSL/TLS certificate management (optional)
- **Amazon VPC**: Secure network foundation with flow logs

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                                 AWS Cloud                                       │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────────┐│
│  │                            VPC (10.0.0.0/16)                               ││
│  │                                                                             ││
│  │  ┌─────────────────────┐                    ┌─────────────────────┐        ││
│  │  │    Public Subnet    │                    │   Private Subnet    │        ││
│  │  │                     │                    │                     │        ││
│  │  │  ┌───────────────┐  │                    │  ┌───────────────┐  │        ││
│  │  │  │ EC2 Instance  │  │                    │  │ RDS Database  │  │        ││
│  │  │  │ (Encrypted    │  │                    │  │ (Encrypted)   │  │        ││
│  │  │  │  EBS Volume)  │  │                    │  │               │  │        ││
│  │  │  └───────────────┘  │                    │  └───────────────┘  │        ││
│  │  │                     │                    │                     │        ││
│  │  └─────────────────────┘                    └─────────────────────┘        ││
│  │                                                                             ││
│  └─────────────────────────────────────────────────────────────────────────────┘│
│                                                                                 │
│  ┌─────────────────────┐    ┌─────────────────────┐    ┌──────────────────────┐ │
│  │   S3 Bucket        │    │   Secrets Manager   │    │   CloudTrail         │ │
│  │   (SSE-KMS)        │    │   (KMS Encrypted)   │    │   (KMS Encrypted)    │ │
│  └─────────────────────┘    └─────────────────────┘    └──────────────────────┘ │
│                                                                                 │
│  ┌─────────────────────┐    ┌─────────────────────┐    ┌──────────────────────┐ │
│  │   KMS Key          │    │   Certificate       │    │   CloudWatch Logs    │ │
│  │   (Customer        │    │   Manager (ACM)     │    │   (Encrypted)        │ │
│  │   Managed)         │    │   (Optional)        │    │                      │ │
│  └─────────────────────┘    └─────────────────────┘    └──────────────────────┘ │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

Before deploying this CDK application, ensure you have:

1. **AWS CLI** installed and configured with appropriate credentials
2. **AWS CDK** installed (`npm install -g aws-cdk`)
3. **Python 3.8+** installed
4. **pip** package manager
5. **Virtual environment** (recommended)

### Required AWS Permissions

Your AWS credentials need permissions for:
- KMS (create keys, manage policies)
- S3 (create buckets, configure encryption)
- RDS (create instances, configure encryption)
- EC2 (create instances, manage security groups)
- VPC (create VPC, subnets, security groups)
- Secrets Manager (create secrets)
- CloudTrail (create trails)
- Certificate Manager (request certificates)
- CloudWatch Logs (create log groups)
- IAM (create roles and policies)

## Installation

1. **Clone the repository** (if not already cloned):
   ```bash
   git clone <repository-url>
   cd aws/data-encryption-rest-transit/code/cdk-python
   ```

2. **Create a virtual environment**:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Bootstrap CDK** (if not already done):
   ```bash
   cdk bootstrap
   ```

## Deployment

### Basic Deployment

Deploy the stack with default configuration:

```bash
cdk deploy
```

### Deployment with Custom Domain

To include SSL/TLS certificate for a custom domain:

```bash
cdk deploy -c domain_name=example.com
```

### Deployment with Custom Account/Region

```bash
cdk deploy -c account=123456789012 -c region=us-east-1
```

### Deployment Options

Before deployment, you can:

1. **Synthesize CloudFormation template**:
   ```bash
   cdk synth
   ```

2. **View differences**:
   ```bash
   cdk diff
   ```

3. **Deploy with approval**:
   ```bash
   cdk deploy --require-approval=any-change
   ```

## Post-Deployment

After successful deployment, the CDK will output important resource information:

- **KMS Key ID**: For additional encryption operations
- **S3 Bucket Name**: For storing encrypted data
- **RDS Endpoint**: For database connections
- **EC2 Instance ID**: For compute operations
- **VPC ID**: For network configuration
- **Secret ARN**: For retrieving database credentials

### Accessing Resources

1. **Connect to EC2 Instance**:
   ```bash
   # Get the key pair from AWS Console or use SSM Session Manager
   aws ssm start-session --target <instance-id>
   ```

2. **Access Database**:
   ```bash
   # Retrieve database credentials from Secrets Manager
   aws secretsmanager get-secret-value --secret-id <secret-arn>
   ```

3. **Upload encrypted data to S3**:
   ```bash
   aws s3 cp file.txt s3://<bucket-name>/
   ```

## Security Features

### Encryption at Rest

- **KMS Key**: Customer-managed key with automatic rotation
- **S3 Bucket**: Server-side encryption with KMS (SSE-KMS)
- **RDS Database**: Encrypted storage, backups, and snapshots
- **EBS Volumes**: Encrypted using customer-managed KMS key
- **Secrets Manager**: Encrypted credential storage
- **CloudTrail**: Encrypted log files

### Encryption in Transit

- **TLS/SSL**: Certificate Manager for HTTPS endpoints
- **VPC**: Secure network communication
- **RDS**: SSL/TLS connections to database
- **S3**: HTTPS-only access policy

### Access Control

- **IAM Roles**: Least privilege access
- **Security Groups**: Network-level firewalls
- **VPC**: Network isolation
- **KMS Policies**: Fine-grained key access control

## Monitoring and Compliance

### Audit Logging

- **CloudTrail**: Comprehensive API call logging
- **VPC Flow Logs**: Network traffic monitoring
- **CloudWatch Logs**: Application and system logs
- **RDS Performance Insights**: Database monitoring

### Compliance Features

- **HIPAA**: Encryption and audit logging
- **PCI DSS**: Secure data handling
- **SOC 2**: Comprehensive security controls
- **GDPR**: Data protection and privacy

## Cost Optimization

### Resource Sizing

- **EC2**: t3.micro instances (eligible for free tier)
- **RDS**: db.t3.micro instances (eligible for free tier)
- **S3**: Intelligent tiering for cost optimization
- **KMS**: Bucket keys to reduce API calls

### Cost Monitoring

Monitor costs using:
- AWS Cost Explorer
- AWS Budgets
- CloudWatch billing alarms

## Testing

### Unit Tests

Run unit tests:
```bash
python -m pytest tests/
```

### Integration Tests

Test encryption functionality:
```bash
# Test S3 encryption
aws s3api head-object --bucket <bucket-name> --key <object-key>

# Test RDS encryption
aws rds describe-db-instances --db-instance-identifier <instance-id>

# Test KMS key usage
aws kms generate-data-key --key-id <key-id> --key-spec AES_256
```

## Troubleshooting

### Common Issues

1. **KMS Key Access Denied**:
   - Check IAM permissions
   - Verify key policy
   - Ensure correct region

2. **RDS Connection Issues**:
   - Check security group rules
   - Verify VPC configuration
   - Confirm database status

3. **S3 Access Denied**:
   - Verify bucket policy
   - Check IAM permissions
   - Confirm encryption configuration

### Debug Commands

```bash
# Check CDK version
cdk --version

# List stacks
cdk list

# View stack resources
aws cloudformation describe-stack-resources --stack-name DataEncryptionStack

# Check CloudTrail logs
aws logs filter-log-events --log-group-name <cloudtrail-log-group>
```

## Cleanup

To avoid ongoing charges, destroy the stack when no longer needed:

```bash
cdk destroy
```

**Warning**: This will delete all resources including data stored in S3 and RDS. Ensure you have backups if needed.

### Manual Cleanup

Some resources may require manual cleanup:

1. **KMS Keys**: Scheduled for deletion (7-day waiting period)
2. **S3 Buckets**: May need to be emptied first
3. **RDS Snapshots**: Review and delete if not needed
4. **CloudWatch Logs**: Consider retention policies

## Development

### Code Structure

```
cdk-python/
├── app.py                  # Main CDK application
├── requirements.txt        # Python dependencies
├── setup.py               # Package configuration
├── cdk.json               # CDK configuration
├── .gitignore             # Git ignore rules
├── README.md              # This file
└── tests/                 # Unit tests (optional)
```

### Best Practices

1. **Security**: Always use least privilege IAM policies
2. **Monitoring**: Enable comprehensive logging and monitoring
3. **Testing**: Test encryption configurations before production
4. **Documentation**: Keep architecture documentation updated
5. **Compliance**: Regular security audits and compliance checks

## Resources

- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [AWS KMS Best Practices](https://docs.aws.amazon.com/kms/latest/developerguide/best-practices.html)
- [AWS S3 Encryption](https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingEncryption.html)
- [AWS RDS Encryption](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Overview.Encryption.html)
- [AWS Security Best Practices](https://aws.amazon.com/architecture/security-identity-compliance/)

## Support

For issues related to this CDK application:

1. Check the troubleshooting section
2. Review AWS CloudFormation events
3. Check AWS service documentation
4. Contact AWS Support for service-specific issues

## License

This project is licensed under the MIT License. See the LICENSE file for details.