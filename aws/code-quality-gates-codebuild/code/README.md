# Infrastructure as Code for Code Quality Gates with CodeBuild

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Code Quality Gates with CodeBuild".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured
- Appropriate AWS permissions for CodeBuild, S3, IAM, SNS, Systems Manager, and CloudWatch
- For CDK implementations: Node.js 16+ or Python 3.8+
- For Terraform: Terraform 1.0+ installed
- GitHub repository with sample application code (optional for testing)

## Architecture Overview

This infrastructure deploys a comprehensive code quality gate system that includes:

- **CodeBuild Project**: Executes quality gate pipeline with multiple phases
- **S3 Bucket**: Stores source code, build artifacts, and quality reports
- **IAM Role**: Provides CodeBuild with necessary permissions
- **SNS Topic**: Sends notifications for quality gate results
- **Systems Manager Parameters**: Stores quality gate thresholds
- **CloudWatch Dashboard**: Monitors quality gate metrics and logs

## Quick Start

### Using CloudFormation
```bash
aws cloudformation create-stack \
    --stack-name quality-gates-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ProjectName,ParameterValue=my-quality-gates \
                 ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install
npm run build
cdk deploy --parameters notificationEmail=your-email@example.com
```

### Using CDK Python
```bash
cd cdk-python/
pip install -r requirements.txt
cdk deploy --parameters notificationEmail=your-email@example.com
```

### Using Terraform
```bash
cd terraform/
terraform init
terraform plan -var="notification_email=your-email@example.com"
terraform apply -var="notification_email=your-email@example.com"
```

### Using Bash Scripts
```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh your-email@example.com
```

## Configuration Parameters

### Quality Gate Thresholds
- **Coverage Threshold**: Minimum code coverage percentage (default: 80%)
- **SonarQube Quality Gate**: Required SonarQube status (default: ERROR)
- **Security Threshold**: Maximum security vulnerability level (default: HIGH)

### Infrastructure Parameters
- **Project Name**: Name for CodeBuild project and related resources
- **Notification Email**: Email address for quality gate notifications
- **AWS Region**: Target AWS region for deployment
- **Compute Type**: CodeBuild compute instance type (default: BUILD_GENERAL1_MEDIUM)

## Sample Application

The infrastructure includes a sample Java Maven application with:
- Calculator class with comprehensive functionality
- JUnit 5 test suite achieving high code coverage
- Maven configuration for JaCoCo and SonarQube integration
- Buildspec.yml with multi-phase quality gates

## Quality Gate Phases

The implemented quality gate pipeline includes:

1. **Compilation & Unit Tests**: Validates code compiles and unit tests pass
2. **Code Coverage Analysis**: Ensures minimum coverage thresholds are met
3. **Static Code Analysis**: Performs SonarQube analysis for code quality
4. **Security Scanning**: Checks for known vulnerabilities using OWASP Dependency Check
5. **Integration Tests**: Executes integration test suite
6. **Quality Gate Summary**: Validates all gates passed and sends notifications

## Monitoring and Observability

### CloudWatch Dashboard
- Build success/failure metrics
- Build duration trends
- Quality gate event logs
- Real-time build status

### SNS Notifications
- Quality gate success notifications
- Failure alerts with specific reasons
- Build completion status updates

### S3 Artifacts
- Quality reports (coverage, security)
- Build artifacts and logs
- Cached dependencies for performance

## Cleanup

### Using CloudFormation
```bash
aws cloudformation delete-stack --stack-name quality-gates-stack
```

### Using CDK
```bash
cdk destroy
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Customization

### Adjusting Quality Thresholds
Modify the Systems Manager parameters to change quality gate requirements:
- `/quality-gates/coverage-threshold`: Code coverage percentage
- `/quality-gates/sonar-quality-gate`: SonarQube quality gate status
- `/quality-gates/security-threshold`: Security vulnerability level

### Adding Custom Quality Checks
Extend the buildspec.yml to include additional quality gates:
- Code complexity analysis
- Documentation coverage
- Performance benchmarks
- Architecture compliance checks

### Multi-Language Support
Adapt the buildspec.yml for different programming languages:
- Python: pytest, coverage, bandit
- Node.js: jest, nyc, npm audit
- .NET: dotnet test, coverlet, security code scan

## Best Practices

### Security
- Use least privilege IAM permissions
- Enable S3 bucket encryption
- Rotate SNS topic access keys regularly
- Monitor CloudWatch logs for security events

### Performance
- Utilize S3 caching for build dependencies
- Optimize Docker images for faster builds
- Use appropriate CodeBuild compute types
- Implement parallel test execution

### Cost Optimization
- Use S3 lifecycle policies for artifact cleanup
- Monitor CodeBuild usage patterns
- Implement build timeout limits
- Use spot instances for non-critical builds

## Troubleshooting

### Common Issues

1. **Build Failures**: Check CloudWatch logs for detailed error messages
2. **Permission Errors**: Verify IAM role has required permissions
3. **Quality Gate Failures**: Review quality reports in S3 bucket
4. **Notification Issues**: Confirm SNS topic subscription is confirmed

### Debug Commands
```bash
# Check build logs
aws logs describe-log-groups --log-group-name-prefix "/aws/codebuild/"

# View quality gate parameters
aws ssm get-parameters --names "/quality-gates/coverage-threshold" \
    "/quality-gates/sonar-quality-gate" "/quality-gates/security-threshold"

# List build artifacts
aws s3 ls s3://your-bucket-name/artifacts/ --recursive

# Check SNS topic subscriptions
aws sns list-subscriptions-by-topic --topic-arn your-topic-arn
```

## Advanced Features

### Integration with CI/CD Pipelines
- Connect to AWS CodePipeline for automated triggers
- Integrate with GitHub Actions or GitLab CI
- Use CodeCommit webhooks for automatic builds

### Quality Trend Analysis
- Export metrics to Amazon QuickSight
- Create custom CloudWatch metrics
- Implement quality trend dashboards

### Automated Remediation
- Lambda functions for automatic issue resolution
- CodeGuru integration for performance insights
- Automated dependency updates

## Support

For issues with this infrastructure code, refer to:
- Original recipe documentation
- AWS CodeBuild documentation
- Provider-specific documentation for each IaC tool
- Quality gate tool documentation (SonarQube, OWASP, etc.)

## Cost Estimation

Estimated monthly costs (us-east-1):
- CodeBuild: $5-15 (depends on build frequency and duration)
- S3: $1-5 (depends on artifact storage and retention)
- SNS: <$1 (notification volume dependent)
- CloudWatch: <$1 (log retention dependent)
- Systems Manager: Free (parameter storage)

Total estimated cost: $7-22 per month for moderate usage