# Automated WorkSpaces Personal Provisioning - CDK TypeScript

This CDK TypeScript application automates the provisioning and configuration of AWS WorkSpaces Personal for development teams. It creates a complete infrastructure solution that includes Lambda automation, Systems Manager configuration documents, and EventBridge scheduling.

## Architecture Overview

The solution deploys the following AWS resources:

- **Lambda Function**: Orchestrates WorkSpaces provisioning and configuration
- **IAM Roles and Policies**: Least-privilege access for automation services
- **Secrets Manager Secret**: Secure storage for Active Directory credentials
- **Systems Manager Document**: Standardized development environment configuration
- **EventBridge Rule**: Scheduled automation trigger
- **CloudWatch Log Groups**: Centralized logging and monitoring

## Prerequisites

- AWS CLI configured with appropriate permissions
- Node.js 18+ installed
- AWS CDK v2 installed globally (`npm install -g aws-cdk`)
- Active Directory setup (Simple AD, Managed Microsoft AD, or AD Connector)
- VPC with subnets in at least two Availability Zones

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Bootstrap CDK (if not already done)

```bash
cdk bootstrap
```

### 3. Configure Context Parameters

Set required configuration via CDK context:

```bash
# Required: Set your WorkSpaces directory ID
cdk deploy --context directoryId=d-906734e6b2

# Optional: Customize other settings
cdk deploy \
  --context directoryId=d-906734e6b2 \
  --context bundleId=wsb-bh8rsxt14 \
  --context environment=production \
  --context automationSchedule="rate(12 hours)"
```

### 4. Deploy the Stack

```bash
# Deploy with default settings
cdk deploy

# Deploy with custom configuration
cdk deploy --context directoryId=YOUR_DIRECTORY_ID --context bundleId=YOUR_BUNDLE_ID
```

## Configuration Options

Configure the deployment using CDK context parameters:

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `directoryId` | WorkSpaces directory ID | None | Yes |
| `bundleId` | WorkSpaces bundle ID | `wsb-bh8rsxt14` | No |
| `targetUsers` | Array of user names for WorkSpaces | `["developer1","developer2","developer3"]` | No |
| `automationSchedule` | EventBridge schedule expression | `rate(24 hours)` | No |
| `environment` | Environment name for tagging | `development` | No |
| `stackName` | Custom stack name | `automated-workspaces-dev` | No |
| `enableVpcEndpoints` | Enable VPC endpoints | `false` | No |

### Example with Custom Configuration

```bash
cdk deploy \
  --context directoryId=d-906734e6b2 \
  --context bundleId=wsb-b0s22j3d7 \
  --context environment=production \
  --context "targetUsers=[\"alice\",\"bob\",\"charlie\"]" \
  --context automationSchedule="rate(8 hours)" \
  --context stackName=workspaces-prod
```

## Post-Deployment Configuration

### 1. Update Active Directory Credentials

After deployment, update the Secrets Manager secret with your AD service account credentials:

```bash
# Get the secret ARN from CloudFormation outputs
SECRET_ARN=$(aws cloudformation describe-stacks \
  --stack-name AutomatedWorkspacesStack \
  --query 'Stacks[0].Outputs[?OutputKey==`SecretsManagerArn`].OutputValue' \
  --output text)

# Update the secret with your AD credentials
aws secretsmanager update-secret \
  --secret-id $SECRET_ARN \
  --secret-string '{"username":"your-ad-service-account","password":"your-secure-password"}'
```

### 2. Test the Automation

Manually invoke the Lambda function to test the automation:

```bash
# Get the function name from outputs
FUNCTION_NAME=$(aws cloudformation describe-stacks \
  --stack-name AutomatedWorkspacesStack \
  --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
  --output text)

# Test the function
aws lambda invoke \
  --function-name $FUNCTION_NAME \
  --payload '{"test": "manual-invocation"}' \
  response.json

# Check the response
cat response.json
```

## Development Commands

```bash
# Install dependencies
npm install

# Compile TypeScript to JavaScript
npm run build

# Watch for changes and recompile
npm run watch

# Synthesize CloudFormation template
npm run synth
# or
cdk synth

# Deploy the stack
npm run deploy
# or
cdk deploy

# Compare deployed stack with current state
npm run diff
# or
cdk diff

# Run tests
npm test

# Lint TypeScript code
npm run lint

# Fix linting issues
npm run lint:fix
```

## Security Considerations

This application implements AWS security best practices:

- **Least Privilege IAM**: Lambda execution role has minimal required permissions
- **Encryption at Rest**: WorkSpaces volumes are encrypted by default
- **Secure Credential Storage**: AD credentials stored in Secrets Manager
- **Network Security**: Lambda can be deployed in VPC with security groups
- **Audit Logging**: All actions logged to CloudWatch for monitoring

## Cost Optimization

The solution includes several cost optimization features:

- **AUTO_STOP WorkSpaces**: Automatically stop after 60 minutes of inactivity
- **Scheduled Automation**: Runs daily to avoid unnecessary Lambda invocations
- **Log Retention**: CloudWatch logs retained for 2 weeks only
- **Resource Tagging**: Comprehensive tagging for cost allocation

## Monitoring and Troubleshooting

### CloudWatch Logs

Monitor the automation process through CloudWatch logs:

```bash
# View Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/automated-workspaces"

# Tail the latest logs
aws logs tail /aws/lambda/automated-workspaces-dev-automation --follow
```

### EventBridge Monitoring

Check EventBridge rule execution:

```bash
# Describe the rule
aws events describe-rule --name automated-workspaces-dev-daily-automation

# Check rule metrics in CloudWatch
aws cloudwatch get-metric-statistics \
  --namespace AWS/Events \
  --metric-name SuccessfulInvocations \
  --dimensions Name=RuleName,Value=automated-workspaces-dev-daily-automation \
  --start-time 2023-01-01T00:00:00Z \
  --end-time 2023-01-02T00:00:00Z \
  --period 3600 \
  --statistics Sum
```

### Common Issues

1. **Directory ID Not Found**: Ensure the directory ID exists and is in the correct region
2. **Bundle ID Invalid**: Verify the bundle ID is available in your region
3. **Permission Errors**: Check that the Lambda execution role has required permissions
4. **AD Authentication Failed**: Verify credentials in Secrets Manager are correct

## Cleanup

Remove all resources created by this stack:

```bash
# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

**Note**: WorkSpaces created by this automation are not automatically deleted when the stack is destroyed. You must manually terminate them if no longer needed.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Run `npm run lint` and fix any issues
6. Submit a pull request

## Support

For issues or questions:

1. Check CloudWatch logs for detailed error messages
2. Review AWS documentation for WorkSpaces, Lambda, and Systems Manager
3. Consult the AWS CDK documentation for construct usage
4. Open an issue in the repository for bugs or feature requests