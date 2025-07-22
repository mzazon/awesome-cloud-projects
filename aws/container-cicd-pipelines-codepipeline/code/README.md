# Infrastructure as Code for Container CI/CD Pipelines with CodePipeline

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Container CI/CD Pipelines with CodePipeline".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Docker installed locally for container testing
- Administrative permissions for AWS services including:
  - CodePipeline, CodeDeploy, CodeBuild
  - ECS, ECR, Application Load Balancer
  - VPC, IAM, CloudWatch, X-Ray
  - SNS, Parameter Store, Secrets Manager
- GitHub repository with containerized application
- Basic understanding of containerization and CI/CD concepts
- Estimated cost: $150-200 per month for multi-environment deployment

## Architecture Overview

This solution creates a comprehensive CI/CD pipeline that includes:

- **Multi-Environment ECS Clusters**: Separate development and production environments
- **Enhanced Security**: ECR vulnerability scanning, IAM least privilege, security group isolation
- **Advanced Deployment Strategies**: Blue-green deployments with canary rollouts
- **Comprehensive Monitoring**: Container Insights, X-Ray tracing, CloudWatch alarms
- **Automated Testing**: Security scanning, unit tests, and compliance validation
- **Intelligent Rollback**: Automated rollback based on performance metrics and health checks

## Quick Start

### Using CloudFormation
```bash
# Deploy the complete infrastructure
aws cloudformation create-stack \
    --stack-name cicd-container-pipeline \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ProjectName,ParameterValue=my-project \
                 ParameterKey=GitHubRepo,ParameterValue=my-org/my-repo \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name cicd-container-pipeline

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name cicd-container-pipeline \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure environment variables
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy infrastructure
cdk bootstrap
cdk deploy --all

# Monitor deployment
cdk ls
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Configure environment
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy infrastructure
cdk bootstrap
cdk deploy --all
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan \
    -var="project_name=my-project" \
    -var="github_repo=my-org/my-repo"

# Apply configuration
terraform apply \
    -var="project_name=my-project" \
    -var="github_repo=my-org/my-repo"

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_NAME="my-project"
export GITHUB_REPO="my-org/my-repo"

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/deploy.sh --status
```

## Configuration

### Environment Variables

The following environment variables can be configured:

- `PROJECT_NAME`: Unique name for your project resources
- `GITHUB_REPO`: GitHub repository in format "owner/repo"
- `AWS_REGION`: AWS region for deployment (defaults to CLI configuration)
- `CONTAINER_PORT`: Application container port (default: 8080)
- `HEALTH_CHECK_PATH`: Application health check endpoint (default: /health)

### Customization Options

#### Development Environment
- **Instance Type**: Fargate Spot for cost optimization
- **Scaling**: 2 tasks for basic load testing
- **Log Retention**: 7 days
- **Deployment**: Rolling updates for fast iteration

#### Production Environment
- **Instance Type**: Standard Fargate for reliability
- **Scaling**: 3 tasks with auto-scaling enabled
- **Log Retention**: 30 days
- **Deployment**: Blue-green with canary rollout

#### Pipeline Configuration
- **Build Environment**: Linux container with Docker support
- **Security Scanning**: Grype vulnerability scanner
- **Approval Gates**: Manual approval before production deployment
- **Rollback**: Automated rollback on CloudWatch alarm triggers

## Post-Deployment Steps

### 1. Configure GitHub Integration

```bash
# Create GitHub webhook for automatic pipeline triggers
aws codepipeline put-webhook \
    --webhook name=github-webhook \
    --target-pipeline=${PROJECT_NAME}-pipeline \
    --target-action=Source
```

### 2. Set Up Application Source Code

Your GitHub repository should include:
- `Dockerfile` for containerizing the application
- `buildspec.yml` for CodeBuild configuration
- `taskdef.json` for ECS task definition template
- `appspec.yaml` for CodeDeploy configuration

### 3. Configure Monitoring and Alerting

```bash
# Subscribe to SNS topic for pipeline notifications
aws sns subscribe \
    --topic-arn arn:aws:sns:${AWS_REGION}:${ACCOUNT_ID}:${PROJECT_NAME}-alerts \
    --protocol email \
    --notification-endpoint your-email@example.com
```

### 4. Test the Pipeline

```bash
# Trigger pipeline manually
aws codepipeline start-pipeline-execution \
    --name ${PROJECT_NAME}-pipeline

# Monitor pipeline execution
aws codepipeline get-pipeline-execution \
    --pipeline-name ${PROJECT_NAME}-pipeline \
    --pipeline-execution-id <execution-id>
```

## Monitoring and Troubleshooting

### Pipeline Monitoring
- **CodePipeline Console**: Monitor pipeline execution status
- **CloudWatch Logs**: View build logs and deployment details
- **X-Ray Console**: Trace application performance and dependencies
- **Container Insights**: Monitor ECS cluster performance

### Common Issues

#### Build Failures
```bash
# Check CodeBuild logs
aws logs filter-log-events \
    --log-group-name /aws/codebuild/${PROJECT_NAME}-build \
    --start-time $(date -u -d '1 hour ago' +%s)000
```

#### Deployment Failures
```bash
# Check CodeDeploy deployment status
aws deploy get-deployment \
    --deployment-id <deployment-id>

# Check ECS service events
aws ecs describe-services \
    --cluster ${PROJECT_NAME}-prod-cluster \
    --services ${PROJECT_NAME}-service-prod
```

#### Performance Issues
```bash
# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/ECS \
    --metric-name CPUUtilization \
    --dimensions Name=ServiceName,Value=${PROJECT_NAME}-service-prod \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average
```

## Security Considerations

### IAM Roles and Policies
- **Least Privilege**: All roles follow minimum required permissions
- **Service-Specific Roles**: Separate roles for each service component
- **Cross-Account Access**: Configured for multi-account deployments

### Network Security
- **VPC Isolation**: Dedicated VPC with private subnets
- **Security Groups**: Restrictive inbound/outbound rules
- **WAF Integration**: Optional Web Application Firewall for ALB

### Container Security
- **Image Scanning**: Automatic vulnerability scanning on ECR push
- **Runtime Security**: ReadOnly root filesystem and non-root user
- **Secrets Management**: Parameter Store and Secrets Manager integration

## Scaling and Optimization

### Auto Scaling Configuration
```bash
# Configure ECS service auto scaling
aws application-autoscaling register-scalable-target \
    --service-namespace ecs \
    --resource-id service/${PROJECT_NAME}-prod-cluster/${PROJECT_NAME}-service-prod \
    --scalable-dimension ecs:service:DesiredCount \
    --min-capacity 2 \
    --max-capacity 10

# Create scaling policy
aws application-autoscaling put-scaling-policy \
    --policy-name cpu-scaling-policy \
    --service-namespace ecs \
    --resource-id service/${PROJECT_NAME}-prod-cluster/${PROJECT_NAME}-service-prod \
    --scalable-dimension ecs:service:DesiredCount \
    --policy-type TargetTrackingScaling \
    --target-tracking-scaling-policy-configuration TargetValue=70,PredefinedMetricSpecification='{PredefinedMetricType=ECSServiceAverageCPUUtilization}'
```

### Cost Optimization
- **Fargate Spot**: Use for development environment
- **Reserved Capacity**: Consider for predictable production workloads
- **Log Retention**: Optimize CloudWatch log retention periods
- **Image Lifecycle**: ECR lifecycle policies for image management

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name cicd-container-pipeline

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name cicd-container-pipeline
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy --all
```

### Using Terraform
```bash
cd terraform/
terraform destroy \
    -var="project_name=my-project" \
    -var="github_repo=my-org/my-repo"
```

### Using Bash Scripts
```bash
# Clean up all resources
./scripts/destroy.sh

# Confirm cleanup
./scripts/destroy.sh --verify
```

## Advanced Features

### Multi-Region Deployment
Extend the pipeline to deploy across multiple AWS regions for high availability and disaster recovery.

### Blue-Green Testing
Implement automated testing during blue-green deployments to validate application functionality before traffic switching.

### Canary Analysis
Integrate with CloudWatch Synthetics for automated canary testing and rollback decisions.

### Service Mesh Integration
Add AWS App Mesh for advanced traffic management and observability in microservices architectures.

### Compliance Integration
Integrate with AWS Config and Security Hub for continuous compliance monitoring and reporting.

## Support

For issues with this infrastructure code:
1. Check the original recipe documentation
2. Review AWS service documentation
3. Consult CloudFormation/CDK/Terraform provider documentation
4. Enable debug logging for detailed troubleshooting

## Contributing

When modifying this infrastructure code:
1. Follow AWS best practices and security guidelines
2. Update documentation for any configuration changes
3. Test changes in a development environment first
4. Ensure backward compatibility when possible
5. Update version numbers appropriately

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Review and modify according to your organization's requirements and security policies.