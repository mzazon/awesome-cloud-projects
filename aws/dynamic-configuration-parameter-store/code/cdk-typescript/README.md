# Dynamic Configuration with Parameter Store - CDK TypeScript

This CDK TypeScript application implements a serverless configuration management system using AWS Systems Manager Parameter Store, Lambda functions with the AWS Parameters and Secrets Extension, and EventBridge for automatic configuration invalidation.

## Architecture

The solution includes:

- **Parameter Store**: Centralized configuration storage with hierarchical organization
- **Lambda Function**: Configuration retrieval with intelligent caching via Parameters and Secrets Extension
- **EventBridge**: Event-driven cache invalidation on parameter changes
- **CloudWatch**: Comprehensive monitoring with custom metrics, alarms, and dashboard
- **IAM Roles**: Least-privilege security following AWS best practices

## Features

- ✅ **Intelligent Caching**: AWS Parameters and Secrets Extension provides local caching with configurable TTL
- ✅ **Event-Driven Updates**: EventBridge automatically triggers functions when parameters change
- ✅ **Security**: KMS encryption support for SecureString parameters with proper IAM controls
- ✅ **Monitoring**: CloudWatch alarms, custom metrics, and operational dashboard
- ✅ **Best Practices**: CDK Nag integration ensures security compliance
- ✅ **Error Handling**: Robust error handling with fallback to direct SSM calls

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18.x or later
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for deployment

## Installation

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Bootstrap CDK** (if first time using CDK in this account/region):
   ```bash
   cdk bootstrap
   ```

## Deployment

1. **Build the application**:
   ```bash
   npm run build
   ```

2. **Synthesize CloudFormation template** (optional, for validation):
   ```bash
   npm run synth
   ```

3. **Deploy the stack**:
   ```bash
   npm run deploy
   ```

   The deployment will create:
   - Sample configuration parameters in Parameter Store
   - Lambda function with Parameters and Secrets Extension
   - EventBridge rule for parameter change events
   - CloudWatch alarms and dashboard
   - All necessary IAM roles and policies

## Testing

After deployment, you can test the configuration management system:

1. **Invoke the Lambda function**:
   ```bash
   aws lambda invoke \
     --function-name <FUNCTION_NAME> \
     --payload '{}' \
     response.json
   
   cat response.json | jq .
   ```

2. **Update a parameter to test event-driven updates**:
   ```bash
   aws ssm put-parameter \
     --name "/myapp/config/api/timeout" \
     --value "45" \
     --type "String" \
     --overwrite
   ```

3. **Monitor metrics in CloudWatch**:
   - Navigate to the created dashboard to see real-time metrics
   - Check alarms for any configuration retrieval issues

## Configuration

The system uses these environment variables in the Lambda function:

- `PARAMETER_PREFIX`: Parameter Store path prefix (default: `/myapp/config`)
- `SSM_PARAMETER_STORE_TTL`: Cache TTL in seconds (default: `300`)

## Sample Parameters

The deployment creates these sample parameters:

- `/myapp/config/database/host`: Database endpoint
- `/myapp/config/database/port`: Database port number  
- `/myapp/config/database/password`: Encrypted database password (SecureString)
- `/myapp/config/api/timeout`: API timeout setting
- `/myapp/config/features/new-ui`: Feature flag for UI toggle

## Security Features

- **Least Privilege IAM**: Function role only has access to required Parameter Store paths
- **KMS Encryption**: SecureString parameters are encrypted using AWS KMS
- **ViaService Condition**: KMS decrypt permissions limited to SSM service
- **CDK Nag**: Security compliance checks with appropriate suppressions

## Monitoring and Observability

The solution includes comprehensive monitoring:

- **Lambda Metrics**: Invocations, errors, duration via CloudWatch
- **Custom Metrics**: Configuration retrieval success/failure rates
- **Alarms**: Proactive alerting on errors and performance issues
- **Dashboard**: Real-time visibility into system health
- **X-Ray Tracing**: Distributed tracing for performance analysis

## Cleanup

To remove all resources:

```bash
npm run destroy
```

This will delete all resources created by the stack, including:
- Lambda function and associated resources
- Parameter Store parameters
- CloudWatch alarms and dashboard
- IAM roles and policies
- EventBridge rules

## Cost Considerations

The solution is designed for cost optimization:

- **Serverless**: Pay only for actual Lambda invocations
- **Intelligent Caching**: Reduces Parameter Store API calls by ~99%
- **Right-Sized Resources**: Lambda memory and timeout optimized for workload
- **Standard Parameters**: Uses Standard tier parameters (lower cost than Advanced)

Estimated monthly cost for moderate usage: $5-10

## Customization

### Adding New Parameters

To add new configuration parameters, modify the `createSampleParameters()` method in the stack:

```typescript
new ssm.StringParameter(this, 'NewParameter', {
  parameterName: `${parameterPrefix}/new/parameter`,
  stringValue: 'parameter-value',
  description: 'Description of new parameter',
});
```

### Adjusting Cache TTL

Modify the `SSM_PARAMETER_STORE_TTL` environment variable:
- Lower values: More fresh data, higher API costs
- Higher values: Better performance, lower costs, potentially stale data

### Custom Metrics

Add custom metrics in the Lambda function:

```python
send_custom_metric('CustomMetricName', value, 'Unit')
```

## Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure the Lambda execution role has proper Parameter Store permissions
2. **Cache Issues**: Check the Parameters and Secrets Extension layer version for your region
3. **EventBridge Not Triggering**: Verify the rule pattern matches your parameter names

### Debugging

- Check CloudWatch Logs for the Lambda function
- Use X-Ray traces to identify performance bottlenecks  
- Monitor custom metrics in CloudWatch for configuration retrieval patterns

## Contributing

1. Make changes to the CDK code
2. Run tests: `npm test`
3. Synthesize: `npm run synth`
4. Deploy: `npm run deploy`

## References

- [AWS Parameters and Secrets Lambda Extension](https://docs.aws.amazon.com/systems-manager/latest/userguide/ps-integration-lambda-extensions.html)
- [Parameter Store EventBridge Integration](https://docs.aws.amazon.com/systems-manager/latest/userguide/sysman-paramstore-cwe.html)
- [AWS CDK v2 Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/)
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)