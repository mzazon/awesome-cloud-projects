# Database Migration Oracle to PostgreSQL - CDK TypeScript

This CDK TypeScript application deploys the complete infrastructure for migrating Oracle databases to PostgreSQL using AWS Database Migration Service (DMS) and Aurora PostgreSQL.

## Architecture

The solution includes:

- **VPC with Multi-AZ Subnets**: Secure network isolation with public, private, and database subnets
- **Aurora PostgreSQL Cluster**: Managed PostgreSQL database optimized for migration workloads
- **DMS Replication Instance**: Compute engine for data migration tasks
- **DMS Endpoints**: Source (Oracle) and target (PostgreSQL) connection configurations
- **IAM Roles**: Secure service permissions for DMS operations
- **Secrets Manager**: Encrypted storage for database credentials
- **CloudWatch Monitoring**: Alarms for replication lag and task failures
- **SNS Notifications**: Alert system for migration monitoring

## Prerequisites

Before deploying this stack, ensure you have:

1. **AWS CLI v2** installed and configured with appropriate permissions
2. **Node.js 18+** and **npm** installed
3. **AWS CDK v2** installed globally: `npm install -g aws-cdk`
4. **Oracle database** accessible with migration privileges
5. **DMS service roles** may require pre-creation in some accounts

### Required AWS Permissions

Your AWS credentials need the following permissions:
- DMS: Full access to create replication instances, endpoints, and tasks
- RDS: Full access to create Aurora clusters and instances
- EC2: VPC, subnet, and security group management
- IAM: Role and policy creation for DMS services
- Secrets Manager: Secret creation and management
- CloudWatch: Alarm and metric creation
- SNS: Topic creation and management

## Installation and Deployment

### 1. Install Dependencies

```bash
cd aws/database-migration-oracle-postgresql/code/cdk-typescript/
npm install
```

### 2. Configure Environment Variables

Set the required environment variables for your deployment:

```bash
# AWS Account and Region (required)
export CDK_DEFAULT_ACCOUNT="123456789012"
export CDK_DEFAULT_REGION="us-east-1"

# Project Configuration (optional - will use defaults)
export PROJECT_NAME="oracle-to-postgresql"
export ENVIRONMENT="dev"

# Oracle Database Configuration (required)
export ORACLE_SERVER_NAME="your-oracle-server.example.com"
export ORACLE_USERNAME="oracle_user"
export ORACLE_DATABASE_NAME="ORCL"
```

### 3. Bootstrap CDK (if not done previously)

```bash
cdk bootstrap aws://$CDK_DEFAULT_ACCOUNT/$CDK_DEFAULT_REGION
```

### 4. Deploy the Stack

```bash
# Preview the deployment
cdk diff

# Deploy the infrastructure
cdk deploy

# Deploy with custom parameters
cdk deploy --parameters projectName=myproject --parameters environment=prod
```

## Post-Deployment Configuration

After the stack deploys successfully, complete these configuration steps:

### 1. Update Oracle Database Credentials

```bash
# Get the Oracle secret ARN from stack outputs
ORACLE_SECRET_ARN=$(aws cloudformation describe-stacks \
    --stack-name DatabaseMigrationStack-dev \
    --query 'Stacks[0].Outputs[?OutputKey==`OracleSecretArn`].OutputValue' \
    --output text)

# Update the Oracle password in Secrets Manager
aws secretsmanager update-secret \
    --secret-id $ORACLE_SECRET_ARN \
    --secret-string '{"username":"oracle_user","password":"your_oracle_password"}'
```

### 2. Configure Oracle Database for CDC

Enable supplemental logging on your Oracle database:

```sql
-- Connect to Oracle as DBA
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (PRIMARY KEY) COLUMNS;
```

### 3. Test DMS Endpoint Connections

```bash
# Get replication instance ARN
REPLICATION_INSTANCE_ARN=$(aws cloudformation describe-stacks \
    --stack-name DatabaseMigrationStack-dev \
    --query 'Stacks[0].Outputs[?OutputKey==`ReplicationInstanceArn`].OutputValue' \
    --output text)

# Test Oracle source connection
aws dms test-connection \
    --replication-instance-arn $REPLICATION_INSTANCE_ARN \
    --endpoint-arn $(aws dms describe-endpoints \
        --filters Name=endpoint-type,Values=source \
        --query 'Endpoints[0].EndpointArn' --output text)

# Test PostgreSQL target connection
aws dms test-connection \
    --replication-instance-arn $REPLICATION_INSTANCE_ARN \
    --endpoint-arn $(aws dms describe-endpoints \
        --filters Name=endpoint-type,Values=target \
        --query 'Endpoints[0].EndpointArn' --output text)
```

### 4. Start Migration Task

```bash
# Get migration task ARN
MIGRATION_TASK_ARN=$(aws cloudformation describe-stacks \
    --stack-name DatabaseMigrationStack-dev \
    --query 'Stacks[0].Outputs[?OutputKey==`MigrationTaskArn`].OutputValue' \
    --output text)

# Start the migration task
aws dms start-replication-task \
    --replication-task-arn $MIGRATION_TASK_ARN \
    --start-replication-task-type start-replication
```

### 5. Monitor Migration Progress

```bash
# Check task status
aws dms describe-replication-tasks \
    --replication-task-arn $MIGRATION_TASK_ARN \
    --query 'ReplicationTasks[0].Status'

# View table statistics
aws dms describe-table-statistics \
    --replication-task-arn $MIGRATION_TASK_ARN \
    --query 'TableStatistics[*].[TableName,TableState,FullLoadRows,Inserts,Updates,Deletes]' \
    --output table
```

## Configuration Options

### Context Variables

You can customize the deployment using CDK context variables:

```bash
# Deploy with custom configuration
cdk deploy \
    --context projectName=myproject \
    --context environment=prod \
    --context oracleServerName=prod-oracle.company.com \
    --context oracleUsername=dba_user \
    --context oracleDatabaseName=PRODDB
```

### Table Mapping Customization

The default table mapping includes HR schema tables. To modify the migration scope, update the `tableMappings` object in `lib/database-migration-stack.ts`:

```typescript
const tableMappings = {
  rules: [
    {
      'rule-type': 'selection',
      'rule-id': '1',
      'rule-name': '1',
      'object-locator': {
        'schema-name': 'YOUR_SCHEMA',
        'table-name': '%',
      },
      'rule-action': 'include',
      filters: [],
    },
    // Add more rules as needed
  ],
};
```

## Monitoring and Troubleshooting

### CloudWatch Metrics

The stack creates CloudWatch alarms for:
- **Replication Lag**: Alerts when lag exceeds 5 minutes
- **Task Failures**: Immediate notification of migration failures

### Viewing Logs

```bash
# View DMS task logs
aws logs describe-log-groups \
    --log-group-name-prefix dms-tasks

# View Aurora PostgreSQL logs
aws logs describe-log-groups \
    --log-group-name-prefix /aws/rds/cluster/aurora-cluster
```

### Common Issues

1. **Connection Failures**: Verify security groups allow traffic on required ports (1521 for Oracle, 5432 for PostgreSQL)
2. **Replication Lag**: Check Oracle database load and network connectivity
3. **Schema Conversion**: Use AWS SCT for complex object conversion before migration

## Cost Optimization

To minimize costs during development and testing:

1. **Aurora Cluster**: Consider using smaller instance types (db.t3.medium)
2. **DMS Instance**: Start with smaller classes (dms.t3.micro for testing)
3. **Multi-AZ**: Disable for non-production environments
4. **Monitoring**: Reduce Performance Insights retention period

## Security Best Practices

1. **Secrets Management**: Never hardcode database passwords
2. **Network Security**: Use private subnets for database resources
3. **IAM Roles**: Follow principle of least privilege
4. **Encryption**: Enable encryption at rest and in transit
5. **Access Control**: Restrict console and API access to authorized users

## Cleanup

To avoid ongoing charges, destroy the stack when testing is complete:

```bash
# Stop migration task first
aws dms stop-replication-task --replication-task-arn $MIGRATION_TASK_ARN

# Destroy the infrastructure
cdk destroy

# Confirm destruction
y
```

**Warning**: This will permanently delete all resources including data in Aurora PostgreSQL. Ensure you have backups if needed.

## Additional Resources

- [AWS DMS User Guide](https://docs.aws.amazon.com/dms/latest/userguide/)
- [Aurora PostgreSQL Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.AuroraPostgreSQL.html)
- [Oracle to PostgreSQL Migration Playbook](https://docs.aws.amazon.com/dms/latest/oracle-to-aurora-postgresql-migration-playbook/)
- [AWS Schema Conversion Tool](https://docs.aws.amazon.com/SchemaConversionTool/latest/userguide/)

## Support

For issues related to this CDK application:
1. Check CloudFormation events in AWS Console
2. Review CloudWatch logs for detailed error messages
3. Verify all prerequisites are met
4. Consult AWS DMS troubleshooting documentation

For AWS service issues, contact AWS Support or post in AWS forums.