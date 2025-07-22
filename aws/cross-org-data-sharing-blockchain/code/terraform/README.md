# Cross-Organization Data Sharing with Amazon Managed Blockchain - Terraform

This Terraform configuration deploys a complete cross-organization data sharing platform using Amazon Managed Blockchain with Hyperledger Fabric, Lambda functions for event processing, and supporting AWS services.

## Architecture Overview

The infrastructure includes:

- **Amazon Managed Blockchain Network**: Hyperledger Fabric network with configurable voting policies
- **Blockchain Members and Nodes**: Initial organization setup with peer nodes
- **AWS Lambda**: Event processing and data validation functions
- **Amazon S3**: Secure storage for shared data and chaincode
- **Amazon DynamoDB**: Audit trail storage for compliance
- **Amazon EventBridge**: Event routing for cross-organization notifications
- **Amazon SNS**: Notification delivery system
- **CloudWatch**: Monitoring and logging infrastructure
- **IAM**: Access control and security policies

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.0 installed
- Appropriate AWS permissions for:
  - Amazon Managed Blockchain
  - AWS Lambda
  - Amazon S3
  - Amazon DynamoDB
  - Amazon EventBridge
  - Amazon SNS
  - CloudWatch
  - IAM

## Quick Start

1. **Clone and Initialize**:
   ```bash
   git clone <repository>
   cd aws/cross-organization-data-sharing-managed-blockchain/code/terraform/
   terraform init
   ```

2. **Configure Variables**:
   ```bash
   # Copy example variables
   cp terraform.tfvars.example terraform.tfvars
   
   # Edit variables as needed
   vim terraform.tfvars
   ```

3. **Plan and Deploy**:
   ```bash
   # Review planned changes
   terraform plan
   
   # Deploy infrastructure
   terraform apply
   ```

4. **Verify Deployment**:
   ```bash
   # Check network status
   aws managedblockchain get-network --network-id $(terraform output -raw network_id)
   
   # List network members
   aws managedblockchain list-members --network-id $(terraform output -raw network_id)
   ```

## Configuration

### Required Variables

- `aws_region`: AWS region for deployment
- `environment`: Environment name (dev/staging/prod)

### Optional Customization

Key variables you may want to customize:

```hcl
# Blockchain configuration
network_name = "cross-org-network"
network_edition = "STANDARD"
framework_version = "2.2"

# Organization configuration
organization_a_name = "financial-institution"
organization_b_name = "healthcare-provider"

# Node configuration
node_instance_type = "bc.t3.medium"

# Lambda configuration
lambda_memory_size = 512
lambda_timeout = 60

# Voting policy
voting_threshold_percentage = 66
proposal_duration_hours = 24
```

### Security Configuration

The deployment includes several security features:

- **IAM Least Privilege**: Restrictive policies for all services
- **S3 Encryption**: Server-side encryption enabled
- **VPC Isolation**: Blockchain nodes deployed in private subnets
- **Access Logging**: Comprehensive audit trails in DynamoDB

## Adding Organization B

After initial deployment, invite a second organization:

1. **Create Proposal**:
   ```bash
   # Replace ACCOUNT_ID_OF_ORG_B with actual account ID
   aws managedblockchain create-proposal \
       --network-id $(terraform output -raw network_id) \
       --member-id $(terraform output -raw organization_a_member_id) \
       --actions '{"Invitations":[{"Principal":"ACCOUNT_ID_OF_ORG_B"}]}' \
       --description "Invite Organization B to cross-org network"
   ```

2. **Vote on Proposal**:
   ```bash
   # Get proposal ID from previous command output
   aws managedblockchain vote-on-proposal \
       --network-id $(terraform output -raw network_id) \
       --proposal-id PROPOSAL_ID \
       --voter-member-id $(terraform output -raw organization_a_member_id) \
       --vote YES
   ```

3. **Organization B Accepts**:
   ```bash
   # Run from Organization B's AWS account
   aws managedblockchain create-member \
       --invitation-id INVITATION_ID \
       --network-id NETWORK_ID \
       --member-configuration file://member-config.json
   ```

## Monitoring and Logging

### CloudWatch Dashboard

Access the monitoring dashboard:
```bash
# Get dashboard URL
terraform output cloudwatch_dashboard_url
```

### Lambda Logs

View Lambda function logs:
```bash
# Stream logs
aws logs tail $(terraform output -raw cloudwatch_log_group_name) --follow

# Query specific events
aws logs filter-log-events \
    --log-group-name $(terraform output -raw cloudwatch_log_group_name) \
    --filter-pattern "ERROR"
```

### Audit Trail

Query the audit trail:
```bash
# Recent audit events
aws dynamodb scan \
    --table-name $(terraform output -raw dynamodb_table_name) \
    --limit 10

# Specific agreement
aws dynamodb query \
    --table-name $(terraform output -raw dynamodb_table_name) \
    --key-condition-expression "AgreementId = :agreementId" \
    --expression-attribute-values '{":agreementId":{"S":"AGR-123"}}'
```

## Testing the Solution

### Simulate Data Sharing Events

Test the Lambda function with sample events:

```bash
# Create test event
cat > test-event.json << 'EOF'
{
  "eventType": "DataSharingAgreementCreated",
  "agreementId": "TEST-AGR-001",
  "organizationId": "test-org",
  "timestamp": 1640995200000,
  "metadata": {
    "title": "Test Agreement"
  }
}
EOF

# Invoke Lambda function
aws lambda invoke \
    --function-name $(terraform output -raw lambda_function_name) \
    --payload file://test-event.json \
    response.json

# Check response
cat response.json
```

### Verify EventBridge Processing

Check EventBridge metrics:
```bash
aws cloudwatch get-metric-statistics \
    --namespace AWS/Events \
    --metric-name MatchedEvents \
    --dimensions Name=RuleName,Value=$(terraform output -raw eventbridge_rule_name) \
    --start-time $(date -d '1 hour ago' --iso-8601) \
    --end-time $(date --iso-8601) \
    --period 300 \
    --statistics Sum
```

## Cost Optimization

### Instance Types

For development/testing:
```hcl
node_instance_type = "bc.t3.small"  # Lower cost option
```

For production:
```hcl
node_instance_type = "bc.m5.large"  # Better performance
```

### DynamoDB Capacity

For low traffic:
```hcl
audit_table_read_capacity = 1
audit_table_write_capacity = 1
```

Consider switching to on-demand billing for variable workloads.

## Troubleshooting

### Common Issues

1. **Network Creation Timeout**:
   - Network creation can take 5-10 minutes
   - Check AWS service health dashboard
   - Verify region supports Managed Blockchain

2. **Lambda Function Errors**:
   - Check CloudWatch logs for detailed error messages
   - Verify IAM permissions
   - Ensure DynamoDB table exists

3. **EventBridge Not Triggering**:
   - Verify event pattern matches your event structure
   - Check SNS topic permissions
   - Test with simple test events

### Debug Commands

```bash
# Check network status
aws managedblockchain describe-network --network-id $(terraform output -raw network_id)

# Verify Lambda permissions
aws lambda get-policy --function-name $(terraform output -raw lambda_function_name)

# Test SNS topic
aws sns publish \
    --topic-arn $(terraform output -raw sns_topic_arn) \
    --message "Test notification"
```

## Cleanup

To destroy all resources:

```bash
# Review what will be destroyed
terraform plan -destroy

# Destroy infrastructure
terraform destroy

# Confirm when prompted
```

**Note**: Blockchain network deletion may take several minutes. Some resources like CloudWatch logs may have retention periods.

## Security Considerations

### Production Deployment

For production environments:

1. **Enable VPC**: Deploy blockchain nodes in private subnets
2. **Rotate Credentials**: Use AWS Secrets Manager for admin passwords
3. **Enable Encryption**: Use KMS keys for additional encryption
4. **Network Security**: Implement security groups and NACLs
5. **Monitoring**: Set up CloudTrail and Config for compliance

### Compliance

This solution supports:
- **SOC 2**: Audit trails and access logging
- **HIPAA**: Encryption and access controls
- **GDPR**: Data sovereignty and right to erasure
- **SOX**: Immutable audit trails

## Support

For issues with this infrastructure:

1. Check the [AWS Managed Blockchain documentation](https://docs.aws.amazon.com/managed-blockchain/)
2. Review [Terraform AWS Provider documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
3. Consult the original recipe documentation

## Version History

- **v1.0**: Initial implementation with Hyperledger Fabric 2.2
- **v1.1**: Added CloudWatch monitoring and alarms
- **v1.2**: Enhanced security with IAM policies