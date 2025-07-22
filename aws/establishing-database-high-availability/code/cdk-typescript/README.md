# Multi-AZ Database Deployments CDK TypeScript Application

This CDK TypeScript application deploys a highly available Multi-AZ Aurora PostgreSQL database cluster following AWS best practices for enterprise-grade database deployments.

## Architecture Overview

The application creates:

- **Aurora PostgreSQL Cluster**: Multi-AZ deployment with 1 writer and 2 reader instances
- **Security Group**: Network access controls for database connections
- **Parameter Group**: Optimized database configuration for high availability
- **Secrets Manager**: Secure credential storage
- **CloudWatch Monitoring**: Comprehensive performance monitoring and alerting
- **Systems Manager Parameters**: Centralized connection string management
- **Enhanced Monitoring**: Detailed instance-level metrics

## Prerequisites

- **AWS Account**: With appropriate permissions for RDS, VPC, IAM, CloudWatch, and Systems Manager
- **AWS CLI**: Version 2.x installed and configured
- **Node.js**: Version 18 or later
- **AWS CDK**: Version 2.100.0 or later
- **TypeScript**: Version 5.2 or later

### Required AWS Permissions

Your AWS credentials must have permissions for:
- RDS cluster and instance management
- VPC and security group operations
- IAM role creation and management
- Secrets Manager operations
- Systems Manager Parameter Store
- CloudWatch metrics and dashboard creation

## Installation

1. **Clone and Navigate to the Project**:
   ```bash
   cd aws/multi-az-database-deployments-high-availability/code/cdk-typescript/
   ```

2. **Install Dependencies**:
   ```bash
   npm install
   ```

3. **Bootstrap CDK (if not already done)**:
   ```bash
   cdk bootstrap
   ```

## Configuration

### Environment Variables

Set your AWS region (optional, defaults to configured region):
```bash
export AWS_DEFAULT_REGION=us-east-1
```

### Customization

You can customize the deployment by modifying the following parameters in `lib/multi-az-database-stack.ts`:

- **Instance Type**: Change `ec2.InstanceSize.LARGE` to desired size
- **Instance Count**: Modify the `instances` parameter (minimum 3 for Multi-AZ)
- **Engine Version**: Update `AuroraPostgresEngineVersion.VER_15_4`
- **Backup Retention**: Adjust `retention: cdk.Duration.days(14)`
- **Parameter Group Settings**: Modify the `parameters` object

## Deployment

### 1. Validate the Configuration

```bash
# Compile TypeScript and validate CDK code
npm run build

# Synthesize CloudFormation template
cdk synth
```

### 2. Review the Deployment Plan

```bash
# Show what resources will be created
cdk diff
```

### 3. Deploy the Stack

```bash
# Deploy with approval prompts for security changes
cdk deploy

# Or deploy without prompts (use with caution)
cdk deploy --require-approval never
```

The deployment typically takes 15-20 minutes to complete.

### 4. Verify Deployment

After deployment, verify the resources:

```bash
# Check cluster status
aws rds describe-db-clusters \
    --db-cluster-identifier <cluster-identifier> \
    --query 'DBClusters[0].Status'

# Check instance status
aws rds describe-db-instances \
    --query 'DBInstances[?DBClusterIdentifier==`<cluster-identifier>`].{Instance:DBInstanceIdentifier,Status:DBInstanceStatus}'
```

## Post-Deployment Configuration

### 1. Retrieve Database Credentials

```bash
# Get the secret ARN from CloudFormation outputs
SECRET_ARN=$(aws cloudformation describe-stacks \
    --stack-name MultiAzDatabaseStack \
    --query 'Stacks[0].Outputs[?OutputKey==`DatabaseCredentialsSecretArn`].OutputValue' \
    --output text)

# Retrieve credentials
aws secretsmanager get-secret-value \
    --secret-id $SECRET_ARN \
    --query 'SecretString' --output text
```

### 2. Get Connection Endpoints

```bash
# Writer endpoint
aws ssm get-parameter \
    --name "/rds/multiaz/<cluster-identifier>/writer-endpoint" \
    --query 'Parameter.Value' --output text

# Reader endpoint
aws ssm get-parameter \
    --name "/rds/multiaz/<cluster-identifier>/reader-endpoint" \
    --query 'Parameter.Value' --output text
```

### 3. Test Database Connectivity

```bash
# Install PostgreSQL client (Amazon Linux 2)
sudo yum install -y postgresql15

# Connect to the database
psql -h <writer-endpoint> -U dbadmin -d testdb
```

## Monitoring and Observability

### CloudWatch Dashboard

Access the automatically created monitoring dashboard:
1. Open the CloudWatch console
2. Navigate to Dashboards
3. Select the dashboard named `<cluster-identifier>-monitoring`

### Key Metrics to Monitor

- **CPU Utilization**: Should typically stay below 80%
- **Database Connections**: Monitor connection pool usage
- **Freeable Memory**: Ensure adequate memory for operations
- **Read/Write IOPS**: Track I/O performance

### Alarms

The stack creates two CloudWatch alarms:
- **High Connections**: Triggers at 80 connections
- **High CPU**: Triggers at 80% CPU utilization for 15 minutes

## Failover Testing

Test the Multi-AZ failover capability:

```bash
# Trigger manual failover
aws rds failover-db-cluster \
    --db-cluster-identifier <cluster-identifier>

# Monitor failover progress
aws rds describe-db-clusters \
    --db-cluster-identifier <cluster-identifier> \
    --query 'DBClusters[0].Status'
```

Typical failover time is under 35 seconds.

## Security Best Practices

The deployment implements several security measures:

- **Encryption at Rest**: All data is encrypted using AWS managed keys
- **Network Isolation**: Database accessible only from within VPC
- **Secrets Management**: Credentials stored in AWS Secrets Manager
- **Enhanced Monitoring**: Detailed logging and monitoring enabled
- **Deletion Protection**: Prevents accidental cluster deletion

## Cost Optimization

To optimize costs:

1. **Right-size Instances**: Start with smaller instances and scale as needed
2. **Reserved Instances**: Purchase RIs for predictable workloads
3. **Automated Snapshots**: Adjust retention period based on requirements
4. **Development/Testing**: Use smaller instance types for non-production

Estimated monthly cost: $600-1200 (varies by region and instance size)

## Troubleshooting

### Common Issues

1. **VPC Not Found Error**:
   ```bash
   # Ensure you have a default VPC or modify the stack to create one
   aws ec2 describe-vpcs --filters "Name=is-default,Values=true"
   ```

2. **Insufficient Permissions**:
   ```bash
   # Verify IAM permissions for RDS, VPC, and CloudWatch
   aws sts get-caller-identity
   ```

3. **Deployment Timeout**:
   ```bash
   # RDS cluster creation can take 15-20 minutes
   # Monitor progress in CloudFormation console
   ```

### Logs and Debugging

- **CDK Debug**: Add `--debug` flag to CDK commands
- **CloudFormation Events**: Monitor stack events in AWS console
- **RDS Logs**: Access PostgreSQL logs via CloudWatch Logs

## Cleanup

To avoid ongoing charges, destroy the stack when no longer needed:

```bash
# Disable deletion protection first (if needed)
aws rds modify-db-cluster \
    --db-cluster-identifier <cluster-identifier> \
    --no-deletion-protection

# Destroy the CDK stack
cdk destroy

# Confirm deletion when prompted
```

**Warning**: This will permanently delete all data. Ensure you have backups if needed.

## Advanced Configuration

### Custom Parameter Groups

Modify the parameter group in `lib/multi-az-database-stack.ts`:

```typescript
parameters: {
  'shared_preload_libraries': 'pg_stat_statements,pg_hint_plan',
  'max_connections': '200',
  'work_mem': '4MB',
  // Add more parameters as needed
}
```

### Cross-Region Read Replicas

To add cross-region read replicas, extend the stack:

```typescript
// Add to the stack
const crossRegionReplica = cluster.addRotationMultiUser('CrossRegionReplica', {
  // Configuration for cross-region replica
});
```

### Performance Insights

Performance Insights is enabled by default. Access it via:
1. RDS Console
2. Select your cluster
3. Click "Performance Insights" tab

## Support and Resources

- [AWS RDS Aurora Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/)
- [Aurora PostgreSQL Best Practices](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/AuroraPostgreSQL.BestPractices.html)
- [Multi-AZ DB Clusters](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/multi-az-db-clusters-concepts.html)

## Contributing

To contribute improvements to this CDK application:

1. Fork the repository
2. Create a feature branch
3. Make changes and test thoroughly
4. Submit a pull request with detailed description

## License

This project is licensed under the MIT License. See the LICENSE file for details.