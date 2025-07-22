# Feature Flags with AWS AppConfig - CDK TypeScript

This CDK TypeScript application implements a complete feature flag management system using AWS AppConfig, Lambda, and CloudWatch monitoring. The infrastructure follows AWS best practices and includes automatic rollback capabilities for safe feature deployments.

## Architecture Overview

The application creates:

- **AWS AppConfig Application**: Container for feature flag configurations
- **AppConfig Environment**: Production environment with monitoring integration
- **Feature Flag Configuration Profile**: Hosted configuration for feature flags
- **Lambda Function**: Demonstrates feature flag consumption using AppConfig extension
- **CloudWatch Monitoring**: Automatic rollback based on Lambda error rates
- **Gradual Deployment Strategy**: 20-minute rollout with 25% growth rate
- **IAM Roles**: Least privilege access for all components

## Prerequisites

- Node.js 18.x or later
- AWS CLI configured with appropriate credentials
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for:
  - AppConfig (applications, environments, configurations)
  - Lambda (functions, layers, execution roles)
  - CloudWatch (alarms, logs, metrics)
  - IAM (roles, policies, service-linked roles)

## Installation

1. Install dependencies:
   ```bash
   npm install
   ```

2. Configure CDK (if first time):
   ```bash
   cdk bootstrap
   ```

## Usage

### Deploy the Stack

```bash
# Synthesize CloudFormation template
npm run synth

# Deploy the infrastructure
npm run deploy
```

### Test Feature Flags

After deployment, test the Lambda function:

```bash
# Get the Lambda function name from stack outputs
aws lambda invoke \
    --function-name <LAMBDA_FUNCTION_NAME> \
    --payload '{}' \
    response.json

# View the response
cat response.json | jq .
```

### Update Feature Flags

1. **Modify Configuration**: Update the feature flags in the stack
2. **Deploy Changes**: Run `cdk deploy` to create new configuration version
3. **Create Deployment**: Use AppConfig console or CLI to deploy with gradual strategy

### Monitor Deployments

```bash
# Check deployment status
aws appconfig get-deployment \
    --application-id <APP_ID> \
    --environment-id <ENV_ID> \
    --deployment-number <DEPLOYMENT_NUMBER>

# Monitor CloudWatch alarms
aws cloudwatch describe-alarms \
    --alarm-names <ALARM_NAME>
```

## Configuration Options

The stack accepts several configuration options through props:

```typescript
new FeatureFlagsAppConfigStack(app, 'MyStack', {
  resourcePrefix: 'MyApp',           // Default: 'FeatureFlags'
  environmentName: 'staging',        // Default: 'production'
  deploymentConfig: {
    deploymentDurationInMinutes: 30, // Default: 20
    growthFactor: 50,                // Default: 25
    finalBakeTimeInMinutes: 15       // Default: 10
  }
});
```

## Feature Flags Structure

The application includes three example feature flags:

### 1. New Checkout Flow
- **Purpose**: Enable new checkout experience
- **Default**: Disabled
- **Attributes**: `rollout-percentage`, `target-audience`

### 2. Enhanced Search
- **Purpose**: Enable advanced search functionality
- **Default**: Enabled
- **Attributes**: `search-algorithm`, `cache-ttl`

### 3. Premium Features
- **Purpose**: Enable premium feature set
- **Default**: Disabled
- **Attributes**: `feature-list`

## Security Features

- **Least Privilege IAM**: Lambda role has minimal required permissions
- **Service-Linked Roles**: AppConfig uses service-linked roles for monitoring
- **CDK Nag Integration**: Automated security best practice validation
- **Encryption**: CloudWatch logs encrypted by default
- **Monitoring**: Comprehensive error tracking and alerting

## Monitoring and Observability

### CloudWatch Alarms
- **Error Rate Monitoring**: Triggers when Lambda errors exceed threshold
- **Automatic Rollback**: AppConfig rolls back on alarm state

### X-Ray Tracing
- **Request Tracing**: End-to-end visibility of Lambda executions
- **Performance Monitoring**: Identify bottlenecks and optimization opportunities

### Logs
- **Structured Logging**: Lambda function uses structured log format
- **Retention Policy**: Logs retained for 7 days by default

## Production Considerations

### Scaling
- **Reserved Concurrency**: Lambda limited to 10 concurrent executions
- **Dead Letter Queue**: Failed executions sent to DLQ for analysis
- **AppConfig Caching**: Extension provides local caching for performance

### Cost Optimization
- **Minimal Resources**: Only creates necessary infrastructure
- **Efficient Polling**: AppConfig extension optimizes configuration retrieval
- **Log Retention**: Short retention period for cost control

### Operational Excellence
- **Gradual Deployments**: Safe rollout with monitoring checkpoints
- **Rollback Capability**: Automatic rollback on detection of issues
- **Comprehensive Outputs**: All important resource identifiers exported

## Troubleshooting

### Common Issues

1. **AppConfig Extension Not Working**
   - Verify Lambda layer ARN is correct for your region
   - Check Lambda environment variables are set correctly

2. **CloudWatch Alarm Not Triggering**
   - Ensure Lambda function is generating the expected metrics
   - Verify alarm threshold and evaluation periods are appropriate

3. **Deployment Failing**
   - Check IAM permissions for all services
   - Verify service-linked role creation permissions

### Debug Commands

```bash
# Check Lambda logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/feature-flag-demo"

# View recent log events
aws logs get-log-events \
    --log-group-name "/aws/lambda/feature-flag-demo-XXXXXX" \
    --log-stream-name "YYYY/MM/DD/[\$LATEST]XXXXXXX"

# Test AppConfig directly
aws appconfig start-configuration-session \
    --application-identifier <APP_ID> \
    --environment-identifier <ENV_ID> \
    --configuration-profile-identifier <PROFILE_ID>
```

## Cleanup

Remove all resources:

```bash
npm run destroy
```

**Note**: This will delete all resources including configuration data. Ensure you have backups if needed.

## Next Steps

1. **Integrate with Applications**: Use the AppConfig SDKs in your applications
2. **Add More Feature Flags**: Extend the configuration with additional flags
3. **Custom Deployment Strategies**: Create deployment strategies for different scenarios
4. **Enhanced Monitoring**: Add custom metrics and dashboards
5. **Multi-Environment**: Deploy to multiple environments (dev, staging, prod)

## Resources

- [AWS AppConfig Documentation](https://docs.aws.amazon.com/appconfig/)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Feature Flag Best Practices](https://aws.amazon.com/builders-library/using-feature-flags-to-mitigate-risk/)
- [AWS Lambda Extensions](https://docs.aws.amazon.com/lambda/latest/dg/lambda-extensions.html)