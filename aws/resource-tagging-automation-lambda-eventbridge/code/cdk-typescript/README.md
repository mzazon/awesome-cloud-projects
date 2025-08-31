# Resource Tagging Automation - CDK TypeScript

This AWS CDK TypeScript application deploys an automated resource tagging solution that uses EventBridge to capture resource creation events and Lambda functions to apply standardized organizational tags.

## Architecture

The solution creates the following AWS resources:

- **Lambda Function**: Processes EventBridge events and applies standardized tags to newly created resources
- **IAM Role**: Provides least-privilege permissions for the Lambda function to tag resources
- **EventBridge Rule**: Captures CloudTrail events for resource creation activities
- **Resource Group**: Organizes automatically tagged resources for centralized management
- **CloudWatch Log Group**: Stores Lambda function execution logs with retention policy

## Prerequisites

Before deploying this CDK application, ensure you have:

1. **AWS CLI**: Installed and configured with appropriate credentials
2. **Node.js**: Version 18.0.0 or higher
3. **AWS CDK**: Version 2.139.0 or higher installed globally
4. **TypeScript**: For development and compilation
5. **CloudTrail**: Enabled in your AWS account to capture resource creation events
6. **Permissions**: IAM permissions to create Lambda functions, EventBridge rules, IAM roles, and Resource Groups

## Installation

1. **Clone the repository** and navigate to the CDK directory:
   ```bash
   cd /path/to/resource-tagging-automation-lambda-eventbridge/code/cdk-typescript
   ```

2. **Install dependencies**:
   ```bash
   npm install
   ```

3. **Bootstrap CDK** (if not already done in your account/region):
   ```bash
   npm run bootstrap
   ```

## Configuration

The application supports configuration through CDK context parameters:

- `environment`: Target environment (default: "production")
- `costCenter`: Cost center for resource allocation (default: "engineering") 
- `managedBy`: Management entity (default: "automation")

Set context parameters in `cdk.json` or pass them via command line:

```bash
cdk deploy -c environment=staging -c costCenter=devops
```

## Deployment

1. **Build the application**:
   ```bash
   npm run build
   ```

2. **Review the CloudFormation template** (optional):
   ```bash
   npm run synth
   ```

3. **Deploy the stack**:
   ```bash
   npm run deploy
   ```

   Or using CDK directly:
   ```bash
   cdk deploy
   ```

## Usage

Once deployed, the solution automatically:

1. **Monitors resource creation** through EventBridge rules connected to CloudTrail
2. **Applies standardized tags** to newly created EC2 instances, S3 buckets, RDS instances, and Lambda functions
3. **Organizes tagged resources** in a Resource Group for centralized management

### Standard Tags Applied

The Lambda function applies these tags to all newly created resources:

- `AutoTagged`: "true"
- `Environment`: "production" (configurable)
- `CostCenter`: "engineering" (configurable)
- `CreatedBy`: Username from CloudTrail event
- `CreatedDate`: Current date (YYYY-MM-DD format)
- `ManagedBy`: "automation" (configurable)

### Supported Resource Types

Currently supported AWS services:

- **EC2**: Instances created via RunInstances API
- **S3**: Buckets created via CreateBucket API
- **RDS**: DB instances created via CreateDBInstance API
- **Lambda**: Functions created via CreateFunction20150331 API

## Testing

Test the automated tagging by creating a new resource:

```bash
# Create test EC2 instance
aws ec2 run-instances \
    --image-id ami-0abcdef1234567890 \
    --instance-type t2.micro \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=test-auto-tagging}]'

# Wait 30 seconds for processing, then check tags
aws ec2 describe-tags --filters "Name=resource-id,Values=i-1234567890abcdef0"
```

## Monitoring

Monitor the solution through:

1. **CloudWatch Logs**: Lambda function execution logs at `/aws/lambda/auto-tagger-{uniqueId}`
2. **EventBridge Metrics**: Rule invocation metrics in CloudWatch
3. **Resource Groups**: View all auto-tagged resources in the AWS console

## Customization

### Adding New Resource Types

To support additional AWS services:

1. **Update EventBridge rule pattern** in `lib/resource-tagging-automation-stack.ts`:
   ```typescript
   eventPattern: {
     source: ['aws.ec2', 'aws.s3', 'aws.rds', 'aws.lambda', 'aws.dynamodb'],
     // Add new service events
   }
   ```

2. **Add tagging logic** in the Lambda function code:
   ```python
   elif event_name == 'CreateTable':
       resources_tagged += tag_dynamodb_table(detail, standard_tags)
   ```

3. **Update IAM permissions** to include new service actions.

### Modifying Standard Tags

Customize the tags applied by modifying the `standardTags` object in the stack constructor or the Lambda function code.

## Cleanup

To remove all resources created by this stack:

```bash
npm run destroy
```

Or using CDK directly:

```bash
cdk destroy
```

## Development

### Available Scripts

- `npm run build`: Compile TypeScript to JavaScript
- `npm run watch`: Watch for changes and recompile
- `npm run test`: Run unit tests
- `npm run lint`: Run ESLint
- `npm run format`: Format code with Prettier
- `npm run synth`: Synthesize CloudFormation template
- `npm run deploy`: Deploy the CDK stack
- `npm run destroy`: Destroy the CDK stack

### Code Structure

```
├── app.ts                           # CDK application entry point
├── lib/
│   └── resource-tagging-automation-stack.ts  # Main stack definition
├── package.json                     # Dependencies and scripts
├── tsconfig.json                   # TypeScript configuration
├── cdk.json                        # CDK configuration
└── README.md                       # This file
```

## Security Considerations

- **Least Privilege**: IAM role grants minimum permissions required for tagging operations
- **Audit Trail**: All tagging activities are logged to CloudWatch Logs
- **Resource Isolation**: Each deployment uses unique resource names to avoid conflicts
- **Tag Validation**: Lambda function validates resource types before applying tags

## Cost Optimization

- **Serverless Architecture**: Pay only for Lambda execution time
- **Log Retention**: CloudWatch logs retained for 30 days by default
- **Resource Efficiency**: EventBridge rules trigger only on relevant events

Estimated monthly cost: $0.50-$2.00 for typical workloads.

## Troubleshooting

### Common Issues

1. **CloudTrail Not Enabled**: Ensure CloudTrail is enabled to capture resource creation events
2. **Permission Errors**: Verify IAM role has necessary permissions for target services
3. **EventBridge Rule Not Triggering**: Check CloudTrail integration and event patterns
4. **Lambda Timeouts**: Increase timeout if processing large numbers of resources

### Debug Steps

1. Check CloudWatch Logs for Lambda function errors
2. Verify EventBridge rule is enabled and has correct event pattern
3. Test Lambda function manually with sample EventBridge event
4. Confirm CloudTrail is capturing relevant API calls

## Support

For issues and questions:

1. Check CloudWatch Logs for error details
2. Review AWS documentation for supported services
3. Validate IAM permissions and CloudTrail configuration
4. Test with known working resource creation scenarios

## License

This code is provided under the MIT License. See LICENSE file for details.