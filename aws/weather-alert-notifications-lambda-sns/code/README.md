# Infrastructure as Code for Weather Alert Notifications with Lambda and SNS

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Weather Alert Notifications with Lambda and SNS".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured (version 2.0 or later)
- Appropriate AWS permissions for creating:
  - Lambda functions and execution roles
  - SNS topics and subscriptions
  - EventBridge (CloudWatch Events) rules
  - IAM roles and policies
  - CloudWatch log groups
- For CDK implementations: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed
- Optional: OpenWeatherMap API key from [openweathermap.org](https://openweathermap.org/api)

## Architecture Overview

This solution deploys:
- **Lambda Function**: Weather monitoring logic with configurable thresholds
- **SNS Topic**: Message distribution for weather alerts
- **EventBridge Rule**: Hourly scheduling trigger
- **IAM Role**: Lambda execution permissions with SNS publish access
- **CloudWatch Log Group**: Function execution logging

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name weather-alerts-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
                 ParameterKey=MonitoredCity,ParameterValue=Seattle \
                 ParameterKey=TemperatureThreshold,ParameterValue=32 \
                 ParameterKey=WindSpeedThreshold,ParameterValue=25

# Check deployment status
aws cloudformation describe-stacks --stack-name weather-alerts-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name weather-alerts-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not done previously)
cdk bootstrap

# Set environment variables (optional)
export NOTIFICATION_EMAIL=your-email@example.com
export MONITORED_CITY=Seattle
export WEATHER_API_KEY=your-api-key-here

# Deploy the stack
cdk deploy --parameters NotificationEmail=your-email@example.com

# View stack outputs
cdk list
```

### Using CDK Python (AWS)

```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not done previously)
cdk bootstrap

# Set environment variables (optional)
export NOTIFICATION_EMAIL=your-email@example.com
export MONITORED_CITY=Seattle
export WEATHER_API_KEY=your-api-key-here

# Deploy the stack
cdk deploy --parameters NotificationEmail=your-email@example.com

# View stack information
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
terraform plan \
    -var="notification_email=your-email@example.com" \
    -var="monitored_city=Seattle" \
    -var="temperature_threshold=32" \
    -var="wind_speed_threshold=25"

# Apply configuration
terraform apply \
    -var="notification_email=your-email@example.com" \
    -var="monitored_city=Seattle"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export NOTIFICATION_EMAIL=your-email@example.com
export MONITORED_CITY=Seattle  # Optional, defaults to Seattle
export WEATHER_API_KEY=your-api-key-here  # Optional, uses demo data if not set

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `weather-alerts`)]'
```

## Configuration

### Environment Variables

All implementations support these configuration options:

- **NOTIFICATION_EMAIL**: Email address for receiving weather alerts (required)
- **MONITORED_CITY**: City to monitor (default: Seattle)
- **WEATHER_API_KEY**: OpenWeatherMap API key (optional, uses demo data if not provided)
- **TEMPERATURE_THRESHOLD**: Temperature alert threshold in Fahrenheit (default: 32)
- **WIND_SPEED_THRESHOLD**: Wind speed alert threshold in MPH (default: 25)
- **SCHEDULE_EXPRESSION**: EventBridge schedule (default: "rate(1 hour)")

### Customizing Weather Thresholds

You can modify weather alert thresholds by updating the Lambda function environment variables:

```bash
# Update via AWS CLI
aws lambda update-function-configuration \
    --function-name weather-alerts-function \
    --environment Variables='{
        "SNS_TOPIC_ARN":"arn:aws:sns:region:account:topic-name",
        "CITY":"New York",
        "TEMP_THRESHOLD":"25",
        "WIND_THRESHOLD":"30",
        "WEATHER_API_KEY":"your-api-key"
    }'
```

## Post-Deployment Steps

1. **Confirm SNS Subscription**: Check your email and confirm the SNS subscription to receive alerts.

2. **Test the Function**: Manually invoke the Lambda function to verify it's working:
   ```bash
   aws lambda invoke \
       --function-name weather-alerts-function \
       --payload '{}' \
       response.json && cat response.json
   ```

3. **Monitor Logs**: Check CloudWatch logs for function execution:
   ```bash
   aws logs describe-log-groups \
       --log-group-name-prefix /aws/lambda/weather-alerts
   ```

4. **Verify Scheduling**: Confirm EventBridge rule is active:
   ```bash
   aws events describe-rule --name weather-check-schedule
   ```

## Monitoring and Troubleshooting

### CloudWatch Metrics

Monitor these key metrics:
- Lambda function invocations and errors
- SNS message publish success/failure
- EventBridge rule execution

### Common Issues

1. **SNS Subscription Not Confirmed**: Check email and confirm subscription
2. **API Rate Limits**: OpenWeatherMap free tier has request limits
3. **Lambda Timeout**: Increase timeout if API requests are slow
4. **IAM Permissions**: Ensure Lambda role has SNS publish permissions

### Debugging Commands

```bash
# Check Lambda function configuration
aws lambda get-function --function-name weather-alerts-function

# View recent log events
aws logs filter-log-events \
    --log-group-name /aws/lambda/weather-alerts-function \
    --start-time $(date -d '1 hour ago' +%s)000

# Test SNS topic
aws sns publish \
    --topic-arn arn:aws:sns:region:account:weather-notifications \
    --message "Test message"
```

## Cost Optimization

Expected monthly costs (low volume):
- **Lambda**: $0.01-$0.05 (744 invocations/month)
- **SNS**: $0.01-$0.10 (depends on message volume)
- **EventBridge**: $0.01 (744 rule executions/month)
- **CloudWatch Logs**: $0.01-$0.03 (basic logging)

**Total estimated cost**: $0.05-$0.20/month

## Security Considerations

- Lambda function uses least-privilege IAM role
- SNS topic access is restricted to the Lambda function
- No sensitive data stored in environment variables
- API keys should be stored in AWS Secrets Manager for production use

## Cleanup

### Using CloudFormation (AWS)

```bash
aws cloudformation delete-stack --stack-name weather-alerts-stack

# Verify deletion
aws cloudformation describe-stacks \
    --stack-name weather-alerts-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK (AWS)

```bash
# From the appropriate CDK directory
cdk destroy

# Confirm when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy \
    -var="notification_email=your-email@example.com"

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Advanced Customization

### Multi-City Monitoring

To monitor multiple cities, modify the Lambda function to iterate through a list of cities stored in environment variables or DynamoDB.

### Custom Alert Conditions

Extend the weather monitoring logic to include:
- Precipitation probability thresholds
- Air quality index monitoring
- Severe weather warnings
- Historical data comparison

### Alternative Notification Channels

- Add SMS notifications via SNS
- Integrate with Slack using webhook URLs
- Send notifications to Microsoft Teams
- Store alerts in DynamoDB for historical analysis

### Enhanced Scheduling

- Different schedules for different cities
- More frequent monitoring during severe weather
- Conditional scheduling based on weather patterns

## Troubleshooting Guide

### Function Not Executing

1. Check EventBridge rule status: `aws events describe-rule --name weather-check-schedule`
2. Verify Lambda permissions: `aws lambda get-policy --function-name weather-alerts-function`
3. Check CloudWatch logs for errors

### No Notifications Received

1. Confirm SNS subscription status
2. Check spam/junk email folders
3. Verify SNS topic permissions
4. Test SNS publishing manually

### API Errors

1. Verify OpenWeatherMap API key validity
2. Check API request limits and quotas
3. Monitor function timeout settings
4. Review network connectivity from Lambda

## Support and Resources

- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [Amazon SNS Documentation](https://docs.aws.amazon.com/sns/)
- [Amazon EventBridge Documentation](https://docs.aws.amazon.com/eventbridge/)
- [OpenWeatherMap API Documentation](https://openweathermap.org/api)
- [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/)

## Contributing

To contribute improvements to this infrastructure code:

1. Test changes in a development environment
2. Ensure all IaC implementations remain synchronized
3. Update documentation for any new features
4. Follow AWS security best practices
5. Include appropriate error handling and logging

For issues with this infrastructure code, refer to the original recipe documentation or create an issue in the repository.