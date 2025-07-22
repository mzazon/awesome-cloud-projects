# High-Availability PostgreSQL Clusters with Amazon RDS - CDK Python

This CDK Python application creates a production-grade high-availability PostgreSQL cluster using Amazon RDS with comprehensive monitoring, disaster recovery, and security features.

## Architecture Overview

The CDK application deploys:

- **Primary PostgreSQL Instance**: Multi-AZ deployment with automatic failover
- **Read Replica**: For horizontal scaling and additional redundancy
- **Cross-Region Replica**: For disaster recovery (requires manual configuration)
- **RDS Proxy**: Connection pooling and enhanced security
- **CloudWatch Monitoring**: Comprehensive alarms and metrics
- **SNS Notifications**: Real-time alerts for database events
- **Secrets Manager**: Secure credential management
- **Automated Backups**: 35-day retention with cross-region replication support

## Prerequisites

Before deploying this CDK application, ensure you have:

1. **AWS CLI** installed and configured with appropriate credentials
2. **Python 3.8+** installed on your system
3. **AWS CDK v2** installed globally (`npm install -g aws-cdk`)
4. **Appropriate IAM permissions** for:
   - RDS instance creation and management
   - VPC and security group management
   - IAM role creation
   - CloudWatch alarms and SNS topics
   - Secrets Manager access
   - Cross-region resource creation (for disaster recovery)

## Installation and Setup

1. **Clone or download** this CDK application to your local machine

2. **Create a Python virtual environment**:
   ```bash
   python -m venv .venv
   ```

3. **Activate the virtual environment**:
   
   On macOS/Linux:
   ```bash
   source .venv/bin/activate
   ```
   
   On Windows:
   ```bash
   .venv\Scripts\activate
   ```

4. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

5. **Bootstrap CDK** (if not already done):
   ```bash
   cdk bootstrap
   ```

## Configuration

### Environment Variables

You can configure the deployment using environment variables:

```bash
export NOTIFICATION_EMAIL="your-email@example.com"
export CLUSTER_NAME="my-postgresql-cluster"
export INSTANCE_CLASS="db.r6g.large"
export CDK_DEFAULT_REGION="us-east-1"
export CDK_DEFAULT_ACCOUNT="123456789012"
```

### CDK Context Parameters

Alternatively, you can use CDK context parameters in `cdk.json` or pass them via command line:

```bash
cdk deploy --context notification_email=your-email@example.com \
           --context cluster_name=my-postgresql-cluster \
           --context instance_class=db.r6g.xlarge
```

### Configuration Options

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `notification_email` | Email address for SNS notifications | `admin@example.com` | Yes |
| `cluster_name` | Custom cluster name (auto-generated if not provided) | `None` | No |
| `instance_class` | RDS instance class | `db.r6g.large` | No |

## Deployment

### Quick Deployment

1. **Set your notification email**:
   ```bash
   export NOTIFICATION_EMAIL="your-email@example.com"
   ```

2. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

3. **Confirm the deployment** when prompted

### Advanced Deployment Options

1. **Deploy with custom parameters**:
   ```bash
   cdk deploy --context notification_email=admin@company.com \
              --context cluster_name=production-postgres \
              --context instance_class=db.r6g.xlarge
   ```

2. **Review changes before deployment**:
   ```bash
   cdk diff
   ```

3. **Deploy with approval prompts disabled**:
   ```bash
   cdk deploy --require-approval never
   ```

## Post-Deployment Configuration

### 1. Confirm SNS Subscription

After deployment, check your email for an SNS subscription confirmation and click the confirmation link.

### 2. Retrieve Database Credentials

Get the database credentials from AWS Secrets Manager:

```bash
aws secretsmanager get-secret-value \
    --secret-id $(aws cloudformation describe-stacks \
        --stack-name PostgreSQLHAStack \
        --query 'Stacks[0].Outputs[?OutputKey==`DatabaseSecret`].OutputValue' \
        --output text) \
    --query 'SecretString' --output text
```

### 3. Connect to the Database

Use the primary endpoint for write operations:

```bash
# Get the primary endpoint
PRIMARY_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name PostgreSQLHAStack \
    --query 'Stacks[0].Outputs[?OutputKey==`PrimaryEndpoint`].OutputValue' \
    --output text)

# Connect using psql
psql -h $PRIMARY_ENDPOINT -U dbadmin -d productiondb
```

Use the read replica endpoint for read-only operations:

```bash
# Get the read replica endpoint
READ_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name PostgreSQLHAStack \
    --query 'Stacks[0].Outputs[?OutputKey==`ReadReplicaEndpoint`].OutputValue' \
    --output text)

# Connect to read replica
psql -h $READ_ENDPOINT -U dbadmin -d productiondb
```

### 4. Use RDS Proxy for Connection Pooling

For applications requiring connection pooling:

```bash
# Get the proxy endpoint
PROXY_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name PostgreSQLHAStack \
    --query 'Stacks[0].Outputs[?OutputKey==`ProxyEndpoint`].OutputValue' \
    --output text)

# Connect through RDS Proxy
psql -h $PROXY_ENDPOINT -U dbadmin -d productiondb
```

## Monitoring and Alerts

The deployment includes comprehensive monitoring:

### CloudWatch Alarms

- **CPU Utilization**: Alerts when CPU usage exceeds 80%
- **Database Connections**: Alerts when connection count exceeds 150
- **Read Replica Lag**: Alerts when replication lag exceeds 30 seconds
- **Storage Space**: Alerts when free storage drops below 20GB

### SNS Notifications

All alarms and RDS events are sent to the configured email address, including:

- Instance availability changes
- Backup and restore operations
- Failover events
- Maintenance notifications
- Performance issues

### Performance Insights

Both primary and replica instances have Performance Insights enabled for detailed query-level monitoring.

## Disaster Recovery

### Cross-Region Setup

For complete disaster recovery, deploy a cross-region stack:

1. **Set the DR region**:
   ```bash
   export CDK_DEFAULT_REGION="us-west-2"
   ```

2. **Deploy DR stack** (requires manual configuration for cross-region replicas)

3. **Enable automated backup replication**:
   ```bash
   aws rds start-db-instance-automated-backups-replication \
       --source-db-instance-arn "arn:aws:rds:us-east-1:ACCOUNT:db:INSTANCE-ID" \
       --backup-retention-period 35 \
       --region us-west-2
   ```

### Failover Testing

Test the Multi-AZ failover capability:

```bash
# Force a failover to test the standby instance
aws rds reboot-db-instance \
    --db-instance-identifier your-cluster-name-primary \
    --force-failover
```

## Security Features

### Encryption

- **Encryption at Rest**: All storage is encrypted using AWS KMS
- **Encryption in Transit**: TLS is required for all connections
- **Backup Encryption**: All automated and manual backups are encrypted

### Access Control

- **Security Groups**: Restrict database access to VPC only
- **IAM Integration**: RDS Proxy uses IAM for enhanced security
- **Secrets Manager**: Database credentials are securely managed

### Network Security

- **Private Subnets**: Database instances are deployed in private subnets
- **VPC Isolation**: No public accessibility enabled
- **Security Group Rules**: Minimal required access permissions

## Cost Optimization

### Instance Sizing

The default configuration uses `db.r6g.large` instances. For cost optimization:

- **Development/Testing**: Use `db.t3.medium` or `db.t3.large`
- **Production**: Use `db.r6g.large` or larger based on workload requirements

### Storage Optimization

- **GP3 Storage**: Optimized for cost and performance
- **Auto Scaling**: Storage automatically scales up to 1TB
- **Backup Retention**: 35 days (adjust based on compliance requirements)

### Reserved Instances

For production workloads, consider purchasing RDS Reserved Instances for significant cost savings.

## Troubleshooting

### Common Issues

1. **Deployment Fails Due to Insufficient Permissions**:
   - Ensure your AWS credentials have the required IAM permissions
   - Check the CloudFormation events for specific error messages

2. **Email Notifications Not Working**:
   - Confirm the SNS subscription in your email
   - Check the email address in the deployment parameters

3. **Cannot Connect to Database**:
   - Verify security group rules allow access from your location
   - Ensure you're using the correct endpoint and credentials
   - Check that the database instance is in "available" status

4. **Cross-Region Replica Issues**:
   - Verify that both regions support the same PostgreSQL version
   - Ensure proper IAM permissions for cross-region operations
   - Check network connectivity between regions

### Debugging Commands

```bash
# Check stack status
cdk diff

# View CloudFormation events
aws cloudformation describe-stack-events --stack-name PostgreSQLHAStack

# Check RDS instance status
aws rds describe-db-instances --db-instance-identifier your-cluster-name-primary

# View CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix "/aws/rds/instance"
```

## Cleanup

To avoid ongoing charges, clean up the resources when no longer needed:

1. **Disable deletion protection** (if needed):
   ```bash
   aws rds modify-db-instance \
       --db-instance-identifier your-cluster-name-primary \
       --no-deletion-protection \
       --apply-immediately
   ```

2. **Destroy the stack**:
   ```bash
   cdk destroy
   ```

3. **Confirm deletion** when prompted

> **Warning**: This will permanently delete all data. Ensure you have appropriate backups before proceeding.

## Advanced Configuration

### Custom VPC

To use a custom VPC instead of the default VPC, modify the `_create_or_get_vpc` method in `app.py`:

```python
def _create_or_get_vpc(self) -> ec2.IVpc:
    """Create a custom VPC for the database cluster."""
    return ec2.Vpc(
        self,
        "PostgreSQLVPC",
        max_azs=3,
        nat_gateways=2,
        subnet_configuration=[
            ec2.SubnetConfiguration(
                name="PublicSubnet",
                subnet_type=ec2.SubnetType.PUBLIC,
                cidr_mask=24,
            ),
            ec2.SubnetConfiguration(
                name="PrivateSubnet",
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                cidr_mask=24,
            ),
            ec2.SubnetConfiguration(
                name="DatabaseSubnet",
                subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                cidr_mask=24,
            ),
        ],
    )
```

### Additional Parameter Tuning

Customize PostgreSQL parameters by modifying the `_create_parameter_group` method:

```python
parameters={
    "log_statement": "all",
    "log_min_duration_statement": "1000",
    "shared_preload_libraries": "pg_stat_statements,pg_hint_plan",
    "max_connections": "500",
    "shared_buffers": "25% of RAM",
    "effective_cache_size": "75% of RAM",
    # Add more parameters as needed
}
```

## Support and Documentation

- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Amazon RDS Documentation](https://docs.aws.amazon.com/rds/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [AWS RDS Best Practices](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_BestPractices.html)

## License

This code is provided under the MIT License. See LICENSE file for details.