# Secure File Sharing with AWS Transfer Family Web Apps - CDK TypeScript

This CDK TypeScript application deploys a secure file sharing solution using AWS Transfer Family Web Apps, providing browser-based access to files stored in Amazon S3 with comprehensive audit logging.

## Architecture

The solution implements the following AWS services:

- **AWS Transfer Family Web Apps**: Browser-based file sharing interface
- **Amazon S3**: Secure object storage with encryption and lifecycle policies
- **AWS IAM Identity Center**: Centralized authentication and authorization
- **AWS CloudTrail**: Comprehensive audit logging for compliance
- **AWS KMS**: Customer-managed encryption keys for enhanced security
- **Amazon CloudWatch Logs**: Centralized log management and monitoring

## Security Features

- **Encryption at Rest**: KMS customer-managed keys with automatic rotation
- **Encryption in Transit**: SSL/TLS enforced for all connections
- **Access Controls**: Fine-grained IAM policies following least privilege
- **Audit Logging**: Complete CloudTrail logging of all file operations
- **Network Security**: Public access blocked on S3 bucket
- **Version Control**: S3 versioning enabled for data protection

## Prerequisites

- AWS CDK v2.166.0 or later
- Node.js 18.x or later
- AWS CLI configured with appropriate permissions
- IAM Identity Center enabled (manual step required)

## Deployment

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Configure AWS credentials**:
   ```bash
   aws configure
   # or use AWS_PROFILE environment variable
   ```

3. **Bootstrap CDK** (if first time in account/region):
   ```bash
   npx cdk bootstrap
   ```

4. **Synthesize CloudFormation template**:
   ```bash
   npm run synth
   ```

5. **Deploy the stack**:
   ```bash
   npm run deploy
   ```

6. **Enable IAM Identity Center** (manual step):
   - Navigate to IAM Identity Center in the AWS Console
   - Enable the service if not already enabled
   - Create users and groups as needed

## Configuration

The stack accepts several configuration parameters through CDK context:

```bash
# Deploy with custom configuration
npx cdk deploy -c bucketNamePrefix=mycompany-files -c environment=production
```

Available context parameters:
- `bucketNamePrefix`: Custom prefix for S3 bucket name
- `webAppName`: Custom name for Transfer Family web app
- `environment`: Environment tag (development/staging/production)
- `enableDetailedLogging`: Enable detailed CloudTrail data events (default: true)

## Usage

After deployment:

1. **Access the Web App**:
   - Use the `WebAppEndpoint` output URL from the CDK deployment
   - Users must be authenticated through IAM Identity Center

2. **File Operations**:
   - Upload files through the web interface
   - Download and manage existing files
   - All operations are logged in CloudTrail

3. **Monitor Activity**:
   - View audit logs in CloudTrail console
   - Monitor file access patterns in CloudWatch
   - Set up alerts for unusual activity

## Cost Optimization

The solution includes several cost optimization features:

- **S3 Lifecycle Policies**: Automatically transition files to cheaper storage classes
- **KMS Bucket Keys**: Reduce KMS costs for S3 encryption
- **Log Retention**: Configurable CloudWatch log retention periods
- **Right-sized Resources**: Minimal Transfer Family web app units

## Security Best Practices

This implementation follows AWS security best practices:

- **CDK Nag Integration**: Automatically validates security configurations
- **Least Privilege Access**: IAM roles have minimal required permissions
- **Encryption Everywhere**: All data encrypted at rest and in transit
- **Audit Trail**: Complete logging of all user and system actions
- **Network Isolation**: S3 bucket blocks all public access

## Monitoring and Alerting

Key metrics to monitor:

- **File Transfer Volume**: Track upload/download patterns
- **Authentication Failures**: Monitor failed login attempts  
- **Access Patterns**: Identify unusual file access behavior
- **Cost Metrics**: Monitor S3 and Transfer Family usage costs

## Cleanup

To destroy the stack and all resources:

```bash
npm run destroy
```

**Note**: The S3 bucket has a retention policy to prevent accidental deletion. Empty the bucket manually before running destroy if needed.

## Troubleshooting

Common issues and solutions:

1. **Identity Center Not Enabled**:
   - Manually enable IAM Identity Center in the AWS console
   - This cannot be automated through CDK

2. **Web App Access Issues**:
   - Verify user permissions in Identity Center
   - Check that users are assigned to the correct groups

3. **File Upload Failures**:
   - Verify Transfer Family role has correct S3 permissions
   - Check KMS key permissions for encryption

4. **High Costs**:
   - Review S3 storage classes and lifecycle policies
   - Monitor Transfer Family web app units scaling

## Support

For issues with this CDK implementation:

1. Check AWS CDK documentation: https://docs.aws.amazon.com/cdk/
2. Review AWS Transfer Family documentation: https://docs.aws.amazon.com/transfer/
3. Validate security configurations with CDK Nag reports

## License

This sample code is made available under the MIT-0 license. See the LICENSE file.