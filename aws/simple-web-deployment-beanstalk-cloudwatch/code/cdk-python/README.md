# Simple Web Application CDK Python

This directory contains the AWS CDK Python implementation for deploying a simple web application using Elastic Beanstalk with comprehensive CloudWatch monitoring.

## Architecture Overview

This CDK application creates:

- **S3 Bucket**: Secure storage for application source bundles with versioning and lifecycle policies
- **Elastic Beanstalk Application**: Managed platform for hosting Python Flask web applications
- **Elastic Beanstalk Environment**: Production-ready environment with enhanced health reporting
- **IAM Roles**: Service role and instance profile with least-privilege permissions
- **CloudWatch Monitoring**: Comprehensive alarms for health, errors, and performance
- **SNS Topic**: Alert notifications for monitoring alarms
- **CloudWatch Logs**: Centralized logging with retention policies

## Prerequisites

- Python 3.8 or later
- AWS CLI installed and configured
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for:
  - Elastic Beanstalk (application and environment management)
  - S3 (bucket creation and object management)
  - IAM (role and policy creation)
  - CloudWatch (alarms and logs)
  - SNS (topic creation)

## Installation and Setup

1. **Clone and Navigate to Directory**:
   ```bash
   cd aws/simple-web-deployment-beanstalk-cloudwatch/code/cdk-python/
   ```

2. **Create Virtual Environment**:
   ```bash
   python -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install Dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Configure AWS Credentials**:
   ```bash
   aws configure
   # Or set environment variables:
   export AWS_ACCESS_KEY_ID=your-access-key
   export AWS_SECRET_ACCESS_KEY=your-secret-key
   export AWS_DEFAULT_REGION=us-east-1
   ```

5. **Bootstrap CDK (First Time Only)**:
   ```bash
   cdk bootstrap
   ```

## Configuration

### Environment Variables

You can customize the deployment using environment variables:

```bash
export APP_NAME="my-web-app"
export ENVIRONMENT="production"
export INSTANCE_TYPE="t3.micro"
export CDK_DEFAULT_REGION="us-east-1"
```

### CDK Context

Alternatively, use CDK context parameters:

```bash
cdk deploy -c app_name=my-web-app -c environment=staging -c instance_type=t3.small
```

### Configuration Options

| Parameter | Default | Description |
|-----------|---------|-------------|
| `app_name` | `simple-web-app` | Name of the Elastic Beanstalk application |
| `environment` | `production` | Environment name (production, staging, dev) |
| `instance_type` | `t3.micro` | EC2 instance type for Beanstalk environment |

## Deployment

### Quick Deployment

```bash
# Synthesize CloudFormation template (recommended first)
cdk synth

# Deploy the stack
cdk deploy
```

### Custom Configuration Deployment

```bash
# Deploy with custom parameters
cdk deploy -c app_name=my-app -c environment=staging -c instance_type=t3.small

# Deploy to specific account/region
CDK_DEFAULT_ACCOUNT=123456789012 CDK_DEFAULT_REGION=us-west-2 cdk deploy
```

### Deployment Outputs

After successful deployment, the stack provides these outputs:

- **ApplicationName**: Elastic Beanstalk application name
- **EnvironmentName**: Elastic Beanstalk environment name
- **EnvironmentURL**: URL to access your deployed application
- **SourceBucketName**: S3 bucket name for source bundles
- **AlertTopicArn**: SNS topic ARN for monitoring alerts
- **LogGroupName**: CloudWatch log group name

## Application Deployment

After the infrastructure is deployed, you need to deploy your application code:

### Prepare Application Source

1. **Create Application Directory**:
   ```bash
   mkdir my-flask-app
   cd my-flask-app
   ```

2. **Create Flask Application** (`application.py`):
   ```python
   import flask
   import logging
   from datetime import datetime

   application = flask.Flask(__name__)
   logging.basicConfig(level=logging.INFO)
   logger = logging.getLogger(__name__)

   @application.route('/')
   def hello():
       logger.info("Home page accessed")
       return {'message': 'Hello from Elastic Beanstalk!', 'timestamp': datetime.now().isoformat()}

   @application.route('/health')
   def health():
       return {'status': 'healthy', 'timestamp': datetime.now().isoformat()}

   if __name__ == '__main__':
       application.run(debug=True)
   ```

3. **Create Requirements File** (`requirements.txt`):
   ```
   Flask==3.0.3
   Werkzeug==3.0.3
   ```

### Deploy Application

```bash
# Create source bundle
zip -r myapp-v1.zip . -x "*.git*" "__pycache__/*" "*.pyc"

# Upload to S3 (get bucket name from CDK outputs)
aws s3 cp myapp-v1.zip s3://your-source-bucket-name/

# Create application version
aws elasticbeanstalk create-application-version \
    --application-name your-app-name \
    --version-label v1.0 \
    --source-bundle S3Bucket=your-source-bucket-name,S3Key=myapp-v1.zip

# Deploy to environment
aws elasticbeanstalk update-environment \
    --environment-name your-environment-name \
    --version-label v1.0
```

## Monitoring and Alerts

### CloudWatch Alarms

The stack creates several monitoring alarms:

1. **Environment Health**: Monitors overall environment health status
2. **4xx Errors**: Alerts on client errors (threshold: 10 requests in 5 minutes)
3. **5xx Errors**: Alerts on server errors (threshold: 5 requests in 5 minutes)
4. **Response Time**: Monitors P95 latency (threshold: 2 seconds)

### SNS Notifications

To receive email alerts:

```bash
# Subscribe to the SNS topic (get ARN from CDK outputs)
aws sns subscribe \
    --topic-arn arn:aws:sns:region:account:your-alert-topic \
    --protocol email \
    --notification-endpoint your-email@example.com

# Confirm subscription in your email
```

### CloudWatch Logs

Application logs are automatically streamed to CloudWatch Logs:

- **Environment Logs**: `/aws/elasticbeanstalk/your-environment-name/`
- **Application Logs**: `/aws/elasticbeanstalk/your-app-name/application`

## Development and Testing

### Code Quality Tools

The project includes development tools for maintaining code quality:

```bash
# Install development dependencies
pip install -r requirements.txt

# Format code
python -m black .

# Lint code
python -m flake8 .

# Type checking
python -m mypy app.py

# Security scan
python -m bandit -r .

# Run tests (if test files exist)
python -m pytest tests/ -v
```

### CDK Development Commands

```bash
# List all stacks
cdk list

# Show differences between deployed and current state
cdk diff

# Generate CloudFormation template
cdk synth

# Deploy with verbose output
cdk deploy --verbose

# Watch mode for development (auto-redeploy on changes)
cdk watch
```

## Troubleshooting

### Common Issues

1. **Permission Denied**:
   - Ensure your AWS credentials have sufficient permissions
   - Check IAM policies for Elastic Beanstalk, S3, and CloudWatch

2. **Environment Creation Failed**:
   - Verify the solution stack name is current
   - Check VPC and subnet configurations
   - Ensure instance type is available in your region

3. **Application Deployment Failed**:
   - Check application logs in CloudWatch
   - Verify requirements.txt includes all dependencies
   - Ensure main application file is named `application.py`

### Debugging Commands

```bash
# Check environment status
aws elasticbeanstalk describe-environments \
    --application-name your-app-name

# View recent events
aws elasticbeanstalk describe-events \
    --application-name your-app-name \
    --max-records 50

# Check CloudWatch logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/elasticbeanstalk"
```

## Cleanup

### Destroy Infrastructure

```bash
# Destroy the CDK stack
cdk destroy

# Confirm deletion when prompted
```

### Manual Cleanup (if needed)

If automated cleanup fails, manually delete:

1. Elastic Beanstalk environment and application
2. S3 bucket and objects
3. CloudWatch alarms and log groups
4. SNS topic and subscriptions
5. IAM roles and policies

## Cost Optimization

### Cost Considerations

- **t3.micro instances**: Eligible for AWS Free Tier (750 hours/month)
- **S3 storage**: Pay for source bundle storage (minimal cost)
- **CloudWatch**: Free tier includes 10 alarms and 5GB log ingestion
- **Data transfer**: Standard AWS data transfer rates apply

### Cost Optimization Tips

1. Use Single Instance environment for development
2. Enable S3 lifecycle policies for old source bundles
3. Set appropriate CloudWatch log retention periods
4. Use Spot instances for non-production workloads
5. Monitor usage with AWS Cost Explorer

## Security Best Practices

### Implemented Security Features

- **S3 Bucket**: Block public access, encryption at rest, secure transport only
- **IAM Roles**: Least privilege permissions, service-specific roles
- **Environment**: Enhanced health reporting, secure configuration
- **Logs**: Centralized logging with retention policies

### Additional Security Recommendations

1. Enable AWS CloudTrail for audit logging
2. Use AWS Config for compliance monitoring
3. Implement Web Application Firewall (WAF) for production
4. Enable VPC for network isolation
5. Use AWS Secrets Manager for sensitive configuration

## Support and Documentation

### AWS Documentation

- [AWS CDK Python Reference](https://docs.aws.amazon.com/cdk/api/v2/python/)
- [Elastic Beanstalk Developer Guide](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/)
- [CloudWatch User Guide](https://docs.aws.amazon.com/cloudwatch/latest/monitoring/)

### CDK Resources

- [CDK Workshop](https://cdkworkshop.com/)
- [CDK Examples](https://github.com/aws-samples/aws-cdk-examples)
- [CDK Best Practices](https://docs.aws.amazon.com/cdk/v2/guide/best-practices.html)

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Run code quality checks
6. Submit a pull request

## Changelog

### Version 1.0.0
- Initial release
- Basic Elastic Beanstalk deployment
- CloudWatch monitoring and alerts
- S3 source bundle management
- Comprehensive documentation