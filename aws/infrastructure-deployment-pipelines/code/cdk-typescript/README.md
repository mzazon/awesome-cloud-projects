# Infrastructure Deployment Pipelines with CDK and CodePipeline

This CDK TypeScript application demonstrates how to build automated infrastructure deployment pipelines using AWS CDK and CodePipeline. The solution provides a complete CI/CD pipeline for infrastructure as code with automated testing, multi-environment deployment, and comprehensive monitoring.

## Architecture Overview

The application includes two main pipeline implementations:

1. **Basic Pipeline Stack** (`PipelineStack`): A traditional CodePipeline implementation with CodeCommit, CodeBuild, and multiple deployment stages
2. **Advanced Pipeline Stack** (`AdvancedPipelineStack`): A CDK Pipeline implementation with self-mutating capabilities and comprehensive testing

## Features

### Pipeline Capabilities
- **Source Control**: CodeCommit repository with event-driven triggers
- **Build & Test**: Automated CDK synthesis, testing, and security scanning
- **Multi-Environment Deployment**: Separate dev, staging, and production environments
- **Manual Approval Gates**: Human review for production deployments
- **Self-Mutating Pipelines**: Automatic pipeline updates when configuration changes
- **Rollback Support**: Automated rollback capabilities for failed deployments

### Monitoring & Governance
- **CloudWatch Alarms**: Pipeline failure detection and notifications
- **CloudTrail Audit**: Complete audit trail for all pipeline activities
- **SNS Notifications**: Real-time alerts for pipeline events
- **Cost Optimization**: Resource tagging and environment-specific configurations

### Security Features
- **IAM Roles**: Least privilege access for all pipeline components
- **Encrypted Artifacts**: S3 encryption for build artifacts
- **Security Scanning**: Automated vulnerability assessment
- **Cross-Account Support**: Ready for multi-account deployments

## Project Structure

```
├── app.ts                          # Main CDK application entry point
├── lib/
│   ├── pipeline-stack.ts           # Basic pipeline implementation
│   ├── advanced-pipeline-stack.ts  # CDK Pipeline implementation
│   └── application-stack.ts        # Sample application stack
├── test/
│   ├── pipeline-stack.test.ts      # Pipeline stack tests
│   └── application-stack.test.ts   # Application stack tests
├── package.json                    # Dependencies and scripts
├── tsconfig.json                   # TypeScript configuration
├── cdk.json                        # CDK configuration
└── README.md                       # This file
```

## Prerequisites

- AWS CLI installed and configured
- Node.js 18+ and npm
- AWS CDK CLI v2 installed globally
- AWS account with appropriate permissions

## Installation

1. **Install dependencies:**
   ```bash
   npm install
   ```

2. **Install CDK CLI globally (if not already installed):**
   ```bash
   npm install -g aws-cdk
   ```

3. **Bootstrap CDK environment:**
   ```bash
   cdk bootstrap
   ```

## Usage

### Deploy Basic Pipeline

```bash
# Synthesize CloudFormation templates
npm run synth

# Deploy the basic pipeline stack
cdk deploy InfrastructureDeploymentPipeline

# Get repository clone URL from outputs
aws cloudformation describe-stacks \
  --stack-name InfrastructureDeploymentPipeline \
  --query 'Stacks[0].Outputs[?OutputKey==`RepositoryCloneUrl`].OutputValue' \
  --output text
```

### Deploy Advanced Pipeline

```bash
# Deploy the advanced pipeline stack
cdk deploy AdvancedPipelineStack

# Get repository clone URL
aws cloudformation describe-stacks \
  --stack-name AdvancedPipelineStack \
  --query 'Stacks[0].Outputs[?OutputKey==`RepositoryCloneUrl`].OutputValue' \
  --output text
```

### Initialize Repository

```bash
# Clone the repository
git clone <repository-clone-url>
cd <repository-name>

# Copy CDK application files to repository
cp -r /path/to/cdk-typescript/* .

# Initial commit
git add .
git commit -m "Initial CDK application setup"
git push origin main
```

## Testing

Run the test suite to ensure everything works correctly:

```bash
# Run all tests
npm test

# Run tests in watch mode
npm run test:watch

# Run linting
npm run lint

# Fix linting issues
npm run lint:fix
```

## Pipeline Workflow

### Basic Pipeline Flow

1. **Source Stage**: Triggered by commits to CodeCommit repository
2. **Build Stage**: CDK synthesis and application testing
3. **Deploy-Dev Stage**: Automatic deployment to development environment
4. **Approval Stage**: Manual approval gate for production
5. **Deploy-Prod Stage**: Deployment to production environment

### Advanced Pipeline Flow

1. **Source Stage**: Code checkout from repository
2. **Build Stage**: Synthesis with security scanning and testing
3. **Development Stage**: Auto-deploy with integration tests
4. **Staging Stage**: Manual approval + load testing
5. **Production Stage**: Final approval + production deployment + validation

## Configuration

### Environment Variables

The pipeline supports the following environment variables:

- `CDK_DEFAULT_ACCOUNT`: AWS account ID
- `CDK_DEFAULT_REGION`: AWS region
- `ENVIRONMENT`: Target environment (dev, staging, prod)

### Customization

Modify the following files to customize the pipeline:

- `lib/pipeline-stack.ts`: Basic pipeline configuration
- `lib/advanced-pipeline-stack.ts`: Advanced pipeline settings
- `lib/application-stack.ts`: Application infrastructure
- `cdk.json`: CDK runtime configuration

## Monitoring

### CloudWatch Dashboards

The pipeline creates CloudWatch alarms for:
- Pipeline execution failures
- Build failures
- Deployment failures

### Notifications

SNS topics are configured for:
- Pipeline state changes
- Manual approval requests
- Error notifications

### Audit Logging

CloudTrail provides audit logs for:
- Pipeline executions
- CodeCommit activities
- CloudFormation deployments

## Troubleshooting

### Common Issues

1. **Bootstrap Required**: Ensure CDK is bootstrapped in your account/region
2. **Permission Errors**: Check IAM roles and policies
3. **Build Failures**: Review CodeBuild logs in CloudWatch
4. **Deployment Failures**: Check CloudFormation events

### Debug Commands

```bash
# Check pipeline status
aws codepipeline get-pipeline-state --name <pipeline-name>

# View build logs
aws logs get-log-events --log-group-name /aws/codebuild/<project-name>

# Check stack events
aws cloudformation describe-stack-events --stack-name <stack-name>
```

## Security Considerations

- Use least privilege IAM policies
- Enable CloudTrail for audit logging
- Encrypt artifacts at rest and in transit
- Regularly rotate access keys and secrets
- Monitor for security vulnerabilities

## Cost Optimization

- Use appropriate instance sizes for CodeBuild
- Implement lifecycle policies for artifacts
- Tag resources for cost allocation
- Monitor usage with AWS Cost Explorer

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For questions or issues:
- Review the CDK documentation
- Check AWS CodePipeline documentation
- Open an issue in the repository
- Contact the development team

## Additional Resources

- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [CodePipeline User Guide](https://docs.aws.amazon.com/codepipeline/)
- [CDK Pipelines Documentation](https://docs.aws.amazon.com/cdk/v2/guide/cdk_pipeline.html)
- [Infrastructure as Code Best Practices](https://docs.aws.amazon.com/whitepapers/latest/introduction-devops-aws/infrastructure-as-code.html)