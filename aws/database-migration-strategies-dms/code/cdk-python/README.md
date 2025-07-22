# AWS CDK Python - Database Migration with DMS

This AWS CDK Python application implements a comprehensive database migration infrastructure using AWS Database Migration Service (DMS). The solution provides minimal downtime database migrations with full-load and change data capture (CDC) capabilities.

## Architecture Overview

The CDK application creates:

- **VPC Infrastructure**: Multi-AZ VPC with public, private, and database subnets
- **DMS Replication Instance**: Multi-AZ deployment for high availability
- **Source & Target Endpoints**: Configurable database connection endpoints
- **Migration Tasks**: Full-load-and-CDC task plus dedicated CDC task
- **Monitoring**: CloudWatch logs, alarms, and SNS notifications
- **Storage**: S3 bucket for migration logs and artifacts

## Prerequisites

### Software Requirements

- **Python 3.8+**: Required for AWS CDK Python
- **AWS CLI v2**: For authentication and deployment
- **AWS CDK v2**: Latest stable version (2.100.0+)
- **Node.js 16+**: Required by AWS CDK (even for Python projects)

### AWS Requirements

- AWS account with appropriate permissions
- AWS CLI configured with credentials
- IAM permissions for DMS, VPC, S3, CloudWatch, and SNS services

### Installation

1. **Clone or download this CDK application**

2. **Create a Python virtual environment**:
   ```bash
   python -m venv .venv
   
   # On Windows
   .venv\Scripts\activate
   
   # On macOS/Linux
   source .venv/bin/activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Install AWS CDK (if not already installed)**:
   ```bash
   npm install -g aws-cdk
   ```

5. **Verify CDK installation**:
   ```bash
   cdk --version
   ```

## Configuration

### Database Configuration

The application supports configurable source and target database settings through CDK context parameters in `cdk.json`:

```json
{
  "context": {
    "source_db_config": {
      "engine_name": "mysql",
      "server_name": "source-database.example.com",
      "port": 3306,
      "database_name": "production_db",
      "username": "migration_user",
      "password": "secure_password_123"
    },
    "target_db_config": {
      "engine_name": "mysql",
      "server_name": "target-rds.us-east-1.rds.amazonaws.com",
      "port": 3306,
      "database_name": "migrated_db",
      "username": "admin",
      "password": "target_password_456"
    }
  }
}
```

### Infrastructure Configuration

Additional configuration options:

- `replication_instance_class`: DMS instance size (default: `dms.t3.medium`)
- `enable_multi_az`: Enable Multi-AZ deployment (default: `true`)
- `allocated_storage`: Storage allocation in GB (default: `100`)
- `vpc_cidr`: VPC CIDR block (default: `10.0.0.0/16`)

### Environment Variables

You can also configure using environment variables:

```bash
export CDK_DEFAULT_ACCOUNT="123456789012"
export CDK_DEFAULT_REGION="us-east-1"
```

## Deployment

### 1. Bootstrap CDK (First Time Only)

```bash
cdk bootstrap aws://ACCOUNT-NUMBER/REGION
```

### 2. Synthesize CloudFormation

```bash
# Generate CloudFormation templates
cdk synth

# Review the generated templates
ls cdk.out/
```

### 3. Deploy the Stack

```bash
# Deploy with automatic approval
cdk deploy

# Deploy with manual approval for security changes
cdk deploy --require-approval broadening
```

### 4. Monitor Deployment

```bash
# Watch deployment progress
cdk deploy --progress events

# Check stack status
aws cloudformation describe-stacks --stack-name DatabaseMigrationDmsStack
```

## Usage

### Starting Migration Tasks

After deployment, you can start migration tasks using the AWS CLI:

```bash
# Get task ARNs from stack outputs
MIGRATION_TASK_ARN=$(aws cloudformation describe-stacks \
  --stack-name DatabaseMigrationDmsStack \
  --query 'Stacks[0].Outputs[?OutputKey==`MigrationTaskId`].OutputValue' \
  --output text)

# Start the full-load-and-cdc task
aws dms start-replication-task \
  --replication-task-arn $MIGRATION_TASK_ARN \
  --start-replication-task-type start-replication
```

### Monitoring Migration Progress

```bash
# Check task status
aws dms describe-replication-tasks \
  --replication-task-identifier migration-task-XXXXXXXX

# View table statistics
aws dms describe-table-statistics \
  --replication-task-arn $MIGRATION_TASK_ARN

# Monitor CloudWatch logs
aws logs describe-log-streams \
  --log-group-name /aws/dms/tasks/dms-replication-XXXXXXXX
```

### Testing Endpoints

```bash
# Test source endpoint connection
aws dms test-connection \
  --replication-instance-arn $REPLICATION_INSTANCE_ARN \
  --endpoint-arn $SOURCE_ENDPOINT_ARN

# Test target endpoint connection
aws dms test-connection \
  --replication-instance-arn $REPLICATION_INSTANCE_ARN \
  --endpoint-arn $TARGET_ENDPOINT_ARN
```

## Customization

### Custom Table Mappings

Edit the `table_mappings` configuration in `app.py` to customize which tables are migrated:

```python
table_mappings = {
    "rules": [
        {
            "rule-type": "selection",
            "rule-id": "1",
            "rule-name": "include-specific-schema",
            "object-locator": {
                "schema-name": "production",
                "table-name": "%"
            },
            "rule-action": "include"
        },
        {
            "rule-type": "selection",
            "rule-id": "2",
            "rule-name": "exclude-temp-tables",
            "object-locator": {
                "schema-name": "production",
                "table-name": "temp_%"
            },
            "rule-action": "exclude"
        }
    ]
}
```

### Custom Task Settings

Modify the `task_settings` in `app.py` to optimize for your specific use case:

```python
task_settings = {
    "FullLoadSettings": {
        "TargetTablePrepMode": "TRUNCATE_BEFORE_LOAD",  # or "DROP_AND_CREATE"
        "MaxFullLoadSubTasks": 16,  # Increase for parallel loading
        "CommitRate": 50000,  # Adjust based on target database capacity
    },
    "ValidationSettings": {
        "EnableValidation": True,
        "ValidationMode": "ROW_LEVEL",  # or "TABLE_LEVEL"
        "ThreadCount": 8,
    }
}
```

### Adding Security Features

To enhance security, consider adding:

1. **VPC Endpoints** for private AWS service communication
2. **Secrets Manager** for database credentials
3. **KMS encryption** for S3 and EBS volumes
4. **Security Groups** with specific port restrictions

## Security Best Practices

### Database Credentials

**Important**: The current configuration includes database passwords in plain text for demonstration purposes. For production deployments:

1. **Use AWS Secrets Manager**:
   ```python
   from aws_cdk import aws_secretsmanager as secrets
   
   db_secret = secrets.Secret(
       self, "DatabaseCredentials",
       description="Database credentials for DMS migration",
       generate_secret_string=secrets.SecretStringGenerator(
           secret_string_template='{"username": "admin"}',
           generate_string_key="password",
           exclude_characters=" %+~`#$&*()|[]{}:;<>?!'/\"\\",
       )
   )
   ```

2. **Reference secrets in endpoints**:
   ```python
   source_endpoint = dms.CfnEndpoint(
       # ... other properties
       username=db_secret.secret_value_from_json("username").unsafe_unwrap(),
       password=db_secret.secret_value_from_json("password").unsafe_unwrap(),
   )
   ```

### Network Security

- Enable VPC Flow Logs for network monitoring
- Use private subnets for database resources
- Implement Security Groups with least privilege access
- Consider VPC endpoints for AWS service communications

### Encryption

- Enable encryption at rest for S3 buckets (already implemented)
- Use encrypted EBS volumes for DMS replication instances
- Enable SSL/TLS for database connections when supported

## Troubleshooting

### Common Issues

1. **Insufficient IAM Permissions**:
   ```bash
   # Check CDK bootstrap stack
   aws cloudformation describe-stacks --stack-name CDKToolkit
   
   # Verify DMS service roles
   aws iam get-role --role-name dms-vpc-role
   aws iam get-role --role-name dms-cloudwatch-logs-role
   ```

2. **VPC Quota Limits**:
   ```bash
   # Check VPC limits
   aws ec2 describe-account-attributes --attribute-names supported-platforms
   aws service-quotas get-service-quota --service-code vpc --quota-code L-F678F1CE
   ```

3. **Database Connectivity**:
   ```bash
   # Test network connectivity
   aws dms describe-connections --endpoint-arn $SOURCE_ENDPOINT_ARN
   
   # Check endpoint status
   aws dms describe-endpoints --endpoint-identifier source-endpoint-XXXXXXXX
   ```

### Logging and Debugging

1. **Enable verbose CDK logging**:
   ```bash
   cdk deploy --verbose
   ```

2. **Check CloudWatch logs**:
   ```bash
   aws logs filter-log-events \
     --log-group-name /aws/dms/tasks/dms-replication-XXXXXXXX \
     --start-time $(date -d '1 hour ago' +%s)000
   ```

3. **Monitor CloudFormation events**:
   ```bash
   aws cloudformation describe-stack-events \
     --stack-name DatabaseMigrationDmsStack \
     --max-items 20
   ```

## Cost Optimization

### DMS Instance Sizing

- Start with `dms.t3.medium` for testing
- Scale up to `dms.r5.large` or higher for production workloads
- Consider `dms.c5` instances for CPU-intensive transformations

### Storage Optimization

- Monitor storage usage and adjust allocated storage
- Use S3 Intelligent Tiering for log storage
- Implement lifecycle policies for old migration logs

### Resource Cleanup

Regular cleanup of unused resources:

```bash
# Stop migration tasks when not in use
aws dms stop-replication-task --replication-task-arn $TASK_ARN

# Delete completed migration tasks
aws dms delete-replication-task --replication-task-arn $TASK_ARN

# Consider using smaller instance classes for development
```

## Development

### Code Structure

```
cdk-python/
├── app.py                 # Main CDK application
├── requirements.txt       # Python dependencies
├── setup.py              # Package configuration
├── cdk.json              # CDK configuration
├── README.md             # This file
└── .venv/                # Python virtual environment
```

### Testing

```bash
# Install development dependencies
pip install -r requirements.txt[dev]

# Run unit tests (if implemented)
python -m pytest tests/

# Type checking
mypy app.py

# Code formatting
black app.py

# Linting
flake8 app.py
```

### Contributing

1. Follow Python PEP 8 style guidelines
2. Add type hints to all functions
3. Include comprehensive docstrings
4. Test all changes before committing
5. Update documentation for new features

## Cleanup

To avoid ongoing AWS charges, destroy the stack when no longer needed:

```bash
# Stop all running tasks first
aws dms stop-replication-task --replication-task-arn $MIGRATION_TASK_ARN
aws dms stop-replication-task --replication-task-arn $CDC_TASK_ARN

# Destroy the CDK stack
cdk destroy

# Confirm destruction
aws cloudformation describe-stacks --stack-name DatabaseMigrationDmsStack
```

## Resources

### AWS Documentation

- [AWS DMS User Guide](https://docs.aws.amazon.com/dms/latest/userguide/)
- [AWS CDK Python Documentation](https://docs.aws.amazon.com/cdk/v2/guide/work-with-cdk-python.html)
- [DMS Best Practices](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_BestPractices.html)

### CDK Resources

- [AWS CDK API Reference](https://docs.aws.amazon.com/cdk/api/v2/)
- [CDK Patterns](https://cdkpatterns.com/)
- [AWS CDK Examples](https://github.com/aws-samples/aws-cdk-examples)

### Support

- [AWS Support](https://aws.amazon.com/support/)
- [AWS re:Post](https://repost.aws/)
- [CDK GitHub Issues](https://github.com/aws/aws-cdk/issues)

## License

This code is provided under the Apache License 2.0. See the LICENSE file for details.