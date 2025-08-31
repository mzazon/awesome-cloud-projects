# Infrastructure as Code for Advanced Request Routing with VPC Lattice and ALB

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Advanced Request Routing with VPC Lattice and ALB".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

The infrastructure creates a sophisticated request routing solution featuring:

- **VPC Lattice Service Network**: Application-layer networking across VPCs
- **Cross-VPC Communication**: Two VPCs connected through VPC Lattice
- **Internal Application Load Balancer**: Layer 7 routing target for VPC Lattice
- **EC2 Web Servers**: Demonstrate different routing scenarios
- **Advanced Routing Rules**: Path, header, and method-based routing
- **IAM Authentication**: Fine-grained access control

## Prerequisites

### General Requirements

- AWS CLI v2 installed and configured
- AWS account with appropriate permissions for:
  - VPC Lattice (CreateService, CreateServiceNetwork, CreateTargetGroup)
  - EC2 (CreateVpc, CreateSubnet, RunInstances, CreateSecurityGroup)
  - Elastic Load Balancing v2 (CreateLoadBalancer, CreateTargetGroup, CreateListener)
  - IAM (PassRole for service-linked roles)
- Basic understanding of VPC networking and load balancing concepts
- Estimated cost: $15-25 for full deployment (includes EC2 instances, ALBs, VPC Lattice)

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI with CloudFormation permissions
- No additional tools required

#### CDK TypeScript
- Node.js 18.x or later
- npm or yarn package manager
- AWS CDK CLI: `npm install -g aws-cdk`

#### CDK Python
- Python 3.8 or later
- pip package manager
- AWS CDK CLI: `npm install -g aws-cdk`

#### Terraform
- Terraform 1.5+ installed
- AWS provider 5.0+ will be automatically downloaded

#### Bash Scripts
- Bash shell environment
- jq for JSON parsing: `sudo apt-get install jq` (Linux) or `brew install jq` (macOS)

## Quick Start

### Using CloudFormation (Recommended for AWS-native approach)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name advanced-routing-lattice \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=EnvironmentName,ParameterValue=demo

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name advanced-routing-lattice

# Get outputs
aws cloudformation describe-stacks \
    --stack-name advanced-routing-lattice \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (Recommended for developers)

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Preview changes
cdk diff

# Deploy infrastructure
cdk deploy --require-approval never

# View outputs
cdk outputs
```

### Using CDK Python (Recommended for Python developers)

```bash
cd cdk-python/

# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Preview changes
cdk diff

# Deploy infrastructure
cdk deploy --require-approval never

# View outputs
cdk outputs
```

### Using Terraform (Recommended for multi-cloud environments)

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure changes
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts (Recommended for learning/testing)

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will output service endpoints and test commands
```

## Architecture Overview

This infrastructure deploys:

1. **VPC Lattice Service Network**: Central networking fabric for cross-VPC communication
2. **Target VPCs**: Multiple VPCs with associated subnets and security groups
3. **Application Load Balancers**: Internal ALBs serving as VPC Lattice targets
4. **EC2 Instances**: Web servers with different content for routing demonstration
5. **VPC Lattice Service**: HTTP service with sophisticated routing rules
6. **IAM Policies**: Authentication and authorization controls

## Routing Rules Implemented

- **Path-based routing**: `/api/v1/*` routes to API services
- **Header-based routing**: `X-Service-Version: beta` for service versioning
- **Method-based routing**: Special handling for POST requests
- **Security rules**: Admin endpoint blocking with HTTP 403 responses

## Validation and Testing

After deployment, test the routing functionality:

```bash
# Get the service domain (available in outputs)
SERVICE_DOMAIN="your-lattice-service-domain"

# Test path-based routing
curl -v "http://${SERVICE_DOMAIN}/api/v1/"
curl -v "http://${SERVICE_DOMAIN}/"

# Test header-based routing
curl -v -H "X-Service-Version: beta" "http://${SERVICE_DOMAIN}/"

# Test security controls
curl -v "http://${SERVICE_DOMAIN}/admin"  # Should return 403
```

## Customization

### Key Variables/Parameters

- **Environment Name**: Prefix for all resource names
- **Instance Type**: EC2 instance size (default: t3.micro)
- **VPC CIDR Blocks**: Network addressing for created VPCs
- **Availability Zones**: Target AZs for multi-AZ deployment
- **Routing Rules**: Customize path, header, and method-based rules

### CloudFormation Parameters

```yaml
Parameters:
  EnvironmentName:
    Type: String
    Default: advanced-routing
  InstanceType:
    Type: String
    Default: t3.micro
  VpcCidr:
    Type: String
    Default: 10.1.0.0/16
```

### CDK Context Values

```json
{
  "environmentName": "advanced-routing",
  "instanceType": "t3.micro",
  "vpcCidr": "10.1.0.0/16"
}
```

### Terraform Variables

```hcl
variable "environment_name" {
  description = "Environment name prefix"
  type        = string
  default     = "advanced-routing"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}
```

## Monitoring and Observability

### CloudWatch Metrics

Monitor these key VPC Lattice metrics:

- `RequestCount`: Number of requests processed
- `TargetResponseTime`: Response time from ALB targets
- `HTTPCode_Target_2XX_Count`: Successful responses
- `HTTPCode_Target_4XX_Count`: Client errors
- `HTTPCode_Target_5XX_Count`: Server errors

### Health Checks

ALB target groups include health checks:
- Path: `/`
- Interval: 10 seconds
- Healthy threshold: 2 successes
- Unhealthy threshold: 3 failures

## Security Features

### IAM Authentication Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "vpc-lattice-svcs:Invoke",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:PrincipalAccount": "${AWS::AccountId}"
        }
      }
    },
    {
      "Effect": "Deny",
      "Principal": "*",
      "Action": "vpc-lattice-svcs:Invoke",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "vpc-lattice-svcs:RequestPath": "/admin"
        }
      }
    }
  ]
}
```

### Security Groups

- **ALB Security Group**: HTTP/HTTPS from VPC CIDR ranges
- **EC2 Security Group**: HTTP from ALB, SSH from VPC

## Security Considerations

This infrastructure implements several security best practices:

- **IAM Authentication**: VPC Lattice services use AWS IAM for access control
- **Internal Load Balancers**: ALBs are not internet-facing
- **Security Groups**: Restrictive ingress rules for minimal access
- **Path-based Security**: Admin endpoints blocked at the service mesh level
- **Account-based Access**: Service limited to same AWS account

## Cost Optimization

To reduce costs during testing:

1. **Use t3.micro instances**: Included in AWS Free Tier
2. **Deploy in single AZ**: Reduce cross-AZ data transfer costs
3. **Cleanup promptly**: VPC Lattice charges for active services
4. **Monitor usage**: Enable AWS Cost Explorer for tracking

## Cleanup

### Using CloudFormation

```bash
# Delete the stack and all resources
aws cloudformation delete-stack \
    --stack-name advanced-routing-lattice

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name advanced-routing-lattice
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/

# Destroy all resources
cdk destroy --force
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm all resources are removed
```

## Troubleshooting

### Common Issues

1. **VPC Lattice Service Not Accessible**:
   - Verify VPC associations with service network
   - Check IAM authentication policies
   - Ensure security groups allow traffic

2. **ALB Targets Unhealthy**:
   - Check EC2 instance status and user data execution
   - Verify security group rules for health checks
   - Review target group health check configuration

3. **Routing Rules Not Working**:
   - Verify rule priority order (lower numbers have higher priority)
   - Check rule matching conditions syntax
   - Ensure listener is attached to correct service

4. **Permission Errors**:
   - Verify IAM permissions for VPC Lattice operations
   - Check service-linked role creation permissions
   - Ensure cross-service IAM policies are correct

### Debugging Commands

```bash
# Check VPC Lattice service status
aws vpc-lattice get-service --service-identifier <service-id>

# List all routing rules
aws vpc-lattice list-rules \
    --service-identifier <service-id> \
    --listener-identifier <listener-id>

# Check ALB target health
aws elbv2 describe-target-health \
    --target-group-arn <target-group-arn>

# View service network associations
aws vpc-lattice list-service-network-vpc-associations \
    --service-network-identifier <network-id>
```

## Advanced Features

### Extending the Solution

1. **Multi-Region Deployment**: Deploy across multiple AWS regions with Route 53 health checks
2. **Weighted Routing**: Implement percentage-based traffic splitting for canary deployments
3. **Service Discovery**: Integrate with AWS App Mesh or Kubernetes for dynamic service registration
4. **Observability**: Add AWS X-Ray tracing and CloudWatch Container Insights
5. **Automation**: Create Lambda functions for dynamic policy updates based on compliance rules

### Integration Examples

```bash
# Add weighted routing for canary deployments
aws vpc-lattice create-rule \
    --service-identifier <service-id> \
    --listener-identifier <listener-id> \
    --name "canary-weighted-rule" \
    --priority 5 \
    --match '{"httpMatch":{"headerMatches":[{"name":"X-Canary","match":{"exact":"true"}}]}}' \
    --action '{"forward":{"targetGroups":[{"targetGroupIdentifier":"<canary-tg>","weight":20},{"targetGroupIdentifier":"<stable-tg>","weight":80}]}}'
```

## Support and Documentation

- **AWS VPC Lattice User Guide**: https://docs.aws.amazon.com/vpc-lattice/latest/ug/
- **ALB Integration**: https://docs.aws.amazon.com/vpc-lattice/latest/ug/alb-target.html
- **Authentication Policies**: https://docs.aws.amazon.com/vpc-lattice/latest/ug/auth-policies.html
- **Pricing Information**: https://aws.amazon.com/vpc-lattice/pricing/

For issues with this infrastructure code, refer to the original recipe documentation or open an issue in the repository.

## Version Information

- **Recipe Version**: 1.1
- **Last Updated**: 2025-07-12
- **IaC Generator Version**: 1.3
- **Supported AWS Regions**: All regions where VPC Lattice is available