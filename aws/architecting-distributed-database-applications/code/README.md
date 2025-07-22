# Infrastructure as Code for Architecting Distributed Database Applications with Aurora DSQL

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Architecting Distributed Database Applications with Aurora DSQL".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation creates a multi-region distributed application architecture using:

- **Aurora DSQL**: Serverless, distributed SQL database with active-active multi-region configuration
- **AWS Lambda**: Serverless compute functions for business logic processing
- **Amazon EventBridge**: Event-driven coordination layer for cross-region communication
- **IAM**: Secure role-based access control for service interactions

The architecture spans three regions:
- Primary Region (us-east-1): Active processing and database operations
- Secondary Region (us-west-2): Active processing and database operations
- Witness Region (eu-west-1): Transaction log storage for distributed consensus

## Prerequisites

### AWS Account Requirements
- AWS CLI v2 installed and configured with appropriate permissions
- Access to Aurora DSQL (preview service) in supported regions
- IAM permissions for creating:
  - Aurora DSQL clusters and multi-region configurations
  - Lambda functions and execution roles
  - EventBridge custom buses, rules, and targets
  - IAM roles and policies

### Service Limits and Quotas
- Aurora DSQL cluster limits in each region
- Lambda function execution time and memory limits
- EventBridge rule and target limits

### Cost Considerations
- Aurora DSQL compute and storage costs across multiple regions
- Lambda invocation and execution time charges
- EventBridge event processing fees
- Data transfer costs between regions
- Estimated monthly cost: $50-100 for development workloads

### Required Permissions
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "dsql:*",
                "lambda:*",
                "events:*",
                "iam:CreateRole",
                "iam:AttachRolePolicy",
                "iam:CreatePolicy",
                "sts:GetCallerIdentity"
            ],
            "Resource": "*"
        }
    ]
}
```

## Quick Start

### Using CloudFormation
```bash
# Deploy the complete stack
aws cloudformation create-stack \
    --stack-name aurora-dsql-distributed-app \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=PrimaryRegion,ParameterValue=us-east-1 \
                 ParameterKey=SecondaryRegion,ParameterValue=us-west-2 \
                 ParameterKey=WitnessRegion,ParameterValue=eu-west-1 \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name aurora-dsql-distributed-app \
    --region us-east-1

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name aurora-dsql-distributed-app \
    --region us-east-1 \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Configure deployment regions (optional)
export CDK_PRIMARY_REGION=us-east-1
export CDK_SECONDARY_REGION=us-west-2
export CDK_WITNESS_REGION=eu-west-1

# Bootstrap CDK in all regions (if not done previously)
cdk bootstrap aws://ACCOUNT-ID/us-east-1
cdk bootstrap aws://ACCOUNT-ID/us-west-2
cdk bootstrap aws://ACCOUNT-ID/eu-west-1

# Deploy the application
cdk deploy --all

# View deployed resources
cdk ls
```

### Using CDK Python
```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure deployment regions (optional)
export CDK_PRIMARY_REGION=us-east-1
export CDK_SECONDARY_REGION=us-west-2
export CDK_WITNESS_REGION=eu-west-1

# Bootstrap CDK in all regions (if not done previously)
cdk bootstrap aws://ACCOUNT-ID/us-east-1
cdk bootstrap aws://ACCOUNT-ID/us-west-2
cdk bootstrap aws://ACCOUNT-ID/eu-west-1

# Deploy the application
cdk deploy --all

# View deployed resources
cdk ls
```

### Using Terraform
```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Run deployment script
./scripts/deploy.sh

# Follow the interactive prompts for region configuration
```

## Deployment Configuration

### Environment Variables
Set these environment variables to customize your deployment:

```bash
# Regional configuration
export PRIMARY_REGION=us-east-1
export SECONDARY_REGION=us-west-2
export WITNESS_REGION=eu-west-1

# Resource naming
export CLUSTER_NAME_PREFIX=my-app-cluster
export LAMBDA_FUNCTION_PREFIX=my-dsql-processor
export EVENTBRIDGE_BUS_PREFIX=my-dsql-events

# Optional: Custom resource tags
export ENVIRONMENT=production
export APPLICATION=distributed-app
export OWNER=team-name
```

### CloudFormation Parameters
- `PrimaryRegion`: Primary AWS region for Aurora DSQL cluster (default: us-east-1)
- `SecondaryRegion`: Secondary AWS region for Aurora DSQL cluster (default: us-west-2)
- `WitnessRegion`: Witness region for transaction logs (default: eu-west-1)
- `ClusterNameSuffix`: Unique suffix for cluster naming (auto-generated if not provided)
- `Environment`: Environment tag value (default: production)

### Terraform Variables
Configure these variables in `terraform.tfvars`:

```hcl
primary_region    = "us-east-1"
secondary_region  = "us-west-2"
witness_region    = "eu-west-1"
cluster_name_suffix = "prod"
environment       = "production"
application_name  = "distributed-app"

# Optional: Custom Lambda configuration
lambda_runtime    = "python3.9"
lambda_timeout    = 30
lambda_memory_size = 256

# Optional: EventBridge configuration
enable_cross_region_replication = true
event_retention_days = 7
```

## Post-Deployment Validation

### Test Aurora DSQL Connectivity
```bash
# Test primary cluster connectivity
aws dsql execute-statement \
    --region us-east-1 \
    --cluster-identifier $(terraform output -raw primary_cluster_id) \
    --sql "SELECT 1 as test_connection"

# Test secondary cluster connectivity
aws dsql execute-statement \
    --region us-west-2 \
    --cluster-identifier $(terraform output -raw secondary_cluster_id) \
    --sql "SELECT 1 as test_connection"
```

### Test Lambda Function Execution
```bash
# Test primary region Lambda function
aws lambda invoke \
    --region us-east-1 \
    --function-name $(terraform output -raw primary_lambda_function_name) \
    --payload '{"operation":"read"}' \
    --cli-binary-format raw-in-base64-out \
    response.json

cat response.json
```

### Verify Multi-Region Consistency
```bash
# Write data in primary region
aws lambda invoke \
    --region us-east-1 \
    --function-name $(terraform output -raw primary_lambda_function_name) \
    --payload '{"operation":"write","transaction_id":"test-001","amount":100.50}' \
    --cli-binary-format raw-in-base64-out \
    write_response.json

# Wait for replication
sleep 3

# Read data from secondary region
aws lambda invoke \
    --region us-west-2 \
    --function-name $(terraform output -raw secondary_lambda_function_name) \
    --payload '{"operation":"read"}' \
    --cli-binary-format raw-in-base64-out \
    read_response.json

# Compare results to verify consistency
echo "Write result:"
cat write_response.json
echo "Read result:"
cat read_response.json
```

## Monitoring and Troubleshooting

### Aurora DSQL Monitoring
```bash
# Check cluster status
aws dsql describe-clusters \
    --region us-east-1 \
    --query 'clusters[?clusterIdentifier==`$(terraform output -raw primary_cluster_id)`].[status,createdTime]'

# Monitor multi-region configuration
aws dsql describe-multi-region-clusters \
    --region us-east-1 \
    --primary-cluster-identifier $(terraform output -raw primary_cluster_id)
```

### Lambda Function Monitoring
```bash
# Check function status
aws lambda get-function \
    --region us-east-1 \
    --function-name $(terraform output -raw primary_lambda_function_name) \
    --query 'Configuration.[FunctionName,State,LastUpdateStatus]'

# View recent logs
aws logs tail /aws/lambda/$(terraform output -raw primary_lambda_function_name) \
    --since 1h --follow
```

### EventBridge Monitoring
```bash
# List rules and their status
aws events list-rules \
    --region us-east-1 \
    --event-bus-name $(terraform output -raw eventbridge_bus_name)

# Check rule targets
aws events list-targets-by-rule \
    --region us-east-1 \
    --rule CrossRegionReplication \
    --event-bus-name $(terraform output -raw eventbridge_bus_name)
```

### Common Issues and Solutions

#### Aurora DSQL Connection Issues
- Verify cluster status is "available"
- Check IAM permissions for Aurora DSQL access
- Ensure Lambda execution role has proper policies attached

#### Lambda Function Errors
- Review CloudWatch logs for detailed error messages
- Verify environment variables are correctly set
- Check function timeout and memory configuration

#### EventBridge Event Processing Issues
- Verify event bus and rule configurations
- Check dead letter queue for failed events
- Monitor CloudWatch metrics for rule invocation count

## Cleanup

### Using CloudFormation
```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name aurora-dsql-distributed-app \
    --region us-east-1

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name aurora-dsql-distributed-app \
    --region us-east-1
```

### Using CDK
```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy all stacks
cdk destroy --all

# Confirm destruction when prompted
```

### Using Terraform
```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Follow interactive prompts for confirmation
```

### Manual Cleanup Verification
After using any cleanup method, verify all resources are removed:

```bash
# Check Aurora DSQL clusters
aws dsql describe-clusters --region us-east-1
aws dsql describe-clusters --region us-west-2

# Check Lambda functions
aws lambda list-functions --region us-east-1 | grep dsql-processor
aws lambda list-functions --region us-west-2 | grep dsql-processor

# Check EventBridge buses
aws events list-event-buses --region us-east-1 | grep dsql-events
aws events list-event-buses --region us-west-2 | grep dsql-events

# Check IAM roles
aws iam list-roles | grep DSQLLambdaRole
```

## Customization

### Adding Additional Regions
To add more regions to the multi-region configuration:

1. Update the configuration files to include additional region parameters
2. Deploy Lambda functions and EventBridge buses in the new regions
3. Configure cross-region event replication rules
4. Update Aurora DSQL multi-region cluster configuration

### Modifying Lambda Functions
To customize the Lambda function behavior:

1. Update the function code in the respective implementation directory
2. Modify environment variables and resource configurations
3. Adjust IAM policies if additional AWS services are needed
4. Redeploy using your chosen IaC method

### Scaling Configuration
For production workloads, consider:

- Lambda reserved concurrency settings
- EventBridge rule filtering for efficiency
- Aurora DSQL performance monitoring and optimization
- CloudWatch alarms for proactive monitoring
- Cost optimization through resource scheduling

## Security Considerations

### IAM Best Practices
- Use least privilege principle for all IAM roles
- Enable CloudTrail for API call auditing
- Regularly rotate access keys and review permissions
- Use IAM conditions to restrict access based on IP, time, or MFA

### Network Security
- Configure VPC endpoints for secure service communication
- Implement security groups with minimal required access
- Enable VPC Flow Logs for network traffic monitoring
- Consider AWS PrivateLink for enhanced security

### Data Protection
- Aurora DSQL encrypts data at rest by default
- Enable encryption in transit for all connections
- Implement application-level encryption for sensitive data
- Configure backup and retention policies

## Performance Optimization

### Aurora DSQL Optimization
- Monitor query performance and optimize SQL statements
- Use appropriate indexes for query patterns
- Implement connection pooling in application code
- Monitor and adjust auto-scaling parameters

### Lambda Optimization
- Right-size memory allocation based on actual usage
- Implement proper error handling and retries
- Use Lambda layers for common dependencies
- Enable X-Ray tracing for performance insights

### EventBridge Optimization
- Use specific event patterns to reduce unnecessary processing
- Implement batch processing where appropriate
- Monitor and optimize rule evaluation performance
- Consider event filtering at the source

## Support and Documentation

For additional support and detailed documentation:

- [Aurora DSQL Documentation](https://docs.aws.amazon.com/aurora-dsql/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/)
- [Amazon EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation or create an issue in the repository.

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment first
2. Follow the established coding standards for each implementation
3. Update documentation to reflect any changes
4. Validate changes across all supported IaC methods
5. Submit improvements via pull request

## License

This infrastructure code is provided under the same license as the parent repository. Please refer to the repository's LICENSE file for details.