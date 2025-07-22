# AWS CDK Python Application - Database Migration with DMS and Schema Conversion Tool

This AWS CDK Python application creates a complete infrastructure solution for database migration using AWS Database Migration Service (DMS) and supports integration with the AWS Schema Conversion Tool (SCT).

## Architecture Overview

The application deploys the following components:

- **VPC Infrastructure**: Multi-AZ VPC with public and private subnets
- **DMS Replication Instance**: Compute resource for performing database migration tasks
- **Target RDS Database**: PostgreSQL database as the migration destination
- **Security Groups**: Least-privilege security configurations
- **IAM Roles**: Service roles for DMS operations
- **CloudWatch Monitoring**: Comprehensive monitoring and logging
- **DMS Endpoints**: Source and target database connection configurations

## Features

- **Complete Infrastructure**: All resources needed for database migration
- **Security Best Practices**: Least privilege access, private subnets, encrypted storage
- **Monitoring**: CloudWatch dashboard and logging for migration visibility
- **Scalability**: Configurable instance sizes and storage options
- **Multi-AZ Support**: High availability across multiple availability zones
- **Secrets Management**: Secure credential handling with AWS Secrets Manager

## Prerequisites

Before deploying this application, ensure you have:

1. **AWS CLI** installed and configured with appropriate credentials
2. **AWS CDK** installed (`npm install -g aws-cdk`)
3. **Python 3.8+** installed
4. **pip** package manager
5. **Appropriate AWS permissions** for creating VPC, DMS, RDS, and IAM resources

## Installation

1. **Clone or download the application files**

2. **Create a virtual environment** (recommended):
   ```bash
   python3 -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Bootstrap CDK** (if first time using CDK in this region):
   ```bash
   cdk bootstrap
   ```

## Configuration

### Environment Variables

Configure your source database connection by setting these environment variables:

```bash
export SOURCE_DB_ENGINE="oracle"                    # oracle, sqlserver, mysql, etc.
export SOURCE_DB_HOST="your-source-db-host"        # Source database hostname
export SOURCE_DB_PORT="1521"                       # Source database port
export SOURCE_DB_USERNAME="your-username"          # Source database username
export SOURCE_DB_PASSWORD="your-password"          # Source database password
export SOURCE_DB_DATABASE="your-database"          # Source database name
export CDK_DEFAULT_ACCOUNT="123456789012"          # Your AWS account ID
export CDK_DEFAULT_REGION="us-east-1"              # Your preferred AWS region
```

### Using .env file

Alternatively, create a `.env` file in the project root:

```bash
# .env file
SOURCE_DB_ENGINE=oracle
SOURCE_DB_HOST=your-source-db-host
SOURCE_DB_PORT=1521
SOURCE_DB_USERNAME=your-username
SOURCE_DB_PASSWORD=your-password
SOURCE_DB_DATABASE=your-database
CDK_DEFAULT_ACCOUNT=123456789012
CDK_DEFAULT_REGION=us-east-1
```

## Deployment

### Deploy the Stack

```bash
# Synthesize the CloudFormation template (optional)
cdk synth

# Deploy the infrastructure
cdk deploy

# Deploy with approval for security changes
cdk deploy --require-approval never
```

### Monitor Deployment

The deployment process will:

1. Create VPC and networking components
2. Set up security groups and IAM roles
3. Deploy the target RDS PostgreSQL database
4. Create DMS replication instance and subnet group
5. Configure DMS endpoints for source and target databases
6. Set up CloudWatch monitoring dashboard

## Post-Deployment Steps

After successful deployment:

1. **Test Database Connectivity**:
   ```bash
   aws dms test-connection \
       --replication-instance-identifier dms-migration-instance \
       --endpoint-identifier source-database-endpoint
   ```

2. **Create Migration Tasks**:
   ```bash
   aws dms create-replication-task \
       --replication-task-identifier migration-task \
       --source-endpoint-identifier source-database-endpoint \
       --target-endpoint-identifier target-database-endpoint \
       --replication-instance-identifier dms-migration-instance \
       --migration-type full-load \
       --table-mappings file://table-mappings.json
   ```

3. **Monitor Progress**:
   - View CloudWatch dashboard for real-time metrics
   - Check DMS console for task progress
   - Review CloudWatch logs for detailed information

## Schema Conversion Tool Integration

This infrastructure supports AWS Schema Conversion Tool (SCT) integration:

1. **Download SCT**: Install AWS Schema Conversion Tool locally
2. **Connect to Databases**: Use the deployed endpoints to connect SCT
3. **Generate Assessment Report**: Analyze schema conversion requirements
4. **Apply Schema Changes**: Convert and apply schemas to target database

## Customization

### Modify Instance Sizes

Edit `app.py` to change instance configurations:

```python
# Change DMS replication instance size
replication_instance_class="dms.t3.large"  # Default: dms.t3.medium

# Change RDS instance size
instance_type=ec2.InstanceType.of(
    ec2.InstanceClass.BURSTABLE3, 
    ec2.InstanceSize.LARGE  # Default: MEDIUM
)
```

### Add Additional Monitoring

Extend the CloudWatch dashboard with custom metrics:

```python
# Add custom metrics to the dashboard
custom_widget = cloudwatch.GraphWidget(
    title="Custom Migration Metrics",
    left=[
        cloudwatch.Metric(
            namespace="AWS/DMS",
            metric_name="FreeStorageSpace",
            dimensions_map={"ReplicationInstanceIdentifier": instance_id}
        )
    ]
)
```

## Security Considerations

- **Network Security**: RDS database is deployed in private subnets
- **Encryption**: All data is encrypted at rest and in transit
- **Access Control**: IAM roles follow least privilege principle
- **Secrets Management**: Database credentials stored in AWS Secrets Manager
- **Security Groups**: Restrictive ingress/egress rules

## Costs

Estimated monthly costs for typical usage:

- **DMS Replication Instance (t3.medium)**: ~$75/month
- **RDS PostgreSQL (db.t3.medium)**: ~$50/month
- **VPC and Data Transfer**: ~$10/month
- **CloudWatch Logs and Monitoring**: ~$15/month

**Total Estimated Cost**: ~$150/month (varies by region and usage)

## Troubleshooting

### Common Issues

1. **VPC Limit Exceeded**:
   - Check VPC limits in your AWS account
   - Request limit increase if needed

2. **IAM Permission Errors**:
   - Ensure your AWS credentials have necessary permissions
   - Check IAM roles are properly configured

3. **Database Connection Issues**:
   - Verify security group rules
   - Check source database accessibility
   - Validate endpoint configurations

### Debugging Commands

```bash
# Check stack status
cdk ls

# View stack events
aws cloudformation describe-stack-events --stack-name DatabaseMigrationStack

# Check DMS replication instance
aws dms describe-replication-instances

# Test endpoint connectivity
aws dms test-connection --replication-instance-identifier dms-migration-instance --endpoint-identifier target-database-endpoint
```

## Cleanup

To avoid ongoing charges, destroy the infrastructure when migration is complete:

```bash
# Destroy all resources
cdk destroy

# Confirm destruction
cdk destroy --force
```

**Important**: This will delete all resources including the target database. Ensure you have backups if needed.

## Support

For issues and questions:

- **AWS DMS Documentation**: https://docs.aws.amazon.com/dms/
- **AWS CDK Documentation**: https://docs.aws.amazon.com/cdk/
- **Schema Conversion Tool**: https://docs.aws.amazon.com/SchemaConversionTool/
- **AWS Support**: Contact AWS Support for production issues

## License

This project is licensed under the Apache License 2.0. See the LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## Changelog

### Version 1.0.0
- Initial release with complete DMS infrastructure
- PostgreSQL target database support
- CloudWatch monitoring dashboard
- Security best practices implementation
- Comprehensive documentation