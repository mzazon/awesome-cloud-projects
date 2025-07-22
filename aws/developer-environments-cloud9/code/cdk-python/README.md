# AWS Cloud9 Developer Environment - CDK Python

This CDK Python application creates a comprehensive AWS Cloud9 developer environment with team collaboration features, IAM roles, CodeCommit integration, and monitoring capabilities.

## Architecture

The CDK application provisions:

- **AWS Cloud9 EC2 Environment**: Browser-based IDE with configurable instance type
- **IAM Role & Policies**: Secure permissions for development tasks
- **CodeCommit Repository**: Team collaboration and version control
- **CloudWatch Monitoring**: Performance metrics and dashboards
- **VPC Configuration**: Network security and isolation
- **Instance Profile**: EC2 instance permissions

## Prerequisites

- Python 3.8 or later
- AWS CLI configured with appropriate permissions
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Virtual environment (recommended)

## Installation

1. **Set up virtual environment:**
   ```bash
   python -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

2. **Install dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

3. **Install development dependencies (optional):**
   ```bash
   pip install -e ".[dev]"
   ```

## Configuration

The application can be customized using CDK context values in `cdk.json` or via command line:

### Available Context Variables

- `environmentName`: Name for the Cloud9 environment (default: "dev-environment")
- `instanceType`: EC2 instance type (default: "t3.medium")
- `autoStopMinutes`: Auto-hibernation timeout in minutes (default: "60")
- `repositoryName`: CodeCommit repository name (default: "team-development-repo")

### Custom Configuration Example

```bash
# Deploy with custom settings
cdk deploy \
  --context environmentName="my-dev-env" \
  --context instanceType="t3.large" \
  --context autoStopMinutes="120"
```

## Deployment

1. **Bootstrap CDK (first time only):**
   ```bash
   cdk bootstrap
   ```

2. **Deploy the stack:**
   ```bash
   cdk deploy
   ```

3. **Review and confirm deployment:**
   The deployment will create resources including EC2 instances, IAM roles, and CodeCommit repositories.

## Usage

### Accessing the Cloud9 Environment

1. Navigate to the AWS Cloud9 console
2. Find your environment by name (from `environmentName` context)
3. Click "Open IDE" to access the browser-based development environment

### Repository Integration

The deployed CodeCommit repository can be cloned into the Cloud9 environment:

```bash
# Inside Cloud9 terminal
git clone https://git-codecommit.REGION.amazonaws.com/v1/repos/REPOSITORY_NAME
```

### Monitoring

Access the CloudWatch dashboard to monitor:
- CPU utilization
- Network traffic
- Instance health

## Development

### Code Structure

```
.
├── app.py                 # Main CDK application
├── requirements.txt       # Python dependencies
├── setup.py              # Package configuration
├── cdk.json              # CDK configuration
└── README.md             # This file
```

### Key Components

- **Cloud9DeveloperEnvironmentStack**: Main CDK stack class
- **IAM Role Creation**: Secure permissions for development
- **CodeCommit Integration**: Team collaboration repository
- **Monitoring Setup**: CloudWatch dashboards and metrics

### Local Development

1. **Install in development mode:**
   ```bash
   pip install -e ".[dev]"
   ```

2. **Run code formatting:**
   ```bash
   black app.py
   ```

3. **Run type checking:**
   ```bash
   mypy app.py
   ```

4. **Run linting:**
   ```bash
   flake8 app.py
   ```

## Customization

### Instance Types

Supported instance types for Cloud9:
- `t3.micro`, `t3.small`, `t3.medium`, `t3.large`
- `t2.micro`, `t2.small`, `t2.medium`, `t2.large`
- `m5.large`, `m5.xlarge`, `c5.large`, `c5.xlarge`

### IAM Permissions

The default IAM role includes permissions for:
- S3 bucket operations
- DynamoDB table operations
- Lambda function management
- CloudWatch logging and metrics
- Systems Manager (SSM) session management

Add custom permissions by modifying the `_create_cloud9_iam_role()` method.

### Environment Variables

Set environment variables in the Cloud9 environment:

```bash
# Example environment setup
export AWS_DEFAULT_REGION=us-east-1
export NODE_ENV=development
export PYTHONPATH=/home/ec2-user/environment:$PYTHONPATH
```

## Troubleshooting

### Common Issues

1. **Deployment Fails**: Ensure AWS CLI is configured and you have necessary permissions
2. **Cloud9 Won't Start**: Check instance type availability in your region
3. **CodeCommit Access**: Verify IAM permissions for Git operations

### Logs and Debugging

- Check CloudFormation stack events in AWS Console
- Review Cloud9 environment logs in CloudWatch
- Use `cdk diff` to see changes before deployment

### Stack Updates

To update the stack with new configuration:

```bash
cdk diff    # Review changes
cdk deploy  # Apply updates
```

## Cleanup

Remove all resources when no longer needed:

```bash
cdk destroy
```

**Warning**: This will permanently delete the Cloud9 environment and all associated resources.

## Security Considerations

- IAM roles follow principle of least privilege
- Environment automatically stops after configured timeout
- VPC provides network isolation
- CodeCommit repositories use IAM-based access control

## Cost Optimization

- Use smaller instance types for basic development
- Enable auto-stop to prevent unnecessary charges
- Monitor usage via CloudWatch dashboards
- Consider Spot instances for non-critical development

## Support

For issues related to:
- **CDK**: [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- **Cloud9**: [AWS Cloud9 User Guide](https://docs.aws.amazon.com/cloud9/latest/user-guide/)
- **CodeCommit**: [AWS CodeCommit User Guide](https://docs.aws.amazon.com/codecommit/latest/userguide/)

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.