# Infrastructure as Code for Continuous Deployment with CodeDeploy

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Continuous Deployment with CodeDeploy".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured (or AWS CloudShell)
- Appropriate AWS permissions for CodeDeploy, CodeCommit, CodeBuild, EC2, IAM, and Application Load Balancer
- Git client for CodeCommit repository operations
- Understanding of blue-green deployment concepts and CI/CD pipelines
- Sufficient EC2 instance limits in your AWS account
- Estimated cost: $10-20 for testing resources (EC2 instances, ALB, data transfer)

## Architecture Overview

This solution implements a complete CI/CD pipeline featuring:

- **CodeCommit**: Source control repository for application code
- **CodeBuild**: Automated build service for creating deployment artifacts
- **CodeDeploy**: Blue-green deployment automation with Auto Scaling Groups
- **Application Load Balancer**: Traffic routing between blue and green environments
- **CloudWatch**: Monitoring and automated rollback based on alarms
- **EC2 Auto Scaling**: Automatic instance management for deployments

## Quick Start

### Using CloudFormation
```bash
# Deploy the complete infrastructure
aws cloudformation create-stack \
    --stack-name codedeploy-pipeline \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=KeyPairName,ParameterValue=your-keypair \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --region us-east-1

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name codedeploy-pipeline \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name codedeploy-pipeline \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# View outputs
cdk list
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# View outputs
cdk list
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for required parameters
# and display progress throughout deployment
```

## Post-Deployment Steps

After infrastructure deployment, follow these steps to complete the setup:

1. **Initialize the Repository**:
   ```bash
   # Clone the created repository
   git clone https://codecommit.us-east-1.amazonaws.com/v1/repos/[REPO-NAME]
   cd [REPO-NAME]
   
   # Add sample application files (provided in outputs)
   # Commit and push to trigger first deployment
   git add .
   git commit -m "Initial application deployment"
   git push origin main
   ```

2. **Monitor Deployment**:
   ```bash
   # Check CodeBuild status
   aws codebuild list-builds-for-project --project-name [BUILD-PROJECT-NAME]
   
   # Monitor CodeDeploy deployments
   aws deploy list-deployments --application-name [APP-NAME]
   ```

3. **Access Application**:
   - Use the Application Load Balancer DNS name from outputs
   - Test the application endpoint: `http://[ALB-DNS-NAME]`

## Configuration Customization

### Environment Variables

Key parameters that can be customized:

- **Region**: AWS region for deployment (default: us-east-1)
- **Instance Type**: EC2 instance type (default: t3.micro)
- **Min/Max Capacity**: Auto Scaling Group sizing
- **Deployment Strategy**: CodeDeploy configuration name
- **Health Check Settings**: Target group health check parameters

### CloudFormation Parameters

```yaml
Parameters:
  KeyPairName:
    Description: EC2 Key Pair for instance access
    Type: AWS::EC2::KeyPair::KeyName
  
  InstanceType:
    Description: EC2 instance type
    Type: String
    Default: t3.micro
  
  MinSize:
    Description: Minimum number of instances
    Type: Number
    Default: 2
```

### Terraform Variables

```hcl
variable "key_pair_name" {
  description = "EC2 Key Pair name"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "min_size" {
  description = "Minimum Auto Scaling Group size"
  type        = number
  default     = 2
}
```

## Deployment Validation

### Health Checks

1. **Infrastructure Validation**:
   ```bash
   # Check Auto Scaling Group
   aws autoscaling describe-auto-scaling-groups \
       --auto-scaling-group-names [ASG-NAME]
   
   # Verify Load Balancer
   aws elbv2 describe-load-balancers \
       --names [ALB-NAME]
   
   # Check target group health
   aws elbv2 describe-target-health \
       --target-group-arn [TARGET-GROUP-ARN]
   ```

2. **Application Testing**:
   ```bash
   # Test application accessibility
   curl -I http://[ALB-DNS-NAME]
   
   # Verify application content
   curl http://[ALB-DNS-NAME]
   ```

3. **Pipeline Testing**:
   ```bash
   # Trigger a new deployment
   aws codebuild start-build --project-name [BUILD-PROJECT-NAME]
   
   # Monitor deployment progress
   aws deploy get-deployment --deployment-id [DEPLOYMENT-ID]
   ```

## Monitoring and Observability

### CloudWatch Integration

The solution includes:

- **Deployment Failure Alarms**: Automatic rollback on deployment failures
- **Target Group Health Monitoring**: Application health tracking
- **Auto Scaling Metrics**: Instance scaling and health monitoring
- **CodeDeploy Metrics**: Deployment success/failure tracking

### Log Locations

- **CodeBuild Logs**: CloudWatch Logs group `/aws/codebuild/[PROJECT-NAME]`
- **CodeDeploy Agent Logs**: EC2 instances at `/var/log/aws/codedeploy-agent/`
- **Application Logs**: EC2 instances at `/var/log/httpd/`
- **Load Balancer Access Logs**: S3 bucket (if enabled)

## Troubleshooting

### Common Issues

1. **Deployment Failures**:
   - Check CodeDeploy agent status on EC2 instances
   - Verify IAM roles have necessary permissions
   - Review application health check endpoints

2. **Build Failures**:
   - Check CodeBuild logs in CloudWatch
   - Verify source repository connectivity
   - Ensure buildspec.yml is properly formatted

3. **Load Balancer Issues**:
   - Verify security group rules allow traffic
   - Check target group health check settings
   - Ensure instances are registered with target groups

### Debug Commands

```bash
# Check CodeDeploy agent status
sudo service codedeploy-agent status

# View CodeDeploy agent logs
sudo tail -f /var/log/aws/codedeploy-agent/codedeploy-agent.log

# Test application locally
curl http://localhost/

# Check Auto Scaling Group activity
aws autoscaling describe-scaling-activities \
    --auto-scaling-group-name [ASG-NAME]
```

## Security Considerations

### IAM Roles and Policies

The solution implements least-privilege access with dedicated roles:

- **CodeDeployServiceRole**: Permissions for deployment operations
- **CodeDeployEC2Role**: Instance permissions for artifact access
- **CodeBuildServiceRole**: Build service permissions

### Security Groups

- **ALB Security Group**: Allows HTTP (port 80) from internet
- **EC2 Security Group**: Allows HTTP from ALB and SSH for debugging

### Best Practices

- Regularly rotate EC2 key pairs
- Monitor CloudTrail logs for API activity
- Use VPC endpoints for private subnet deployments
- Enable ALB access logging for audit trails

## Cleanup

### Using CloudFormation
```bash
# Delete the stack (removes all resources)
aws cloudformation delete-stack --stack-name codedeploy-pipeline

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name codedeploy-pipeline \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
# From the CDK directory
cdk destroy

# Confirm destruction when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup Verification

After automated cleanup, verify these resources are removed:

- EC2 instances and Auto Scaling Groups
- Application Load Balancer and target groups
- CodeDeploy applications and deployment groups
- CodeBuild projects and CodeCommit repositories
- IAM roles and instance profiles
- S3 buckets for artifacts
- CloudWatch alarms and log groups

## Cost Optimization

### Resource Sizing

- Use `t3.micro` instances for development/testing
- Adjust Auto Scaling Group capacity based on load requirements
- Consider spot instances for non-production environments

### Cleanup Recommendations

- Delete unused deployment artifacts in S3
- Remove old CloudWatch log streams
- Terminate idle development environments
- Use scheduled scaling for predictable workloads

## Support and Documentation

### Additional Resources

- [AWS CodeDeploy User Guide](https://docs.aws.amazon.com/codedeploy/latest/userguide/)
- [Blue/Green Deployments with CodeDeploy](https://docs.aws.amazon.com/codedeploy/latest/userguide/welcome.html#blue-green-overview)
- [Auto Scaling Group Integration](https://docs.aws.amazon.com/codedeploy/latest/userguide/integrations-aws-auto-scaling.html)
- [Application Load Balancer Guide](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)

### Getting Help

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review CloudWatch logs for error details
3. Refer to the original recipe documentation
4. Consult AWS service documentation
5. Use AWS Support for service-specific issues

## Contributing

To improve this IaC implementation:

1. Test changes in a development environment
2. Follow AWS best practices and security guidelines
3. Update documentation for any parameter changes
4. Validate all deployment types work correctly