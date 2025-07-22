# Database Monitoring Dashboards with CloudWatch - CDK Python

This CDK Python application creates a comprehensive database monitoring solution using AWS CloudWatch, RDS, and SNS. The solution provides real-time visibility into database performance metrics and automated alerting for critical thresholds.

## Architecture

The application deploys the following AWS resources:

- **RDS MySQL Instance**: Database instance with enhanced monitoring and Performance Insights enabled
- **CloudWatch Dashboard**: Comprehensive dashboard displaying key database performance metrics
- **CloudWatch Alarms**: Automated alarms for CPU utilization, database connections, storage space, and read latency
- **SNS Topic**: Notification topic for database alerts
- **IAM Role**: Enhanced monitoring role for detailed OS-level metrics
- **Security Group**: Secure network access configuration for the database

## Features

### Monitoring Capabilities
- Real-time database performance metrics visualization
- Enhanced monitoring with OS-level metrics at 60-second intervals
- Performance Insights for query-level analysis
- Comprehensive I/O performance tracking

### Alerting System
- CPU utilization monitoring (threshold: 80%)
- Database connection count monitoring (threshold: 50 connections)
- Storage space monitoring (threshold: 2GB free space)
- Read latency monitoring (threshold: 200ms)
- Email notifications via SNS

### Dashboard Widgets
- **Database Performance Overview**: CPU utilization, database connections, and freeable memory
- **Storage and Latency Metrics**: Free storage space, read/write latency
- **I/O Performance Metrics**: Read/write IOPS and throughput

## Prerequisites

- Python 3.8 or later
- AWS CLI configured with appropriate permissions
- Node.js and npm (for AWS CDK CLI)
- AWS CDK v2 installed globally: `npm install -g aws-cdk`

### Required AWS Permissions

Your AWS credentials must have permissions to create and manage:
- RDS instances and security groups
- CloudWatch dashboards and alarms
- SNS topics and subscriptions
- IAM roles and policies
- EC2 VPC resources (for default VPC lookup)

## Installation

1. **Clone or download the application files**

2. **Install Python dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

3. **Install AWS CDK CLI** (if not already installed):
   ```bash
   npm install -g aws-cdk
   ```

4. **Bootstrap CDK** (if not already done for your account/region):
   ```bash
   cdk bootstrap
   ```

## Configuration

### Context Parameters

You can customize the deployment by setting context parameters in `cdk.json` or via command line:

- `db_instance_class`: RDS instance type (default: `db.t3.micro`)
- `alert_email`: Email address for notifications (default: `admin@example.com`)
- `monitoring_interval`: Enhanced monitoring interval in seconds (default: `60`)
- `account`: AWS account ID (optional, auto-detected)
- `region`: AWS region (optional, auto-detected)

### Example with Custom Parameters

```bash
# Deploy with custom instance class and email
cdk deploy -c db_instance_class=db.t3.small -c alert_email=your-email@company.com

# Deploy with custom monitoring interval
cdk deploy -c monitoring_interval=30 -c alert_email=dba-team@company.com
```

### Setting Parameters in cdk.json

Alternatively, add parameters to the `context` section in `cdk.json`:

```json
{
  "context": {
    "db_instance_class": "db.t3.small",
    "alert_email": "your-email@company.com",
    "monitoring_interval": "60"
  }
}
```

## Deployment

### Deploy the Stack

```bash
# Preview the deployment
cdk diff

# Deploy the stack
cdk deploy

# Deploy with approval prompt for security changes
cdk deploy --require-approval broadening
```

### Deployment Output

After successful deployment, the stack outputs include:

- **DatabaseInstanceIdentifier**: RDS instance identifier
- **DatabaseEndpoint**: Database connection endpoint
- **DatabasePort**: Database port (default: 3306)
- **DatabaseSecretArn**: ARN of the secret containing database credentials
- **SNSTopicArn**: SNS topic ARN for alerts
- **CloudWatchDashboardURL**: Direct link to the CloudWatch dashboard
- **MonitoringRoleArn**: IAM role ARN for enhanced monitoring

## Usage

### Accessing the Database

1. **Retrieve database credentials** from AWS Secrets Manager:
   ```bash
   aws secretsmanager get-secret-value \
       --secret-id <DatabaseSecretArn> \
       --query SecretString --output text
   ```

2. **Connect to the database**:
   ```bash
   mysql -h <DatabaseEndpoint> -u admin -p
   ```

### Viewing Monitoring Data

1. **Access the CloudWatch Dashboard** using the provided URL in the stack outputs
2. **View Performance Insights** in the RDS console for query-level analysis
3. **Monitor alarms** in the CloudWatch console

### Email Notifications

1. **Confirm your email subscription** by clicking the link in the confirmation email
2. **Configure additional subscribers** by adding them to the SNS topic
3. **Test notifications** by temporarily lowering alarm thresholds

## Cost Considerations

### Estimated Monthly Costs (us-east-1)

- **RDS db.t3.micro instance**: ~$12-15/month
- **Enhanced monitoring (60-second intervals)**: ~$2.50/month
- **Performance Insights (7-day retention)**: Free
- **CloudWatch dashboard**: First 3 dashboards free, then $3/month each
- **CloudWatch alarms**: First 10 alarms free, then $0.10/month each
- **SNS notifications**: First 1,000 email notifications free, then $2/100,000

**Total estimated cost**: ~$15-20/month for the complete monitoring solution

### Cost Optimization Tips

- Use `db.t3.micro` for development/testing (included in AWS Free Tier for new accounts)
- Consider 300-second monitoring intervals instead of 60-second for cost savings
- Use CloudWatch Logs Insights instead of Performance Insights for long-term retention

## Monitoring Best Practices

### Dashboard Customization
- Add custom metrics specific to your application
- Create separate dashboards for different environments
- Use CloudWatch annotations to mark deployment events

### Alarm Configuration
- Adjust thresholds based on your application's normal behavior
- Use composite alarms for complex alerting scenarios
- Implement escalation policies with multiple notification channels

### Security Considerations
- Restrict database security group rules in production
- Use VPC endpoints for private connectivity
- Enable encryption at rest and in transit
- Rotate database credentials regularly

## Troubleshooting

### Common Issues

1. **VPC Lookup Fails**:
   - Ensure you have a default VPC in your region
   - Or modify the code to create a new VPC

2. **Email Notifications Not Received**:
   - Check spam folder for confirmation email
   - Verify email address in SNS subscription
   - Confirm subscription is confirmed (not pending)

3. **Dashboard Shows No Data**:
   - Wait 5-10 minutes for metrics to appear
   - Generate database activity to create metrics
   - Check that enhanced monitoring is enabled

4. **RDS Instance Creation Fails**:
   - Verify you have sufficient RDS limits in your region
   - Check that the instance class is available in your region
   - Ensure proper IAM permissions

### Getting Help

- Check AWS CloudWatch documentation: https://docs.aws.amazon.com/cloudwatch/
- Review RDS monitoring guide: https://docs.aws.amazon.com/rds/latest/userguide/monitoring.html
- AWS CDK Python reference: https://docs.aws.amazon.com/cdk/api/v2/python/

## Cleanup

### Destroy the Stack

```bash
# Preview what will be deleted
cdk diff --template app.py

# Destroy all resources
cdk destroy

# Force destruction without confirmation
cdk destroy --force
```

### Manual Cleanup (if needed)

If `cdk destroy` fails, manually delete:
1. RDS snapshots (if any were created)
2. CloudWatch log groups with retention
3. Secrets Manager secrets after recovery window

## Development

### Code Structure

```
.
├── app.py                 # Main CDK application
├── requirements.txt       # Python dependencies
├── setup.py              # Package configuration
├── cdk.json              # CDK configuration
└── README.md             # This file
```

### Local Development

```bash
# Install development dependencies
pip install -e ".[dev]"

# Run code formatting
black app.py

# Run linting
flake8 app.py

# Run type checking
mypy app.py

# Run tests (add tests in tests/ directory)
pytest
```

### Contributing

1. Follow PEP 8 style guidelines
2. Add type hints to all functions
3. Include comprehensive docstrings
4. Test changes in a development environment
5. Update this README for any significant changes

## License

This code is provided under the Apache 2.0 License. See the AWS CDK project for full license details.