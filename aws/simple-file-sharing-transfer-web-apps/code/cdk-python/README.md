# Simple File Sharing with Transfer Family Web Apps - CDK Python

This CDK Python application creates a secure, browser-based file sharing solution using AWS Transfer Family Web Apps integrated with S3 storage, IAM Identity Center authentication, and S3 Access Grants for fine-grained permissions.

## Architecture Overview

The solution deploys the following components:

- **S3 Bucket**: Secure file storage with versioning, encryption, and access controls
- **IAM Roles**: Proper permissions for Transfer Family and S3 Access Grants integration
- **Transfer Family Web App**: Fully managed, browser-based file sharing interface
- **S3 Access Grants**: Fine-grained, temporary access controls
- **IAM Identity Center Integration**: Centralized user authentication and management
- **Demo User**: Optional test user for validating the solution

## Prerequisites

Before deploying this CDK application, ensure you have:

1. **AWS Account**: Administrative permissions for Transfer Family, S3, and IAM Identity Center
2. **AWS CLI**: Version 2.x installed and configured
3. **Python**: Version 3.8 or higher
4. **Node.js**: Version 18.x or higher (required for CDK CLI)
5. **CDK CLI**: Version 2.150.0 or higher
6. **IAM Identity Center**: Must be enabled in your AWS account

### Enable IAM Identity Center

If IAM Identity Center is not enabled in your account:

1. Go to [AWS Console - IAM Identity Center](https://console.aws.amazon.com/singlesignon/)
2. Click "Enable" and follow the setup wizard
3. Note the Instance ARN and Identity Store ID for configuration

## Installation

1. **Clone and navigate to the project directory**:
   ```bash
   cd aws/simple-file-sharing-transfer-web-apps/code/cdk-python/
   ```

2. **Create and activate a Python virtual environment**:
   ```bash
   python -m venv .venv
   
   # On macOS/Linux
   source .venv/bin/activate
   
   # On Windows
   .venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Install CDK CLI** (if not already installed):
   ```bash
   npm install -g aws-cdk@latest
   ```

5. **Bootstrap CDK** (if not already done in your account/region):
   ```bash
   cdk bootstrap
   ```

## Configuration

### Method 1: Environment Variables

Set the required configuration using environment variables:

```bash
# Required: IAM Identity Center configuration
export IDENTITY_CENTER_INSTANCE_ARN="arn:aws:sso:::instance/ssoins-xxxxxxxxxx"
export IDENTITY_STORE_ID="d-xxxxxxxxxx"

# Optional: Control demo user creation
export CREATE_DEMO_USER="true"
```

### Method 2: CDK Context

Alternatively, pass configuration via CDK context:

```bash
cdk deploy -c identity_center_instance_arn=arn:aws:sso:::instance/ssoins-xxxxxxxxxx \
           -c identity_store_id=d-xxxxxxxxxx \
           -c create_demo_user=true
```

### Method 3: Modify cdk.json

Edit the `cdk.json` file to include your configuration:

```json
{
  "context": {
    "identity_center_instance_arn": "arn:aws:sso:::instance/ssoins-xxxxxxxxxx",
    "identity_store_id": "d-xxxxxxxxxx",
    "create_demo_user": true
  }
}
```

## Deployment

### Quick Deploy

Deploy the entire solution with default settings:

```bash
cdk deploy
```

### Deployment with Configuration

Deploy with specific configuration:

```bash
cdk deploy -c identity_center_instance_arn=your-instance-arn \
           -c identity_store_id=your-identity-store-id
```

### Preview Changes

Review what will be deployed before making changes:

```bash
cdk diff
```

### Deploy to Specific Account/Region

```bash
cdk deploy --profile your-profile \
           --region us-east-1
```

## Getting Started

After successful deployment:

1. **Find the Web App Access Endpoint**:
   - Check the CloudFormation output `TransferWebAppAccessEndpoint`
   - Or use AWS CLI: `aws transfer describe-web-app --web-app-id YOUR_WEB_APP_ID`

2. **Set Password for Demo User** (if created):
   - Go to [IAM Identity Center Console](https://console.aws.amazon.com/singlesignon/)
   - Navigate to Users and find the demo user
   - Set a password for the user

3. **Access the File Sharing Interface**:
   - Open the access endpoint URL in a browser
   - Login with the demo user credentials
   - Upload, download, and manage files through the web interface

## Usage Examples

### Upload Files

1. Navigate to the web app access endpoint
2. Sign in with your IAM Identity Center credentials
3. Use the intuitive web interface to upload files
4. Files support up to 160 GB per file with progress tracking

### Download Files

1. Browse available files in the web interface
2. Click on files to download them directly
3. Use search functionality to find specific files

### Folder Operations

1. Create folders to organize files
2. Navigate through folder structures
3. Upload files directly into specific folders

## Architecture Details

### Security Features

- **Encryption**: All data encrypted at rest and in transit
- **Access Control**: Fine-grained permissions through S3 Access Grants
- **Authentication**: Integration with IAM Identity Center for SSO
- **Network Security**: CORS configuration for secure cross-origin requests
- **Audit Trail**: All activities logged through AWS CloudTrail

### Cost Optimization

- **Serverless**: No infrastructure to manage or pay for when not in use
- **S3 Intelligent Tiering**: Automatic cost optimization for infrequently accessed files
- **Pay-per-use**: Transfer Family charges only for active usage

### High Availability

- **Multi-AZ**: Built on AWS's highly available infrastructure
- **Auto-scaling**: Automatically scales to handle varying workloads
- **Durability**: S3 provides 99.999999999% (11 9's) durability

## Customization

### Adding More Users

```python
# Create additional users through IAM Identity Center
# Then create access grants for each user
additional_user = self._create_demo_user(identity_store_id, "user2")
additional_grant = self._create_access_grant(identity_store_id, additional_user)
```

### Custom Branding

The web app supports custom branding through AWS Transfer Family configuration:

```python
web_app = transfer.CfnWebApp(
    self,
    "TransferFamilyWebApp",
    # Add custom domain and branding options
)
```

### Advanced Permissions

Configure different access levels using S3 Access Grants:

```python
# Read-only access grant
readonly_grant = s3control.CfnAccessGrant(
    self,
    "ReadOnlyGrant",
    permission="READ",
    # ... other configuration
)
```

## Monitoring and Troubleshooting

### CloudWatch Metrics

Monitor the solution using AWS CloudWatch:

- Transfer Family metrics for web app usage
- S3 metrics for storage utilization
- IAM Identity Center metrics for authentication

### Logs

Access logs through:

- AWS CloudTrail for API activity
- Transfer Family logs for user actions
- CloudWatch Logs for custom resource operations

### Common Issues

1. **IAM Identity Center Not Enabled**:
   - Enable IAM Identity Center in your account
   - Verify the instance ARN and identity store ID

2. **Permission Errors**:
   - Ensure your deployment role has necessary permissions
   - Check IAM policies for Transfer Family and S3 Access Grants

3. **CORS Issues**:
   - Verify the web app endpoint is correctly configured in S3 CORS
   - Check browser developer tools for CORS errors

## Clean Up

### Remove All Resources

```bash
cdk destroy
```

### Confirm Deletion

The command will show you what resources will be deleted and ask for confirmation.

### Manual Cleanup

Some resources may require manual cleanup:

- IAM Identity Center users (if created outside CDK)
- S3 Access Grants instances (managed by AWS)

## Development

### Running Tests

```bash
# Install development dependencies
pip install -e .[dev]

# Run tests
pytest

# Run with coverage
pytest --cov=app
```

### Code Formatting

```bash
# Format code
black app.py

# Lint code
flake8 app.py

# Type checking
mypy app.py
```

### Security Scanning

```bash
# Security scanning
bandit -r app.py
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Run the test suite
6. Submit a pull request

## License

This project is licensed under the Apache License 2.0 - see the LICENSE file for details.

## Support

For issues and questions:

1. Check the troubleshooting section above
2. Review AWS Transfer Family documentation
3. Open an issue in the project repository
4. Contact AWS Support for service-specific issues

## Additional Resources

- [AWS Transfer Family Web Apps User Guide](https://docs.aws.amazon.com/transfer/latest/userguide/web-app.html)
- [S3 Access Grants Documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-grants.html)
- [IAM Identity Center User Guide](https://docs.aws.amazon.com/singlesignon/latest/userguide/)
- [AWS CDK Python Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/work-with-cdk-python.html)