# Infrastructure as Code for Private API Integration with VPC Lattice and EventBridge

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Private API Integration with VPC Lattice and EventBridge".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - VPC Lattice (service networks, resource gateways, resource configurations)
  - EventBridge (custom buses, rules, connections)
  - Step Functions (state machines)
  - API Gateway (private APIs)
  - IAM (roles and policies)
  - VPC (endpoints, subnets)
  - EC2 (VPC and subnet creation)
- Understanding of VPC networking and event-driven architectures
- Estimated cost: $2-5 for testing resources

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI with CloudFormation permissions

#### CDK TypeScript
- Node.js 18.x or later
- AWS CDK CLI v2 (`npm install -g aws-cdk`)

#### CDK Python
- Python 3.8 or later
- AWS CDK CLI v2 (`pip install aws-cdk-lib`)

#### Terraform
- Terraform 1.0 or later
- AWS Provider 5.0 or later

## Quick Start

### Using CloudFormation (AWS)
```bash
aws cloudformation create-stack \
    --stack-name private-api-lattice-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=demo
```

### Using CDK TypeScript (AWS)
```bash
cd cdk-typescript/
npm install
npx cdk bootstrap  # First time only
npx cdk deploy
```

### Using CDK Python (AWS)
```bash
cd cdk-python/
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt
cdk bootstrap  # First time only
cdk deploy
```

### Using Terraform
```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

### Using Bash Scripts
```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Architecture Overview

This implementation creates:

- **VPC Infrastructure**: Target VPC with multi-AZ subnets for high availability
- **VPC Lattice Components**: Service network, resource gateway, and resource configuration
- **Private API Gateway**: HTTPS endpoints accessible only within VPC boundaries
- **EventBridge Integration**: Custom bus, connection, and rules for event-driven workflows
- **Step Functions**: State machine for orchestrating private API calls
- **IAM Security**: Least-privilege roles and policies for secure cross-VPC communication

## Validation & Testing

After deployment, test the solution:

1. **Verify VPC Lattice Status**:
   ```bash
   # Check service network
   aws vpc-lattice list-service-networks
   
   # Verify resource configuration
   aws vpc-lattice list-resource-configurations
   ```

2. **Test EventBridge Integration**:
   ```bash
   # Send test event
   aws events put-events \
       --entries '[{
           "Source": "demo.application",
           "DetailType": "Order Received",
           "Detail": "{\"orderId\": \"test-123\"}",
           "EventBusName": "CUSTOM_BUS_NAME"
       }]'
   ```

3. **Monitor Step Functions Execution**:
   ```bash
   # List executions
   aws stepfunctions list-executions \
       --state-machine-arn STATE_MACHINE_ARN
   ```

## Cleanup

### Using CloudFormation (AWS)
```bash
aws cloudformation delete-stack --stack-name private-api-lattice-stack
```

### Using CDK (AWS)
```bash
cd cdk-typescript/  # or cdk-python/
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

### Key Variables/Parameters

- **Environment**: Deployment environment (demo, dev, prod)
- **VPC CIDR**: Network range for target VPC (default: 10.1.0.0/16)
- **Region**: AWS region for deployment
- **Resource Names**: Customizable naming prefixes for all resources

### CloudFormation Parameters
Modify the `Parameters` section in `cloudformation.yaml`:
- `Environment`: Environment tag for resources
- `VpcCidr`: CIDR block for target VPC
- `ResourcePrefix`: Prefix for resource names

### CDK Configuration
Update the `cdk.json` context or environment variables:
- Set deployment region and account
- Customize resource naming patterns
- Configure environment-specific settings

### Terraform Variables
Modify `terraform/variables.tf` or create `terraform.tfvars`:
```hcl
environment = "production"
vpc_cidr = "10.2.0.0/16"
resource_prefix = "myorg"
```

## Security Considerations

This implementation follows AWS security best practices:

- **Network Isolation**: Private API accessible only through VPC endpoints
- **IAM Least Privilege**: Minimal permissions for EventBridge and Step Functions
- **VPC Lattice Security**: Resource-based policies for cross-VPC access
- **Encryption**: HTTPS encryption for all API communications
- **No Public Internet**: All traffic stays within AWS backbone network

## Troubleshooting

### Common Issues

1. **VPC Lattice Association Delays**: Resource associations may take 30-60 seconds to become active
2. **API Gateway Endpoint Resolution**: Ensure VPC endpoint DNS resolution is enabled
3. **Step Functions Permissions**: Verify IAM roles have sufficient permissions for HTTP tasks
4. **EventBridge Connection Failures**: Check resource configuration ARN in connection settings

### Debugging Commands

```bash
# Check VPC Lattice resource status
aws vpc-lattice get-resource-configuration --resource-configuration-identifier RESOURCE_CONFIG_ARN

# Verify API Gateway VPC endpoint
aws ec2 describe-vpc-endpoints --filters Name=service-name,Values=com.amazonaws.REGION.execute-api

# Monitor Step Functions execution
aws stepfunctions describe-execution --execution-arn EXECUTION_ARN

# View EventBridge rule targets
aws events list-targets-by-rule --rule RULE_NAME --event-bus-name BUS_NAME
```

## Performance and Cost Optimization

- **VPC Lattice**: Pay-per-use pricing with no upfront costs
- **API Gateway**: Consider caching strategies for frequently accessed data
- **Step Functions**: Optimize state machine design to minimize transitions
- **EventBridge**: Use event filtering to reduce unnecessary processing

## Support

For issues with this infrastructure code:

1. Refer to the original recipe documentation for architectural guidance
2. Check AWS service documentation for latest API changes
3. Review CloudFormation/CDK/Terraform provider documentation for syntax updates
4. Monitor AWS service health dashboard for regional issues

## Related AWS Documentation

- [VPC Lattice User Guide](https://docs.aws.amazon.com/vpc-lattice/latest/ug/)
- [EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)
- [Step Functions Developer Guide](https://docs.aws.amazon.com/step-functions/latest/dg/)
- [API Gateway Developer Guide](https://docs.aws.amazon.com/apigateway/latest/developerguide/)
- [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/)