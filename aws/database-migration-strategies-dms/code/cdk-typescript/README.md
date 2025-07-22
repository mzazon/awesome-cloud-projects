# AWS DMS Database Migration - CDK TypeScript Implementation

This CDK TypeScript application implements a comprehensive AWS Database Migration Service (DMS) solution for enterprise database migrations with minimal downtime. The infrastructure includes replication instances, source and target endpoints, migration tasks, and comprehensive monitoring.

## Architecture Overview

The solution creates:

- **DMS Replication Instance**: Multi-AZ deployment for high availability
- **Source Endpoint**: Configurable connection to source database
- **Target Endpoint**: Configurable connection to target database  
- **Migration Tasks**: Both full-load-and-cdc and cdc-only tasks
- **Monitoring**: CloudWatch logs, alarms, and SNS notifications
- **Security**: VPC security groups, IAM roles, and S3 encryption
- **Logging**: S3 bucket for DMS logs with lifecycle policies

## Prerequisites

- AWS CDK v2.136.0 or later
- Node.js 18.x or later
- AWS CLI configured with appropriate permissions
- TypeScript knowledge for customization

## Quick Start

### Installation

```bash
# Install dependencies
npm install

# Verify CDK installation
npx cdk --version
```

### Deployment

```bash
# Synthesize CloudFormation template
npm run synth

# Deploy the stack
npm run deploy

# View differences (optional)
npm run diff
```

### Configuration

The stack can be customized by modifying the instantiation in `app.ts`:

```typescript
const stack = new DatabaseMigrationStack(app, 'DatabaseMigrationStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  
  // Custom replication instance settings
  replicationInstanceClass: 'dms.r5.large',
  allocatedStorage: 200,
  multiAz: true,
  
  // Source database configuration
  sourceEndpointConfig: {
    engineName: 'postgresql',
    serverName: 'source-db.example.com',
    port: 5432,
    databaseName: 'sourcedb',
    username: 'source_user',
    password: 'secure_password',
    extraConnectionAttributes: 'heartbeatEnable=true'
  },
  
  // Target database configuration
  targetEndpointConfig: {
    engineName: 'postgresql',
    serverName: 'target-rds.aws.com',
    port: 5432,
    databaseName: 'targetdb',
    username: 'target_user',
    password: 'secure_password'
  }
});
```

## Features

### Security Best Practices

- **CDK Nag Integration**: Automated security compliance checking
- **S3 Encryption**: Server-side encryption for migration logs
- **VPC Security Groups**: Restricted database access within VPC
- **IAM Least Privilege**: Minimal permissions for DMS operations
- **SSL/TLS**: Required for endpoint connections

### High Availability

- **Multi-AZ Deployment**: Automatic failover for replication instance
- **CloudWatch Monitoring**: Real-time metrics and alerting
- **Error Handling**: Comprehensive error policies and recovery

### Monitoring & Observability

- **CloudWatch Logs**: Centralized logging for all DMS operations
- **Custom Alarms**: Migration failure and CDC latency monitoring
- **SNS Notifications**: Automated alerting for critical events
- **S3 Log Retention**: 90-day lifecycle with versioning

### Migration Capabilities

- **Full Load + CDC**: Complete data migration with ongoing replication
- **CDC Only**: Real-time change data capture for ongoing sync
- **Data Validation**: Row-level validation for data integrity
- **Table Mapping**: Flexible schema transformation rules

## Usage Examples

### Basic MySQL to RDS Migration

```typescript
const migrationStack = new DatabaseMigrationStack(app, 'MySQLMigration', {
  sourceEndpointConfig: {
    engineName: 'mysql',
    serverName: 'on-premise-mysql.company.com',
    port: 3306,
    databaseName: 'production',
    username: 'migration_user',
    password: process.env.SOURCE_DB_PASSWORD!,
    extraConnectionAttributes: 'initstmt=SET foreign_key_checks=0'
  },
  targetEndpointConfig: {
    engineName: 'mysql',
    serverName: 'prod-mysql.cluster-abc123.us-east-1.rds.amazonaws.com',
    port: 3306,
    databaseName: 'production',
    username: 'admin',
    password: process.env.TARGET_DB_PASSWORD!
  }
});
```

### PostgreSQL to Aurora Migration

```typescript
const postgresStack = new DatabaseMigrationStack(app, 'PostgreSQLMigration', {
  replicationInstanceClass: 'dms.r5.xlarge', // Larger instance for performance
  sourceEndpointConfig: {
    engineName: 'postgres',
    serverName: 'legacy-postgres.company.local',
    port: 5432,
    databaseName: 'legacy_app',
    username: 'postgres',
    password: process.env.SOURCE_DB_PASSWORD!,
    extraConnectionAttributes: 'heartbeatEnable=true;heartbeatFrequency=180'
  },
  targetEndpointConfig: {
    engineName: 'aurora-postgresql',
    serverName: 'aurora-cluster.cluster-xyz789.us-west-2.rds.amazonaws.com',
    port: 5432,
    databaseName: 'modern_app',
    username: 'postgres',
    password: process.env.TARGET_DB_PASSWORD!
  }
});
```

## Testing

```bash
# Run unit tests
npm test

# Run tests in watch mode
npm run test:watch

# Generate test coverage
npm test -- --coverage
```

## Operations

### Starting Migration Tasks

After deployment, use the AWS CLI or console to start migration tasks:

```bash
# Start the full load + CDC task
aws dms start-replication-task \
    --replication-task-arn <task-arn> \
    --start-replication-task-type start-replication

# Monitor progress
aws dms describe-replication-tasks \
    --replication-task-identifier <task-id>
```

### Monitoring

- **CloudWatch Dashboard**: Custom dashboard for DMS metrics
- **Log Insights**: Query migration logs for troubleshooting
- **SNS Alerts**: Subscribe to the alerting topic for notifications

### Troubleshooting

1. **Connection Issues**: Check VPC security groups and endpoint configurations
2. **Performance**: Monitor CloudWatch metrics and adjust instance class
3. **Data Validation**: Review validation reports in CloudWatch logs
4. **CDC Latency**: Check source database load and network connectivity

## Customization

### Adding Custom Table Mappings

Modify the `getTableMappingRules()` method in `database-migration-stack.ts`:

```typescript
private getTableMappingRules(): any {
  return {
    rules: [
      {
        'rule-type': 'selection',
        'rule-id': '1',
        'rule-name': 'include-specific-schema',
        'object-locator': {
          'schema-name': 'production',
          'table-name': '%'
        },
        'rule-action': 'include'
      },
      {
        'rule-type': 'transformation',
        'rule-id': '2',
        'rule-name': 'rename-tables',
        'rule-target': 'table',
        'object-locator': {
          'schema-name': 'production',
          'table-name': 'old_%'
        },
        'rule-action': 'rename',
        'value': 'new_${table-name}'
      }
    ]
  };
}
```

### Custom Task Settings

Modify the `getTaskSettings()` method for specific requirements:

```typescript
// Example: Increase parallel load threads for large datasets
FullLoadSettings: {
  TargetTablePrepMode: 'TRUNCATE_BEFORE_LOAD',
  MaxFullLoadSubTasks: 16,
  CommitRate: 50000
}
```

## Cost Optimization

- Use appropriate replication instance sizes based on workload
- Configure S3 lifecycle policies for log retention
- Monitor and stop CDC tasks when no longer needed
- Consider Reserved Instances for long-running migrations

## Security Considerations

- Store database passwords in AWS Secrets Manager
- Use VPC endpoints for private connectivity
- Enable encryption in transit for all endpoints
- Regular security reviews with CDK Nag

## Cleanup

```bash
# Stop all migration tasks before destroying
aws dms stop-replication-task --replication-task-arn <task-arn>

# Destroy the stack
npm run destroy
```

## Support

For issues with this CDK implementation:

1. Check AWS DMS documentation
2. Review CloudWatch logs for detailed error messages
3. Consult AWS DMS best practices guide
4. Open GitHub issues for code-related problems

## License

This code is licensed under the MIT-0 License. See the LICENSE file for details.