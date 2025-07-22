# AWS App2Container CDK Python Application

This CDK Python application provisions the complete infrastructure needed for application modernization using AWS App2Container. It creates all necessary AWS resources including ECS cluster, ECR repository, CI/CD pipeline, and supporting services for containerizing and deploying legacy applications.

## Architecture Overview

This CDK application deploys:

- **VPC**: Multi-AZ VPC with public and private subnets
- **ECS Cluster**: Fargate-enabled cluster for running containerized applications
- **ECR Repository**: Container image registry with lifecycle policies
- **Application Load Balancer**: Internet-facing ALB with target groups
- **CI/CD Pipeline**: CodeCommit, CodeBuild, and CodePipeline integration
- **IAM Roles**: Properly scoped roles for App2Container and ECS operations
- **S3 Bucket**: Artifact storage for App2Container operations
- **CloudWatch**: Logging and monitoring dashboard
- **Security Groups**: Properly configured network security

## Prerequisites

1. **AWS CLI**: Version 2.x installed and configured
2. **AWS CDK**: Version 2.162.1 or later
3. **Python**: Version 3.8 or later
4. **Docker**: For local testing (optional)
5. **AWS Account**: With appropriate permissions for the services above

### Required AWS Permissions

Your AWS credentials must have permissions to create and manage:
- EC2 (VPC, Security Groups, Load Balancers)
- ECS (Clusters, Services, Task Definitions)
- ECR (Repositories, Images)
- IAM (Roles, Policies)
- S3 (Buckets, Objects)
- CodeCommit, CodeBuild, CodePipeline
- CloudWatch (Logs, Dashboards)

## Installation and Setup

### 1. Install Dependencies

```bash
# Create and activate virtual environment (recommended)
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install required packages
pip install -r requirements.txt
```

### 2. Configure AWS CDK

```bash
# Bootstrap CDK (only needed once per account/region)
cdk bootstrap

# Verify CDK installation
cdk --version
```

### 3. Configure Application

You can customize the deployment by modifying the context in `cdk.json` or passing context variables:

```bash
# Deploy with custom unique suffix
cdk deploy --context unique_suffix=prod

# Deploy to specific region
export CDK_DEFAULT_REGION=us-west-2
cdk deploy
```

## Deployment

### Quick Start

```bash
# Synthesize CloudFormation template
cdk synth

# Deploy the stack
cdk deploy

# View stack outputs
cdk deploy --outputs-file outputs.json
```

### Advanced Deployment Options

```bash
# Deploy with approval for IAM changes
cdk deploy --require-approval any-change

# Deploy with custom parameters
cdk deploy --parameters unique-suffix=myapp

# Deploy with specific profile
cdk deploy --profile production

# Deploy with verbose logging
cdk deploy --verbose
```

## Stack Outputs

After successful deployment, the stack provides these important outputs:

- **VpcId**: VPC identifier for the infrastructure
- **EcsClusterName**: ECS cluster name for containerized applications
- **EcrRepositoryUri**: ECR repository URI for container images
- **S3BucketName**: S3 bucket for App2Container artifacts
- **CodeCommitRepositoryCloneUrl**: Git repository for CI/CD pipeline
- **LoadBalancerDnsName**: ALB DNS name for application access
- **App2ContainerRoleArn**: IAM role for App2Container operations
- **EcsTaskRoleArn**: IAM role for ECS tasks
- **EcsExecutionRoleArn**: IAM execution role for ECS tasks

## Using with App2Container

### 1. Configure App2Container

After stack deployment, configure App2Container to use the created resources:

```bash
# Initialize App2Container with the S3 bucket
sudo app2container init

# Configure with stack outputs
export S3_BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name App2ContainerStack \
    --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
    --output text)

export ECR_REPO_URI=$(aws cloudformation describe-stacks \
    --stack-name App2ContainerStack \
    --query 'Stacks[0].Outputs[?OutputKey==`EcrRepositoryUri`].OutputValue' \
    --output text)
```

### 2. Modernize Applications

Follow the App2Container workflow:

```bash
# Discover applications
sudo app2container inventory

# Analyze application (replace app-id with actual ID)
sudo app2container analyze --application-id <app-id>

# Extract application artifacts
sudo app2container extract --application-id <app-id>

# Containerize the application
sudo app2container containerize --application-id <app-id>

# Generate deployment artifacts for ECS
sudo app2container generate app-deployment \
    --application-id <app-id> \
    --deploy-target ecs
```

### 3. Deploy to ECS

Use the generated deployment artifacts with the ECS cluster:

```bash
# Deploy containerized application to ECS
sudo app2container generate app-deployment \
    --application-id <app-id> \
    --deploy-target ecs \
    --deploy
```

## Monitoring and Logging

### CloudWatch Dashboard

The stack creates a CloudWatch dashboard with key metrics:
- ECS cluster CPU utilization
- Application Load Balancer request count
- Container task health status

Access the dashboard in the AWS Console under CloudWatch > Dashboards.

### Application Logs

Container logs are automatically sent to CloudWatch Logs:

```bash
# View ECS service logs
aws logs describe-log-groups --log-group-name-prefix "/aws/ecs/app2container"

# Stream logs for a specific application
aws logs tail /aws/ecs/app2container-demo --follow
```

## Customization

### Modifying Resources

You can customize the infrastructure by editing `app.py`:

1. **VPC Configuration**: Modify CIDR blocks, subnet configuration
2. **ECS Settings**: Change capacity providers, container insights
3. **Load Balancer**: Configure SSL certificates, additional listeners
4. **Auto Scaling**: Adjust scaling policies and thresholds
5. **Security**: Modify security groups, IAM policies

### Environment-Specific Deployments

Create multiple stacks for different environments:

```bash
# Development environment
cdk deploy App2ContainerDevStack --context env=dev

# Production environment  
cdk deploy App2ContainerProdStack --context env=prod
```

## Security Considerations

### IAM Permissions

The stack creates least-privilege IAM roles:
- **App2ContainerRole**: Permissions for App2Container operations
- **EcsTaskRole**: Runtime permissions for containerized applications
- **EcsExecutionRole**: ECS service permissions for task execution

### Network Security

- VPC with private subnets for ECS tasks
- Security groups restricting traffic to necessary ports
- ALB with configurable ingress rules

### Container Security

- ECR repositories with image scanning enabled
- ECS tasks running in private subnets
- CloudWatch monitoring for security events

## Troubleshooting

### Common Issues

1. **CDK Bootstrap Error**:
   ```bash
   # Re-bootstrap with verbose logging
   cdk bootstrap --verbose
   ```

2. **Permission Denied**:
   ```bash
   # Check AWS credentials
   aws sts get-caller-identity
   
   # Verify IAM permissions
   aws iam get-user
   ```

3. **Stack Deployment Fails**:
   ```bash
   # Check CloudFormation events
   aws cloudformation describe-stack-events --stack-name App2ContainerStack
   
   # Deploy with rollback disabled for debugging
   cdk deploy --no-rollback
   ```

4. **App2Container Configuration Issues**:
   ```bash
   # Verify App2Container configuration
   sudo app2container config
   
   # Check S3 bucket access
   aws s3 ls s3://$(echo $S3_BUCKET_NAME)
   ```

### Debugging

Enable CDK debug mode:

```bash
# Deploy with debug logging
cdk deploy --debug

# Synthesize with verbose output
cdk synth --verbose
```

## Cleanup

To avoid ongoing charges, clean up resources when no longer needed:

```bash
# Destroy the CDK stack
cdk destroy

# Confirm deletion of all resources
cdk destroy --force

# Clean up CDK bootstrap resources (optional)
# Note: This affects other CDK deployments in the account/region
aws cloudformation delete-stack --stack-name CDKToolkit
```

### Manual Cleanup

Some resources may require manual cleanup:

1. **ECR Images**: Delete container images if auto-delete failed
2. **S3 Objects**: Empty S3 buckets if auto-delete is disabled
3. **CloudWatch Logs**: Delete log groups to avoid storage charges

## Development

### Code Quality

Run linting and testing:

```bash
# Install development dependencies
pip install -r requirements.txt

# Run linting
flake8 app.py

# Run type checking
mypy app.py

# Format code
black app.py

# Run tests (if implemented)
pytest tests/
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## Support

For issues and questions:

- **AWS Documentation**: [App2Container User Guide](https://docs.aws.amazon.com/app2container/)
- **CDK Documentation**: [AWS CDK Python Reference](https://docs.aws.amazon.com/cdk/api/v2/python/)
- **GitHub Issues**: Report bugs and request features
- **AWS Support**: For production workload assistance

## License

This project is licensed under the MIT License. See the LICENSE file for details.

## Additional Resources

- [AWS App2Container Workshop](https://app2container.workshop.aws/)
- [Container Migration Best Practices](https://docs.aws.amazon.com/prescriptive-guidance/latest/containers-migration/)
- [ECS Best Practices Guide](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)