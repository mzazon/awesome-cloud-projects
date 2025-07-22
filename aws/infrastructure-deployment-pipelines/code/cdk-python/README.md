# Infrastructure Deployment Pipeline - CDK Python

This is a complete AWS CDK Python application that implements an automated infrastructure deployment pipeline using AWS CodePipeline, CodeCommit, and CodeBuild.

## Architecture Overview

The application creates a self-updating CI/CD pipeline that:

- **Source Control**: Uses AWS CodeCommit for version control
- **Build Process**: Employs AWS CodeBuild for testing and synthesis
- **Multi-Environment Deployment**: Supports development and production stages
- **Approval Gates**: Requires manual approval for production deployments
- **Monitoring**: Includes CloudWatch alarms and SNS notifications
- **Security**: Implements security scanning and validation steps

## Project Structure

```
├── app.py                 # Main CDK application entry point
├── requirements.txt       # Python dependencies
├── setup.py              # Package setup configuration
├── cdk.json              # CDK configuration
├── README.md             # This file
├── tests/                # Unit tests (to be created)
└── integration_tests/    # Integration tests (to be created)
```

## Prerequisites

- AWS CLI configured with appropriate permissions
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- Python 3.8 or higher
- Git for version control

## Installation

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd infrastructure-deployment-pipelines-cdk-codepipeline/code/cdk-python
   ```

2. **Create a virtual environment**:
   ```bash
   python -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Bootstrap CDK** (if not already done):
   ```bash
   cdk bootstrap
   ```

## Configuration

Set the following environment variables before deployment:

```bash
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export REPO_NAME=infrastructure-pipeline-$(date +%s)
```

## Deployment

1. **Deploy the pipeline**:
   ```bash
   cdk deploy InfrastructurePipelineStack
   ```

2. **Push code to trigger pipeline**:
   ```bash
   # Initialize git repository
   git init
   git add .
   git commit -m "Initial commit"
   
   # Add remote origin (use the repository URL from CDK output)
   git remote add origin <codecommit-repository-url>
   git push -u origin main
   ```

## Pipeline Stages

### 1. Source Stage
- Monitors CodeCommit repository for changes
- Triggers on commits to the main branch

### 2. Build Stage
- Installs Python dependencies
- Runs unit tests with pytest
- Performs security scanning with bandit and safety
- Synthesizes CDK templates

### 3. Development Stage
- Validates infrastructure configuration
- Deploys to development environment
- Runs integration tests

### 4. Production Stage
- Requires manual approval
- Validates production readiness
- Deploys to production environment
- Performs post-deployment verification

## Application Components

### Infrastructure Stack (`ApplicationStack`)

The application stack includes:

- **S3 Bucket**: For static assets with versioning and encryption
- **DynamoDB Table**: For application data with pay-per-request billing
- **Lambda Function**: For API processing with environment-specific configuration
- **CloudWatch Dashboard**: For monitoring and observability
- **IAM Roles**: With least privilege access policies

### Pipeline Stack (`PipelineStack`)

The pipeline stack provides:

- **CodeCommit Repository**: Git-based source control
- **CodePipeline**: Orchestrates the CI/CD workflow
- **CodeBuild Projects**: Handles building and testing
- **SNS Topic**: For notifications and alerts
- **CloudWatch Alarms**: For pipeline failure monitoring

## Testing

### Unit Tests

Run unit tests with:
```bash
python -m pytest tests/ -v
```

### Integration Tests

Run integration tests with:
```bash
python -m pytest integration_tests/ -v
```

### Security Scanning

Run security scans with:
```bash
# Python security scanning
bandit -r . -f json

# Dependency vulnerability scanning
safety check
```

## Monitoring

The pipeline includes comprehensive monitoring:

- **CloudWatch Metrics**: For pipeline execution and application performance
- **CloudWatch Alarms**: For failure detection and alerting
- **SNS Notifications**: For pipeline status updates
- **CloudWatch Dashboards**: For visualization and monitoring

## Security Features

- **Encryption**: All data encrypted at rest and in transit
- **IAM Policies**: Least privilege access controls
- **Security Scanning**: Automated security vulnerability detection
- **Approval Gates**: Manual approval required for production
- **Audit Logging**: Complete audit trail of all changes

## Cost Optimization

- **Pay-per-request**: DynamoDB uses on-demand billing
- **Spot Instances**: CodeBuild uses cost-effective compute when possible
- **Resource Tagging**: All resources tagged for cost allocation
- **Lifecycle Policies**: Automatic cleanup of temporary resources

## Troubleshooting

### Common Issues

1. **Pipeline Fails to Start**:
   - Check CodeCommit repository permissions
   - Verify CDK bootstrap was completed
   - Ensure IAM roles have sufficient permissions

2. **Build Failures**:
   - Check Python dependencies in requirements.txt
   - Verify test files are present and executable
   - Review CodeBuild logs in CloudWatch

3. **Deployment Failures**:
   - Check CloudFormation stack events
   - Verify resource limits and quotas
   - Review IAM permissions for deployment roles

### Debugging

Enable debug logging:
```bash
export CDK_DEBUG=true
cdk deploy --verbose
```

View pipeline execution:
```bash
aws codepipeline get-pipeline-state --pipeline-name InfrastructurePipeline
```

## Cleanup

To remove all resources:

```bash
# Delete the pipeline stack
cdk destroy InfrastructurePipelineStack

# Delete any remaining application stacks
cdk destroy --all
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Run the full test suite
6. Submit a pull request

## License

This project is licensed under the Apache-2.0 License. See the LICENSE file for details.

## Support

For issues and questions:
- Check the troubleshooting section above
- Review AWS CDK documentation
- Open an issue in the repository
- Contact the development team

## Additional Resources

- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/)
- [AWS CodePipeline User Guide](https://docs.aws.amazon.com/codepipeline/latest/userguide/)
- [AWS CodeCommit User Guide](https://docs.aws.amazon.com/codecommit/latest/userguide/)
- [AWS CodeBuild User Guide](https://docs.aws.amazon.com/codebuild/latest/userguide/)