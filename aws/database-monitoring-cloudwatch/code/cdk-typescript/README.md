# Database Monitoring with CloudWatch - CDK TypeScript

This CDK TypeScript application creates a comprehensive database monitoring solution with CloudWatch dashboards and alarms for Amazon RDS MySQL instances.

## Architecture

The solution deploys:

- **VPC**: Private isolated subnets across 2 availability zones
- **RDS MySQL Instance**: With enhanced monitoring and Performance Insights
- **CloudWatch Dashboard**: Real-time visualization of database metrics
- **CloudWatch Alarms**: Automated monitoring with SNS notifications
- **SNS Topic**: Email notifications for database alerts
- **IAM Role**: Enhanced monitoring permissions for RDS

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18+ installed
- npm or yarn package manager
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Valid email address for receiving alerts

## Quick Start

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Set required environment variables**:
   ```bash
   export ALERT_EMAIL="your-email@example.com"
   export ENVIRONMENT="development"  # Optional, defaults to development
   ```

3. **Bootstrap CDK** (if first time using CDK in this account/region):
   ```bash
   cdk bootstrap
   ```

4. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

5. **Confirm email subscription**:
   - Check your email inbox for SNS subscription confirmation
   - Click the confirmation link to receive database alerts

## Configuration Options

You can customize the deployment using CDK context parameters:

```bash
# Deploy with custom configuration
cdk deploy \
  --context alertEmail=admin@company.com \
  --context environment=production \
  --context databaseInstanceClass=db.t3.small \
  --context databaseAllocatedStorage=50 \
  --context cpuAlarmThreshold=70 \
  --context connectionsAlarmThreshold=80
```

### Available Context Parameters

| Parameter | Description | Default | Values |
|-----------|-------------|---------|---------|
| `alertEmail` | Email for alerts | Required | Valid email address |
| `environment` | Environment name | `development` | `development`, `staging`, `production` |
| `databaseInstanceClass` | RDS instance type | `db.t3.micro` | `db.t3.micro`, `db.t3.small`, etc. |
| `databaseAllocatedStorage` | Storage in GB | `20` | `20-100` |
| `databaseName` | Initial database name | `monitoringdemo` | Alphanumeric string |
| `databaseUsername` | Master username | `admin` | Alphanumeric string |
| `monitoringInterval` | Enhanced monitoring interval (seconds) | `60` | `0`, `1`, `5`, `10`, `15`, `30`, `60` |
| `performanceInsightsRetentionPeriod` | Performance Insights retention (days) | `7` | `7`, `731` |
| `cpuAlarmThreshold` | CPU alarm threshold (%) | `80` | `1-100` |
| `connectionsAlarmThreshold` | Connection count threshold | `50` | `1-1000` |
| `freeStorageSpaceThreshold` | Storage threshold (bytes) | `2147483648` | Bytes |

## Environment-Specific Features

### Development Environment
- Single AZ deployment
- Basic monitoring configuration
- No deletion protection

### Production Environment
- Multi-AZ deployment
- Additional latency alarms
- Deletion protection enabled
- Enhanced monitoring

## Monitoring Features

### CloudWatch Dashboard Widgets

1. **Database Performance Overview**
   - CPU Utilization with alarm threshold annotation
   - Database Connections
   - Freeable Memory

2. **Storage and Latency Metrics**
   - Free Storage Space
   - Read/Write Latency

3. **I/O Operations Per Second**
   - Read IOPS
   - Write IOPS

4. **I/O Throughput**
   - Read Throughput (Bytes/Second)
   - Write Throughput (Bytes/Second)

5. **Additional Database Metrics**
   - Binary Log Disk Usage
   - Swap Usage

### CloudWatch Alarms

- **CPU Utilization**: Triggers when CPU > threshold for 2 periods
- **Database Connections**: Triggers when connections > threshold for 2 periods
- **Free Storage Space**: Triggers when storage < threshold for 1 period
- **Read Latency** (Production only): Triggers when latency > 200ms for 3 periods
- **Write Latency** (Production only): Triggers when latency > 200ms for 3 periods

## Database Connection

After deployment, you can connect to the database using the credentials stored in AWS Secrets Manager:

```bash
# Get the database endpoint from outputs
aws cloudformation describe-stacks \
  --stack-name DatabaseMonitoringStack \
  --query 'Stacks[0].Outputs[?OutputKey==`DatabaseEndpoint`].OutputValue' \
  --output text

# Get the database credentials
aws secretsmanager get-secret-value \
  --secret-id DatabaseMonitoringStack/database/credentials \
  --query SecretString --output text | jq -r .password
```

## Testing the Monitoring

1. **Access the Dashboard**:
   - Use the CloudWatch Dashboard URL from the stack outputs
   - Monitor real-time database metrics

2. **Generate Test Load**:
   ```bash
   # Connect to the database and run sample queries
   mysql -h <database-endpoint> -u admin -p<password> \
     -e "SELECT SLEEP(30); SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES;"
   ```

3. **Test Alarms**:
   - The above query should generate CPU activity
   - Check email for alarm notifications

## Cost Estimation

- **RDS db.t3.micro**: ~$15-25/month
- **Enhanced Monitoring**: ~$2.50/month (if enabled)
- **Performance Insights**: Free for 7 days retention
- **CloudWatch**: $0.30 per alarm + dashboard costs
- **SNS**: $0.50 per million requests

## Cleanup

To remove all resources and avoid charges:

```bash
cdk destroy
```

**Note**: The database will be permanently deleted. Ensure you have backups if needed.

## Useful CDK Commands

- `npm run build`: Compile TypeScript to JS
- `npm run watch`: Watch for changes and compile
- `cdk diff`: Compare deployed stack with current state
- `cdk synth`: Emit the synthesized CloudFormation template
- `cdk deploy`: Deploy this stack to your default AWS account/region
- `cdk destroy`: Remove the stack from your AWS account

## Troubleshooting

### Common Issues

1. **Email not received**: Check spam folder and confirm SNS subscription
2. **Database connection issues**: Verify security group rules and VPC configuration
3. **Performance Insights not available**: Only supported on certain instance types
4. **Enhanced monitoring not working**: Verify IAM role permissions

### Debug Commands

```bash
# Check stack events
aws cloudformation describe-stack-events --stack-name DatabaseMonitoringStack

# Check RDS instance status
aws rds describe-db-instances --db-instance-identifier <instance-id>

# List CloudWatch alarms
aws cloudwatch describe-alarms --alarm-name-prefix DatabaseMonitoringStack
```

## Security Considerations

- Database credentials are automatically generated and stored in Secrets Manager
- Database is deployed in private subnets with no public access
- Security groups restrict access to MySQL port (3306) from VPC only
- Storage encryption is enabled by default
- SNS topic uses KMS encryption

## Best Practices

1. **Monitor costs**: Review CloudWatch and RDS bills regularly
2. **Adjust thresholds**: Tune alarm thresholds based on your workload
3. **Regular backups**: Automated backups are enabled with 7-day retention
4. **Security updates**: Keep RDS engine version updated
5. **Access control**: Use IAM for fine-grained database access control

## Support

For issues with this CDK application:

1. Check the [AWS CDK documentation](https://docs.aws.amazon.com/cdk/)
2. Review [RDS monitoring best practices](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Monitoring.html)
3. Consult [CloudWatch documentation](https://docs.aws.amazon.com/cloudwatch/)

## License

This code is licensed under the MIT License. See the LICENSE file for details.