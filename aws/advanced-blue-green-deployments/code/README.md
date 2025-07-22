# Infrastructure as Code for Implementing Advanced Blue-Green Deployments with ECS, Lambda, and CodeDeploy

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Implementing Advanced Blue-Green Deployments with ECS, Lambda, and CodeDeploy".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements sophisticated blue-green deployment patterns for both containerized (ECS) and serverless (Lambda) workloads using AWS CodeDeploy. The infrastructure includes:

- **Application Load Balancer** with blue/green target groups for traffic management
- **ECS Fargate cluster** with service and task definitions for containerized applications
- **Lambda functions** with aliases for serverless deployments
- **CodeDeploy applications** with deployment groups for both ECS and Lambda
- **CloudWatch monitoring** with alarms for automated rollback triggers
- **ECR repository** for container image management
- **IAM roles** implementing least privilege security principles
- **SNS notifications** for deployment status updates
- **Pre/post deployment hooks** for validation and testing

## Prerequisites

- AWS CLI v2 installed and configured
- Docker installed for container image management
- Appropriate AWS permissions for:
  - ECS, Lambda, CodeDeploy, ALB, ECR
  - IAM role creation and management
  - CloudWatch alarms and metrics
  - VPC and networking resources
- Basic understanding of blue-green deployment concepts
- Estimated cost: $30-60 for testing (ALB, ECS tasks, Lambda executions, monitoring)

## Quick Start

### Using CloudFormation
```bash
# Deploy the complete blue-green infrastructure
aws cloudformation create-stack \
    --stack-name advanced-blue-green-deployment \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ProjectName,ParameterValue=my-blue-green-project \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --enable-termination-protection

# Monitor deployment progress
aws cloudformation describe-stack-events \
    --stack-name advanced-blue-green-deployment \
    --query 'StackEvents[?ResourceStatus==`CREATE_IN_PROGRESS`]'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name advanced-blue-green-deployment \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure project settings
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the infrastructure
cdk deploy --all --require-approval never

# View deployed resources
cdk list
```

### Using CDK Python
```bash
cd cdk-python/

# Set up Python virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure environment
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the infrastructure
cdk deploy --all --require-approval never

# View application stacks
cdk list
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_name=my-blue-green-project"

# Apply the configuration
terraform apply -var="project_name=my-blue-green-project" -auto-approve

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_NAME="my-blue-green-project"
export AWS_REGION=$(aws configure get region)

# Deploy the complete solution
./scripts/deploy.sh

# Check deployment status
./scripts/deploy.sh --status

# Test blue-green deployment
./scripts/deploy.sh --test-deployment
```

## Post-Deployment Setup

### 1. Container Image Preparation
```bash
# Get ECR repository URI from outputs
ECR_URI=$(aws cloudformation describe-stacks \
    --stack-name advanced-blue-green-deployment \
    --query 'Stacks[0].Outputs[?OutputKey==`ECRRepositoryURI`].OutputValue' \
    --output text)

# Authenticate Docker to ECR
aws ecr get-login-password --region $AWS_REGION | \
    docker login --username AWS --password-stdin $ECR_URI

# Build and push sample application images
# (See recipe documentation for sample application code)
docker build -t $ECR_URI:1.0.0 .
docker push $ECR_URI:1.0.0

docker build -t $ECR_URI:2.0.0 --build-arg VERSION=2.0.0 .
docker push $ECR_URI:2.0.0
```

### 2. Initial Service Deployment
```bash
# Get ALB DNS name
ALB_DNS=$(aws cloudformation describe-stacks \
    --stack-name advanced-blue-green-deployment \
    --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerDNS`].OutputValue' \
    --output text)

# Test initial deployment
curl http://$ALB_DNS/health
curl http://$ALB_DNS/
```

### 3. Lambda Function Testing
```bash
# Get Lambda function name
LAMBDA_FUNCTION=$(aws cloudformation describe-stacks \
    --stack-name advanced-blue-green-deployment \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

# Test Lambda function
aws lambda invoke \
    --function-name $LAMBDA_FUNCTION:PROD \
    --payload '{"httpMethod":"GET","path":"/health"}' \
    --cli-binary-format raw-in-base64-out \
    response.json

cat response.json
```

## Blue-Green Deployment Process

### 1. ECS Blue-Green Deployment
```bash
# Create deployment using CodeDeploy
aws deploy create-deployment \
    --application-name <ECS-APPLICATION-NAME> \
    --deployment-group-name <ECS-DEPLOYMENT-GROUP> \
    --revision revisionType=AppSpecContent,appSpecContent='{
        "content": "<BASE64-ENCODED-APPSPEC>"
    }' \
    --deployment-config-name CodeDeployDefault.ECSLinear10PercentEvery1Minutes

# Monitor deployment
aws deploy get-deployment --deployment-id <DEPLOYMENT-ID>
```

### 2. Lambda Blue-Green Deployment
```bash
# Update Lambda function code
aws lambda update-function-code \
    --function-name <FUNCTION-NAME> \
    --zip-file fileb://function.zip \
    --publish

# Create deployment using CodeDeploy
aws deploy create-deployment \
    --application-name <LAMBDA-APPLICATION-NAME> \
    --deployment-group-name <LAMBDA-DEPLOYMENT-GROUP> \
    --revision revisionType=AppSpecContent,appSpecContent='{
        "content": "<BASE64-ENCODED-APPSPEC>"
    }' \
    --deployment-config-name CodeDeployDefault.LambdaLinear10PercentEvery1Minute
```

### 3. Automated Rollback Triggers
The infrastructure includes CloudWatch alarms that automatically trigger rollbacks:
- High error rates (>10 errors per minute)
- Increased response times (>2 seconds average)
- Lambda function errors (>5 errors per minute)
- Lambda duration increases (>5 seconds average)

## Monitoring and Observability

### CloudWatch Dashboard
Access the pre-configured dashboard:
```bash
# Get dashboard URL
echo "https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards:name=Blue-Green-Deployments-<PROJECT-NAME>"
```

### Key Metrics to Monitor
- **CodeDeploy Deployments**: Success/failure rates
- **ALB Performance**: Response times, HTTP status codes
- **ECS Service Health**: Running/desired task counts
- **Lambda Performance**: Duration, invocations, errors
- **Deployment Validation**: Custom validation metrics

### Log Analysis
```bash
# View ECS application logs
aws logs filter-log-events \
    --log-group-name "/ecs/<SERVICE-NAME>" \
    --start-time $(date -d '1 hour ago' +%s)000

# View Lambda function logs
aws logs filter-log-events \
    --log-group-name "/aws/lambda/<FUNCTION-NAME>" \
    --start-time $(date -d '1 hour ago' +%s)000
```

## Cleanup

### Using CloudFormation
```bash
# Disable termination protection
aws cloudformation update-termination-protection \
    --stack-name advanced-blue-green-deployment \
    --no-enable-termination-protection

# Delete the stack
aws cloudformation delete-stack \
    --stack-name advanced-blue-green-deployment

# Monitor deletion progress
aws cloudformation describe-stack-events \
    --stack-name advanced-blue-green-deployment
```

### Using CDK
```bash
# Destroy all stacks
cdk destroy --all --force

# Clean up CDK bootstrap (optional)
# Note: Only do this if no other CDK applications are using it
# cdk bootstrap --force --toolkit-stack-name CDKToolkit
```

### Using Terraform
```bash
cd terraform/

# Destroy all resources
terraform destroy -var="project_name=my-blue-green-project" -auto-approve

# Clean up Terraform state
rm -rf .terraform terraform.tfstate*
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm all resources are deleted
./scripts/destroy.sh --verify
```

## Customization

### Key Configuration Parameters

#### CloudFormation Parameters
- `ProjectName`: Unique identifier for all resources
- `VpcId`: VPC for resource deployment (defaults to default VPC)
- `SubnetIds`: Subnets for ALB and ECS deployment
- `ContainerImage`: Initial container image URI
- `DesiredCount`: Number of ECS tasks to run

#### Terraform Variables
- `project_name`: Unique identifier for resources
- `region`: AWS region for deployment
- `vpc_id`: VPC for resource deployment
- `subnet_ids`: List of subnet IDs
- `container_cpu`: CPU units for ECS tasks (256-4096)
- `container_memory`: Memory for ECS tasks (512-8192)

#### CDK Configuration
Modify `cdk.json` or environment variables:
- `PROJECT_NAME`: Resource naming prefix
- `DESIRED_COUNT`: ECS service desired count
- `CONTAINER_CPU`: ECS task CPU allocation
- `CONTAINER_MEMORY`: ECS task memory allocation

### Traffic Shifting Strategies

Modify deployment configurations for different traffic patterns:
- `CodeDeployDefault.ECSLinear10PercentEvery1Minutes`: Linear 10% every minute
- `CodeDeployDefault.ECSLinear10PercentEvery3Minutes`: Linear 10% every 3 minutes
- `CodeDeployDefault.ECSCanary10Percent15Minutes`: 10% canary for 15 minutes
- `CodeDeployDefault.LambdaLinear10PercentEvery1Minute`: Lambda linear 10%
- `CodeDeployDefault.LambdaCanary10Percent5Minutes`: Lambda canary 10%

### Monitoring Customization

Adjust CloudWatch alarm thresholds:
```bash
# Update error rate threshold
aws cloudwatch put-metric-alarm \
    --alarm-name "high-error-rate" \
    --threshold 20 \
    --comparison-operator GreaterThanThreshold
```

## Troubleshooting

### Common Issues

1. **ECS Service Won't Start**
   - Check IAM roles and policies
   - Verify container image exists in ECR
   - Check security group configurations
   - Review ECS service events

2. **CodeDeploy Deployment Fails**
   - Verify AppSpec configuration
   - Check CodeDeploy service role permissions
   - Review deployment logs
   - Validate target group health checks

3. **Lambda Deployment Issues**
   - Check Lambda function configuration
   - Verify alias and version settings
   - Review IAM execution role
   - Check function timeout settings

4. **ALB Health Check Failures**
   - Verify health check path exists
   - Check application startup time
   - Review security group rules
   - Validate target group configuration

### Debugging Commands
```bash
# Check ECS service events
aws ecs describe-services \
    --cluster <CLUSTER-NAME> \
    --services <SERVICE-NAME> \
    --query 'services[0].events'

# Review CodeDeploy deployment status
aws deploy get-deployment \
    --deployment-id <DEPLOYMENT-ID> \
    --query 'deploymentInfo.errorInformation'

# Check ALB target health
aws elbv2 describe-target-health \
    --target-group-arn <TARGET-GROUP-ARN>

# Review CloudWatch alarm history
aws cloudwatch describe-alarm-history \
    --alarm-name <ALARM-NAME>
```

## Security Considerations

- All IAM roles follow least privilege principles
- Security groups restrict access to necessary ports only
- Container images should be scanned for vulnerabilities
- Enable AWS CloudTrail for audit logging
- Use AWS Secrets Manager for sensitive configuration
- Implement network ACLs for additional security layers

## Performance Optimization

- Adjust ECS task CPU and memory based on application requirements
- Configure ALB target group deregistration delay
- Optimize Lambda function memory allocation
- Use CloudWatch Insights for log analysis
- Implement custom metrics for business KPIs
- Consider using AWS X-Ray for distributed tracing

## Cost Optimization

- Use Spot instances for development/testing environments
- Implement auto-scaling for ECS services
- Monitor CloudWatch costs and optimize metric retention
- Use Lambda provisioned concurrency judiciously
- Clean up unused ECR images regularly
- Consider Reserved Instances for predictable workloads

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS service documentation
3. Review CloudFormation/CDK/Terraform provider documentation
4. Check AWS service health dashboard
5. Contact AWS support for service-specific issues

## Additional Resources

- [AWS Blue-Green Deployment Best Practices](https://docs.aws.amazon.com/whitepapers/latest/blue-green-deployments/welcome.html)
- [CodeDeploy User Guide](https://docs.aws.amazon.com/codedeploy/latest/userguide/welcome.html)
- [ECS Developer Guide](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/Welcome.html)
- [Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/welcome.html)
- [Application Load Balancer User Guide](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)