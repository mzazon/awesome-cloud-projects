# Scheduled Email Reports - CDK Python Application

This AWS CDK Python application deploys a complete serverless email reporting system using App Runner, SES, and EventBridge Scheduler. The infrastructure follows AWS Well-Architected principles with emphasis on security, reliability, and cost optimization.

## Architecture Overview

The solution creates:

- **AWS App Runner Service**: Hosts a containerized Flask application that generates business reports
- **Amazon SES**: Provides reliable email delivery with high deliverability rates
- **EventBridge Scheduler**: Automates report generation on a configurable schedule
- **CloudWatch**: Comprehensive monitoring with dashboards, metrics, and alarms
- **IAM Roles**: Least-privilege security configurations for all services

## Prerequisites

Before deploying this application, ensure you have:

1. **AWS CLI** configured with appropriate permissions
2. **AWS CDK** v2.161.0 or later installed
3. **Python 3.8+** installed
4. **Node.js** (required for CDK)
5. **Verified SES email address** for sending reports
6. **GitHub repository** with your Flask application code

## Quick Start

### 1. Install Dependencies

```bash
# Install Python dependencies
pip install -r requirements.txt

# Install CDK globally (if not already installed)
npm install -g aws-cdk
```

### 2. Configure Application

Update the context values in `cdk.json`:

```json
{
  "context": {
    "app_name": "your-email-reports-service",
    "verified_email": "your-verified-email@example.com",
    "schedule_expression": "cron(0 9 * * ? *)",
    "environment": "dev"
  }
}
```

### 3. Bootstrap CDK (First Time Only)

```bash
cdk bootstrap
```

### 4. Deploy the Application

```bash
# Synthesize CloudFormation template
cdk synth

# Deploy the stack
cdk deploy
```

### 5. Verify SES Email Address

After deployment, verify your email address in the SES console:

1. Go to AWS SES Console
2. Navigate to "Verified identities"
3. Find your email address and click "Verify"
4. Check your email for verification link

## Configuration Options

### CDK Context Parameters

| Parameter | Description | Default Value |
|-----------|-------------|---------------|
| `app_name` | Name of the App Runner service | `email-reports-service` |
| `verified_email` | Email address for SES (must be verified) | `your-verified-email@example.com` |
| `schedule_expression` | Cron expression for report schedule | `cron(0 9 * * ? *)` (9 AM UTC daily) |
| `environment` | Environment name for resource tagging | `dev` |

### Schedule Expression Examples

| Schedule | Cron Expression | Description |
|----------|----------------|-------------|
| Daily at 9 AM UTC | `cron(0 9 * * ? *)` | Run every day at 9:00 AM UTC |
| Weekly on Monday | `cron(0 9 ? * MON *)` | Run every Monday at 9:00 AM UTC |
| Monthly on 1st | `cron(0 9 1 * ? *)` | Run on the 1st of each month at 9:00 AM UTC |
| Every 6 hours | `cron(0 */6 * * ? *)` | Run every 6 hours |

## Development Workflow

### Local Development

```bash
# Install dependencies in development mode
pip install -e .

# Run type checking
mypy scheduled_email_reports/

# Validate CDK code
cdk synth --strict
```

### Testing

```bash
# Run CDK unit tests (if implemented)
python -m pytest

# Validate CloudFormation template
cdk synth > template.yaml
aws cloudformation validate-template --template-body file://template.yaml
```

### CDK Nag Security Validation

This project includes CDK Nag for security best practices validation:

```bash
# CDK Nag runs automatically during synthesis
cdk synth

# Address any security warnings shown in the output
# Suppressions are documented in app.py for justified exceptions
```

## Monitoring and Operations

### CloudWatch Dashboard

Access the monitoring dashboard at:
```
https://{region}.console.aws.amazon.com/cloudwatch/home?region={region}#dashboards:name={app-name}-dashboard
```

The dashboard includes:
- App Runner service health metrics
- Custom application metrics (reports generated)
- SES email delivery metrics

### CloudWatch Alarms

Two alarms are configured:
1. **4xx Error Alarm**: Monitors App Runner service errors
2. **Report Generation Alarm**: Monitors successful report generation

### Application Logs

View application logs in CloudWatch:
```
/aws/apprunner/{app-name}
```

## Application Code Requirements

Your Flask application repository should include:

### Required Files

```
email-reports-app/
├── app.py                 # Flask application
├── requirements.txt       # Python dependencies
├── Dockerfile            # Container configuration
├── apprunner.yaml        # App Runner configuration
└── README.md             # Application documentation
```

### Flask Application Structure

```python
from flask import Flask, request, jsonify
import boto3
from datetime import datetime

app = Flask(__name__)
ses_client = boto3.client('ses')
cloudwatch = boto3.client('cloudwatch')

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({'status': 'healthy', 'timestamp': datetime.now().isoformat()})

@app.route('/generate-report', methods=['POST'])
def generate_report():
    # Your report generation logic here
    # Send email via SES
    # Publish metrics to CloudWatch
    pass

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000)
```

## Deployment Validation

After deployment, verify the system works:

1. **Health Check**: `curl https://{service-url}/health`
2. **Manual Report**: `curl -X POST https://{service-url}/generate-report`
3. **Check Email**: Verify report email received
4. **Monitor Dashboard**: Review CloudWatch metrics
5. **Verify Schedule**: Check EventBridge Schedule in AWS console

## Cost Optimization

This solution is designed for cost efficiency:

- **App Runner**: Pay only for compute time used
- **SES**: Low cost per email sent
- **EventBridge Scheduler**: Minimal cost for scheduled invocations
- **CloudWatch**: Optimized log retention (7 days)

Estimated monthly cost for moderate usage (100 emails/day): $10-20

## Security Features

- **IAM Roles**: Least privilege access for all services
- **CDK Nag**: Automated security best practices validation
- **SES**: Built-in email authentication (SPF, DKIM, DMARC)
- **App Runner**: Isolated container execution environment
- **CloudWatch**: Audit logging for all operations

## Troubleshooting

### Common Issues

1. **Email not sending**: Verify SES email address is verified
2. **App Runner startup fails**: Check Dockerfile and requirements.txt
3. **Schedule not triggering**: Verify EventBridge Scheduler permissions
4. **High costs**: Review CloudWatch log retention settings

### Debug Commands

```bash
# Check stack status
cdk list
cdk diff

# View CloudFormation events
aws cloudformation describe-stack-events --stack-name ScheduledEmailReportsStack

# Test App Runner service
aws apprunner describe-service --service-name {app-name}

# Check EventBridge Schedule
aws scheduler get-schedule --name {schedule-name}
```

## Cleanup

To avoid ongoing charges, destroy the stack when no longer needed:

```bash
# Delete all resources
cdk destroy

# Confirm deletion
# Type 'y' when prompted
```

**Note**: Some resources like CloudWatch logs may have retention policies that keep data after stack deletion.

## Additional Resources

- [AWS CDK Python Reference](https://docs.aws.amazon.com/cdk/api/v2/python/)
- [AWS App Runner Developer Guide](https://docs.aws.amazon.com/apprunner/)
- [Amazon SES Developer Guide](https://docs.aws.amazon.com/ses/)
- [EventBridge Scheduler User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/scheduler.html)
- [CDK Nag Documentation](https://github.com/cdklabs/cdk-nag)

## Support

For issues with this CDK application:

1. Check the troubleshooting section above
2. Review AWS service documentation
3. Check CDK GitHub issues
4. Consult AWS support resources

## License

This project is licensed under the MIT License - see the LICENSE file for details.