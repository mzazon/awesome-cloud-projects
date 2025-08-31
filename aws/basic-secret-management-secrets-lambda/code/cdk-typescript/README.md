# Basic Secret Management with Secrets Manager and Lambda - CDK TypeScript

This CDK TypeScript application demonstrates secure secret management using AWS Secrets Manager and Lambda functions. It implements the architecture described in the "Basic Secret Management with Secrets Manager and Lambda" recipe.

## Architecture Overview

The application creates:
- **AWS Secrets Manager Secret**: Stores database credentials with automatic password generation
- **Lambda Function**: Retrieves secrets using the AWS Parameters and Secrets Extension
- **IAM Role**: Provides least-privilege access to the specific secret
- **CloudWatch Log Group**: Captures function execution logs with retention policy

## Features

- ✅ **Secure Secret Storage**: Uses AWS Secrets Manager with KMS encryption
- ✅ **Performance Optimized**: Leverages AWS Parameters and Secrets Lambda Extension for caching
- ✅ **Least Privilege IAM**: Grants minimal permissions required for operation
- ✅ **Automatic Password Generation**: Creates secure random passwords for secrets
- ✅ **Proper Error Handling**: Comprehensive error handling in Lambda function
- ✅ **CloudWatch Integration**: Structured logging with retention policies
- ✅ **Well-Architected**: Follows AWS security and reliability best practices

## Prerequisites

- Node.js 18.x or later
- AWS CLI configured with appropriate permissions
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- TypeScript installed (`npm install -g typescript`)

## Quick Start

1. **Install Dependencies**:
   ```bash
   npm install
   ```

2. **Bootstrap CDK** (if not done previously):
   ```bash
   cdk bootstrap
   ```

3. **Deploy the Stack**:
   ```bash
   npm run deploy
   ```

   Or manually:
   ```bash
   npm run build
   cdk deploy
   ```

4. **Test the Function**:
   ```bash
   aws lambda invoke \
     --function-name $(aws cloudformation describe-stacks \
       --stack-name SecretsManagerLambdaStack \
       --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
       --output text) \
     --payload '{}' \
     response.json
   
   cat response.json
   ```

## Useful Commands

- `npm run build` - Compile TypeScript to JavaScript
- `npm run watch` - Watch for changes and compile
- `npm run test` - Perform the Jest unit tests
- `cdk deploy` - Deploy this stack to your default AWS account/region
- `cdk diff` - Compare deployed stack with current state
- `cdk synth` - Emit the synthesized CloudFormation template
- `npm run destroy` - Destroy the stack

## Stack Outputs

After deployment, the stack provides these outputs:

- **SecretName**: Name of the created secret in AWS Secrets Manager
- **SecretArn**: ARN of the created secret
- **LambdaFunctionName**: Name of the Lambda function
- **LambdaFunctionArn**: ARN of the Lambda function
- **IAMRoleName**: Name of the IAM role used by Lambda
- **LogGroupName**: CloudWatch log group for function logs

## Configuration

The Lambda function is configured with these environment variables:

- `SECRET_NAME`: Name of the secret to retrieve
- `PARAMETERS_SECRETS_EXTENSION_CACHE_ENABLED`: Enable caching (true)
- `PARAMETERS_SECRETS_EXTENSION_CACHE_SIZE`: Cache size (1000)
- `PARAMETERS_SECRETS_EXTENSION_MAX_CONNECTIONS`: Max connections (3)
- `PARAMETERS_SECRETS_EXTENSION_HTTP_PORT`: Extension HTTP port (2773)

## Security Features

- **KMS Encryption**: All secrets encrypted at rest using AWS KMS
- **IAM Least Privilege**: Lambda role can only access the specific secret
- **No Hardcoded Credentials**: All sensitive data stored in Secrets Manager
- **Secure Password Generation**: Automatic generation of complex passwords
- **Extension-Based Retrieval**: Uses optimized AWS extension for performance

## Testing

The Lambda function returns a JSON response containing:
- Database connection information (excluding password for security)
- Success/error status
- Caching information
- Execution metadata

Example response:
```json
{
  "statusCode": 200,
  "body": {
    "message": "Secret retrieved successfully",
    "database_host": "mydb.cluster-xyz.us-east-1.rds.amazonaws.com",
    "database_name": "production",
    "username": "appuser",
    "extension_cache": "Enabled with 300s TTL",
    "note": "Password retrieved but not displayed for security"
  }
}
```

## Monitoring

The application includes:
- CloudWatch log group with 1-week retention
- Structured logging in Lambda function
- Error tracking and reporting
- Performance monitoring through extension metrics

## Cleanup

To remove all resources:

```bash
npm run destroy
```

Or manually:
```bash
cdk destroy
```

This will delete:
- Lambda function and its log group
- IAM role and policies
- Secrets Manager secret (with immediate deletion)
- All associated resources

## Customization

To customize the deployment:

1. **Modify Secret Structure**: Edit the `generateSecretString` configuration in `lib/secrets-manager-lambda-stack.ts`
2. **Adjust Lambda Settings**: Change memory, timeout, or environment variables in the stack
3. **Update IAM Permissions**: Modify the IAM role if additional permissions are needed
4. **Change Naming**: Update resource names by modifying the `uniqueSuffix` logic

## Cost Optimization

This application is designed for minimal cost:
- Secrets Manager: ~$0.40/month per secret
- Lambda: Pay per invocation (first 1M requests free)
- CloudWatch Logs: Minimal logging with retention policy
- No continuous charges for idle resources

## Security Best Practices

The implementation follows these security practices:
- Principle of least privilege for IAM permissions
- Encryption at rest and in transit
- No sensitive data in logs or outputs
- Secure random password generation
- Extension-based secret retrieval for performance

## Support

For issues or questions:
- Review AWS Secrets Manager documentation
- Check CloudWatch logs for error details
- Validate IAM permissions and resource access
- Ensure proper AWS CLI configuration

## License

This sample code is made available under the MIT license.