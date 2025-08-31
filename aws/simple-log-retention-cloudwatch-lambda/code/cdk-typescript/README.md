# Simple Log Retention Management - CDK TypeScript Implementation

This directory contains the AWS CDK TypeScript implementation for the "Simple Log Retention Management with CloudWatch and Lambda" recipe. This solution automates CloudWatch Logs retention policy management using Lambda and EventBridge.

## Architecture

The CDK application creates:

- **Lambda Function**: Automated log retention management function with Python 3.12 runtime
- **IAM Role**: Execution role with CloudWatch Logs permissions following least privilege principle  
- **EventBridge Rule**: Weekly schedule (every 7 days) to trigger the Lambda function
- **Test Log Groups**: Sample log groups with different naming patterns to demonstrate functionality
- **CloudWatch Dashboard**: Monitoring dashboard for Lambda function metrics
- **Outputs**: Key resource identifiers and dashboard URL for easy access

## Prerequisites

- Node.js 18+ installed
- AWS CLI configured with appropriate permissions
- AWS CDK CLI installed globally (`npm install -g aws-cdk`)
- TypeScript installed globally (`npm install -g typescript`)

### Required AWS Permissions

Your AWS credentials must have permissions for:
- CloudFormation stack operations
- Lambda function creation and management
- IAM role and policy creation
- CloudWatch Logs operations
- EventBridge rule creation
- CloudWatch dashboard creation

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Bootstrap CDK (if not done previously)

```bash
cdk bootstrap
```

### 3. Build the Application

```bash
npm run build
```

### 4. Deploy the Stack

```bash
cdk deploy
```

Or use the npm script:

```bash
npm run deploy
```

### 5. Verify Deployment

After deployment, the stack outputs will display:
- Lambda function name and ARN
- EventBridge rule name  
- CloudWatch dashboard URL

## Testing the Solution

### Manual Testing

1. **Invoke the Lambda function manually:**
   ```bash
   aws lambda invoke \
     --function-name <LambdaFunctionName> \
     --payload '{}' \
     response.json
   ```

2. **Check the response:**
   ```bash
   cat response.json | jq .
   ```

3. **Verify retention policies were applied:**
   ```bash
   aws logs describe-log-groups \
     --query 'logGroups[*].{Name:logGroupName,Retention:retentionInDays}' \
     --output table
   ```

### Automatic Testing

The EventBridge rule will automatically trigger the Lambda function weekly. Monitor execution through:

- CloudWatch dashboard (URL provided in stack outputs)
- Lambda function logs in CloudWatch Logs console
- EventBridge rule metrics

## Configuration

### Environment Variables

The Lambda function accepts these environment variables (configurable in `app.ts`):

- `DEFAULT_RETENTION_DAYS`: Default retention period for unmatched log groups (default: 30 days)

### Retention Rules

The function applies retention policies based on log group naming patterns:

| Pattern | Retention | Description |
|---------|-----------|-------------|
| `/aws/lambda/` | 30 days | Lambda function logs |
| `/aws/apigateway/` | 90 days | API Gateway logs |
| `/aws/codebuild/` | 14 days | CodeBuild logs |
| `/aws/ecs/` | 60 days | ECS container logs |
| `/aws/stepfunctions/` | 90 days | Step Functions logs |
| `/application/` | 180 days | Application logs |
| `/system/` | 365 days | System logs |
| *Other patterns* | 30 days | Default retention |

### Customizing Retention Rules

To modify retention rules, edit the `get_retention_days` function in the Lambda code within `app.ts`.

## Development

### Available Scripts

- `npm run build` - Compile TypeScript to JavaScript
- `npm run watch` - Watch for changes and auto-compile
- `npm run test` - Run Jest tests (when implemented)
- `npm run cdk` - Run CDK CLI commands
- `npm run deploy` - Deploy the stack
- `npm run destroy` - Destroy the stack
- `npm run diff` - Show differences between deployed and local stack
- `npm run synth` - Synthesize CloudFormation template

### Project Structure

```
├── app.ts              # Main CDK application file
├── package.json        # Node.js dependencies and scripts
├── tsconfig.json       # TypeScript configuration
├── cdk.json           # CDK configuration
└── README.md          # This file
```

## Monitoring and Troubleshooting

### CloudWatch Dashboard

The stack creates a CloudWatch dashboard with Lambda function metrics:
- Invocation count
- Error count  
- Duration
- Success rate

Access via the URL provided in stack outputs.

### Lambda Function Logs

Monitor function execution in CloudWatch Logs:
```
/aws/lambda/<function-name>
```

### Common Issues

1. **Permission Errors**: Ensure your AWS credentials have sufficient permissions
2. **Function Timeout**: Default timeout is 5 minutes; increase if needed for large log group counts
3. **Rate Limiting**: AWS APIs have rate limits; the function includes error handling for throttling

## Cleanup

### Remove All Resources

```bash
cdk destroy
```

Or use the npm script:

```bash
npm run destroy
```

### Verify Cleanup

Check that all resources were removed:
```bash
aws cloudformation describe-stacks --stack-name SimpleLogRetentionStack
```

## Cost Optimization

This solution follows AWS cost optimization best practices:

- **Serverless Architecture**: Pay only for Lambda execution time
- **Efficient Scheduling**: Weekly execution reduces unnecessary runs
- **Right-sized Resources**: 256MB memory allocation optimized for the workload
- **Log Retention**: Automated retention policies reduce storage costs
- **Resource Tagging**: All resources tagged for cost tracking

## Security

Security best practices implemented:

- **Least Privilege IAM**: Role has minimal required permissions
- **No Hardcoded Secrets**: All configuration via environment variables
- **Secure Defaults**: Uses latest Lambda runtime and recommended settings
- **Resource Isolation**: Stack creates dedicated resources with proper naming

## Support

For issues with this CDK implementation:

1. Check the original recipe documentation
2. Review CloudFormation events in AWS Console
3. Check Lambda function logs for execution details
4. Verify IAM permissions are correctly applied

## License

This code is provided under the MIT License. See the original recipe for full license details.