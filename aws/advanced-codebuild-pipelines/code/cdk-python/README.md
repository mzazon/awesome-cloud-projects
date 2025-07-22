# Advanced CodeBuild Pipeline - CDK Python Application

This AWS CDK Python application creates a sophisticated CI/CD pipeline using AWS CodeBuild with multi-stage builds, intelligent caching, and comprehensive artifact management.

## Features

- **Multi-Stage Build Pipeline**: Separate stages for dependencies, main build, and parallel architecture builds
- **Intelligent Caching**: S3-based caching for dependencies, Docker layers, and build artifacts
- **Container Registry**: ECR repository with vulnerability scanning and lifecycle policies
- **Build Orchestration**: Lambda-based pipeline orchestration with error handling
- **Cache Management**: Automated cache optimization and cleanup
- **Comprehensive Monitoring**: CloudWatch dashboards, alarms, and analytics
- **Security Best Practices**: IAM roles with least privilege, encryption at rest, and vulnerability scanning

## Architecture

The application deploys three main stacks:

1. **Storage Stack**: S3 buckets for caching and artifacts, ECR repository, IAM roles
2. **Pipeline Stack**: CodeBuild projects, Lambda orchestration, EventBridge automation
3. **Monitoring Stack**: CloudWatch dashboards, alarms, analytics, and notifications

## Prerequisites

- Python 3.8 or later
- AWS CLI v2 configured with appropriate permissions
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Docker installed (for local testing)

### Required AWS Permissions

The deployment requires permissions for:
- CodeBuild projects and builds
- S3 bucket creation and management
- ECR repository creation and management
- IAM role and policy creation
- Lambda function deployment
- CloudWatch dashboard and alarm creation
- EventBridge rule creation
- SNS topic creation

## Installation and Setup

1. **Clone and navigate to the project directory**:
   ```bash
   cd aws/advanced-codebuild-pipelines-multi-stage-caching-artifacts/code/cdk-python/
   ```

2. **Create and activate a virtual environment**:
   ```bash
   python -m venv .venv
   
   # On Windows
   .venv\Scripts\activate
   
   # On macOS/Linux
   source .venv/bin/activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Set environment variables** (optional, defaults will be used otherwise):
   ```bash
   export PROJECT_NAME="my-advanced-build"
   export ENVIRONMENT="dev"
   export NOTIFICATION_EMAIL="your-email@example.com"
   export ENABLE_PARALLEL_BUILDS="true"
   export ENABLE_SECURITY_SCANNING="true"
   export ENABLE_ANALYTICS="true"
   export BUILD_COMPUTE_TYPE="BUILD_GENERAL1_LARGE"
   export PARALLEL_ARCHITECTURES="amd64,arm64"
   export CACHE_RETENTION_DAYS="30"
   export ARTIFACT_RETENTION_DAYS="90"
   ```

## Deployment

1. **Bootstrap CDK** (if not already done):
   ```bash
   cdk bootstrap
   ```

2. **Review the deployment plan**:
   ```bash
   cdk diff
   ```

3. **Deploy all stacks**:
   ```bash
   cdk deploy --all
   ```

   Or deploy stacks individually:
   ```bash
   cdk deploy AdvancedCodeBuildStorage
   cdk deploy AdvancedCodeBuildPipeline
   cdk deploy AdvancedCodeBuildMonitoring
   ```

4. **Confirm deployment** when prompted and wait for completion.

## Configuration Options

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PROJECT_NAME` | `advanced-codebuild` | Name prefix for all resources |
| `ENVIRONMENT` | `dev` | Environment name (dev, staging, prod) |
| `NOTIFICATION_EMAIL` | None | Email for build notifications |
| `ENABLE_PARALLEL_BUILDS` | `true` | Enable parallel architecture builds |
| `ENABLE_SECURITY_SCANNING` | `true` | Enable security scanning in pipeline |
| `ENABLE_ANALYTICS` | `true` | Enable build analytics and reporting |
| `BUILD_COMPUTE_TYPE` | `BUILD_GENERAL1_LARGE` | CodeBuild compute type |
| `PARALLEL_ARCHITECTURES` | `amd64,arm64` | Architectures for parallel builds |
| `CACHE_RETENTION_DAYS` | `30` | Days to retain cache objects |
| `ARTIFACT_RETENTION_DAYS` | `90` | Days to retain artifact objects |

### Build Compute Types

Available options for `BUILD_COMPUTE_TYPE`:
- `BUILD_GENERAL1_SMALL` - 3 GB memory, 2 vCPUs
- `BUILD_GENERAL1_MEDIUM` - 7 GB memory, 4 vCPUs
- `BUILD_GENERAL1_LARGE` - 15 GB memory, 8 vCPUs
- `BUILD_GENERAL1_2XLARGE` - 145 GB memory, 72 vCPUs

## Usage

### Triggering Builds

1. **Using the orchestrator Lambda function**:
   ```bash
   aws lambda invoke \
       --function-name {project-name}-orchestrator-{environment} \
       --payload '{"buildConfig":{"sourceLocation":"s3://bucket/source.zip"}}' \
       response.json
   ```

2. **Directly starting CodeBuild projects**:
   ```bash
   aws codebuild start-build \
       --project-name {project-name}-main-{environment} \
       --source-location-override s3://bucket/source.zip
   ```

### Monitoring

1. **Access the CloudWatch dashboard**:
   - Navigate to CloudWatch in the AWS Console
   - Go to Dashboards section
   - Open "Advanced-CodeBuild-{project-name}-{environment}"

2. **View build logs**:
   ```bash
   aws logs describe-log-groups \
       --log-group-name-prefix "/aws/codebuild/{project-name}"
   ```

3. **Check analytics reports**:
   ```bash
   aws s3 ls s3://{project-name}-artifacts-{environment}-{account}/analytics/
   ```

### Cache Management

The cache is automatically managed through:
- Lifecycle policies on S3 buckets
- Automated cleanup Lambda function (runs daily)
- Manual cache optimization:
  ```bash
  aws lambda invoke \
      --function-name {project-name}-cache-manager-{environment} \
      --payload '{}' \
      response.json
  ```

## Development

### Project Structure

```
├── app.py                 # Main CDK application
├── cdk.json              # CDK configuration
├── requirements.txt      # Python dependencies
├── setup.py             # Package configuration
├── stacks/              # CDK stack definitions
│   ├── __init__.py
│   ├── storage_stack.py     # Storage infrastructure
│   ├── pipeline_stack.py    # Pipeline infrastructure
│   └── monitoring_stack.py  # Monitoring infrastructure
└── README.md            # This file
```

### Adding Custom Build Stages

1. **Extend the pipeline stack**:
   ```python
   # In stacks/pipeline_stack.py
   def _create_custom_build_project(self):
       # Add your custom build project configuration
   ```

2. **Update the orchestrator function**:
   ```python
   # Modify the Lambda code to include your custom stage
   ```

3. **Add monitoring widgets**:
   ```python
   # In stacks/monitoring_stack.py
   # Add CloudWatch widgets for your custom stage
   ```

### Testing

1. **Run unit tests**:
   ```bash
   python -m pytest tests/ -v
   ```

2. **Lint code**:
   ```bash
   pylint stacks/ app.py
   black --check .
   ```

3. **Type checking**:
   ```bash
   mypy stacks/ app.py
   ```

### Customization

#### Adding New Build Environments

1. Modify the `BuildEnvironment` configuration in pipeline_stack.py
2. Update environment variables as needed
3. Adjust compute types based on workload requirements

#### Extending Monitoring

1. Add custom metrics in the Lambda functions
2. Create additional CloudWatch widgets in monitoring_stack.py
3. Configure additional alarms for your specific use cases

#### Security Enhancements

1. Customize IAM policies for stricter permissions
2. Add additional encryption configurations
3. Implement VPC isolation if required

## Troubleshooting

### Common Issues

1. **CDK Bootstrap Issues**:
   ```bash
   cdk bootstrap --trust-self
   ```

2. **Permission Denied Errors**:
   - Verify AWS credentials have sufficient permissions
   - Check IAM policies for CodeBuild, S3, ECR, and Lambda

3. **Build Failures**:
   - Check CloudWatch logs for detailed error messages
   - Verify source code structure matches buildspec expectations
   - Ensure Docker is available for container builds

4. **Resource Limit Errors**:
   - Check AWS service quotas
   - Adjust compute types if hitting resource limits

### Log Analysis

Use CloudWatch Log Insights with pre-defined queries:
```bash
aws logs start-query \
    --log-group-name "/aws/codebuild/{project-name}-main-{environment}" \
    --start-time $(date -d '1 hour ago' +%s) \
    --end-time $(date +%s) \
    --query-string "fields @timestamp, @message | filter @message like /ERROR/"
```

## Cost Optimization

1. **Adjust retention periods** for caches and artifacts
2. **Use appropriate compute types** for your workload
3. **Enable S3 lifecycle policies** (automatically configured)
4. **Monitor usage** through the CloudWatch dashboard
5. **Clean up unused resources** regularly

## Security Considerations

- All S3 buckets have public access blocked
- IAM roles follow least privilege principle
- ECR repositories have vulnerability scanning enabled
- All data is encrypted at rest using AWS managed keys
- Build environments are isolated per project

## Cleanup

To delete all resources:

```bash
cdk destroy --all
```

**Warning**: This will delete all resources including S3 buckets, ECR repositories, and their contents.

## Support

For issues with this CDK application:
1. Check the CloudWatch logs for detailed error messages
2. Review the AWS CDK documentation
3. Consult the original recipe documentation
4. Check AWS service health dashboard

## Contributing

When contributing to this CDK application:
1. Follow Python PEP 8 style guidelines
2. Add unit tests for new functionality
3. Update documentation for any changes
4. Ensure all stacks can be deployed and destroyed cleanly

## License

This project is licensed under the Apache License 2.0 - see the LICENSE file for details.