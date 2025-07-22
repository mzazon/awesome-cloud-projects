# AWS App2Container Infrastructure - Terraform

This Terraform configuration creates the complete infrastructure for containerizing and deploying legacy applications using AWS App2Container. The infrastructure includes ECS clusters, ECR repositories, CI/CD pipelines, load balancers, and comprehensive monitoring.

## Architecture Overview

The Terraform configuration deploys:

- **Amazon ECS**: Managed container orchestration with Fargate
- **Amazon ECR**: Container image registry with security scanning
- **Application Load Balancer**: HTTP/HTTPS load balancing with health checks
- **AWS CodePipeline**: Complete CI/CD pipeline for automated deployments
- **AWS CodeBuild**: Container image building and testing
- **AWS CodeCommit**: Git repository for source code management
- **Amazon CloudWatch**: Comprehensive monitoring, logging, and alerting
- **Amazon S3**: Artifact storage for App2Container and pipeline artifacts
- **AWS IAM**: Least-privilege security roles and policies
- **Auto Scaling**: Automatic scaling based on CPU utilization

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **AWS CLI** installed and configured with appropriate credentials
2. **Terraform** >= 1.5 installed
3. **AWS Account** with sufficient permissions to create the required resources
4. **Legacy Application** ready for containerization with App2Container

### Required AWS Permissions

Your AWS credentials must have permissions for:
- ECS, ECR, ELB, Auto Scaling
- CodePipeline, CodeBuild, CodeCommit
- CloudWatch, SNS, S3
- IAM role and policy management
- VPC and Security Group management

## Quick Start

### 1. Clone and Configure

```bash
# Navigate to the terraform directory
cd terraform/

# Copy example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit variables to match your requirements
vim terraform.tfvars
```

### 2. Initialize and Plan

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan
```

### 3. Deploy Infrastructure

```bash
# Apply the configuration
terraform apply

# Confirm deployment by typing 'yes' when prompted
```

### 4. Deploy Your Application

After infrastructure deployment, follow these steps:

```bash
# Get ECR repository URL from outputs
ECR_REPO=$(terraform output -raw ecr_repository_url)

# Authenticate Docker with ECR
aws ecr get-login-password --region $(aws configure get region) | docker login --username AWS --password-stdin $ECR_REPO

# Tag and push your containerized application
docker tag your-app:latest $ECR_REPO:latest
docker push $ECR_REPO:latest

# Update ECS service to use the new image
aws ecs update-service \
  --cluster $(terraform output -raw cluster_name) \
  --service $(terraform output -raw service_name) \
  --force-new-deployment
```

## Configuration Options

### Core Configuration

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `environment` | Environment name | `dev` | `dev`, `test`, `staging`, `prod` |
| `task_cpu` | ECS task CPU units | `512` | `256`, `512`, `1024`, `2048`, `4096` |
| `task_memory` | ECS task memory (MB) | `1024` | Compatible with CPU selection |
| `container_port` | Application port | `8080` | Any valid port number |

### Auto Scaling Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `desired_count` | Initial task count | `2` |
| `min_capacity` | Minimum tasks | `1` |
| `max_capacity` | Maximum tasks | `10` |
| `cpu_target_value` | CPU target for scaling | `70.0` |

### Security Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_waf` | Enable AWS WAF | `false` |
| `enable_secrets_manager` | Use Secrets Manager | `true` |
| `compliance_mode` | Compliance level | `none` |

## Monitoring and Alerting

The infrastructure includes comprehensive monitoring:

### CloudWatch Dashboard
Access your application metrics at:
```
https://console.aws.amazon.com/cloudwatch/home#dashboards
```

### Key Metrics Monitored
- ECS Service CPU and Memory utilization
- Application Load Balancer request metrics
- Container health and availability
- Pipeline execution status

### Alarms Configured
- High CPU utilization (>80% by default)
- High memory utilization (>80% by default)
- ALB target health failures

## CI/CD Pipeline

The deployed pipeline includes three stages:

1. **Source**: Monitors CodeCommit repository for changes
2. **Build**: Uses CodeBuild to create container images
3. **Deploy**: Automatically deploys to ECS service

### Using the Pipeline

```bash
# Get repository clone URL
REPO_URL=$(terraform output -raw codecommit_repository_clone_url_http)

# Clone the repository
git clone $REPO_URL app2container-code
cd app2container-code

# Add your Dockerfile and buildspec.yml
# (Examples provided in the recipe documentation)

# Commit and push to trigger pipeline
git add .
git commit -m "Initial application deployment"
git push origin main
```

## Cost Optimization

### Fargate Spot Instances
Enable Fargate Spot for development environments:
```hcl
enable_spot_instances = true
```

### Right Sizing
Monitor your application metrics and adjust:
- `task_cpu` and `task_memory` based on actual usage
- `min_capacity` and `max_capacity` for auto scaling

### Log Retention
Adjust CloudWatch log retention to balance cost and compliance:
```hcl
log_retention_days = 7  # For development
log_retention_days = 30 # For production
```

## Security Best Practices

The configuration implements several security best practices:

### Encryption
- S3 buckets encrypted with AES-256
- ECR repository encryption enabled
- CloudWatch logs encryption configured

### IAM Roles
- Least privilege access for all services
- Separate roles for task execution and application runtime
- No hardcoded credentials

### Network Security
- Security groups with minimal required access
- VPC deployment with private subnets (configurable)
- ALB with security group restrictions

### Container Security
- ECR image scanning enabled
- Container running as non-root user (configure in Dockerfile)
- Read-only root filesystem (configurable)

## Troubleshooting

### Common Issues

**ECS Service Not Starting**
```bash
# Check service events
aws ecs describe-services \
  --cluster $(terraform output -raw cluster_name) \
  --services $(terraform output -raw service_name)

# Check task logs
aws logs tail $(terraform output -raw cloudwatch_log_group_name) --follow
```

**ALB Health Check Failures**
```bash
# Check target group health
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw target_group_arn)
```

**Pipeline Failures**
```bash
# Check pipeline status
aws codepipeline get-pipeline-state \
  --name $(terraform output -raw codepipeline_name)

# Check build logs
aws logs tail /aws/codebuild/$(terraform output -raw codebuild_project_name) --follow
```

### Useful Commands

All troubleshooting commands are available in the Terraform outputs:
```bash
terraform output troubleshooting_commands
```

## Cleanup

To destroy all resources:

```bash
# Destroy infrastructure
terraform destroy

# Confirm by typing 'yes' when prompted
```

**Warning**: This will permanently delete all resources including data stored in S3 buckets.

## Advanced Configuration

### Custom VPC Deployment
```hcl
vpc_id = "vpc-12345678"
subnet_ids = ["subnet-12345678", "subnet-87654321"]
```

### HTTPS with Custom Domain
```hcl
ssl_certificate_arn = "arn:aws:acm:region:account:certificate/cert-id"
custom_domain_name = "app.example.com"
route53_zone_id = "Z1D633PJN98FT9"
enable_https_redirect = true
```

### Service Mesh Integration
```hcl
enable_app_mesh = true
app_mesh_name = "my-app-mesh"
enable_service_discovery = true
service_discovery_namespace = "my-apps.local"
```

## Support

For issues related to this Terraform configuration:

1. Check the [troubleshooting section](#troubleshooting) above
2. Review AWS service documentation for specific services
3. Check Terraform AWS provider documentation
4. Refer to the original App2Container recipe documentation

## Contributing

When making changes to this Terraform configuration:

1. Follow HashiCorp's Terraform style guide
2. Update variable descriptions and validation rules
3. Add appropriate outputs for new resources
4. Test changes in a development environment
5. Update this README with new features or configuration options

## Version History

- **v1.0**: Initial release with core App2Container infrastructure
- **v1.1**: Added advanced security and compliance features
- **v1.2**: Enhanced monitoring and cost optimization options