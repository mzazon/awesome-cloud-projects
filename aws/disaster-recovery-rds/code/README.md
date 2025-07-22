# Infrastructure as Code for Implementing RDS Disaster Recovery Solutions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Implementing RDS Disaster Recovery Solutions".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured with appropriate credentials
- Existing RDS MySQL or PostgreSQL database instance in your primary region
- Permissions to create and manage:
  - RDS instances and read replicas
  - Lambda functions and IAM roles
  - EventBridge rules and CloudWatch alarms
  - SNS topics and subscriptions
  - CloudWatch dashboards
- Two AWS regions selected: primary region (where your database runs) and secondary region (for disaster recovery)
- Basic understanding of database concepts, RDS features, and disaster recovery principles

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CloudFormation permissions
- Ability to create IAM roles and policies

#### CDK TypeScript
- Node.js 16+ installed
- npm or yarn package manager
- AWS CDK CLI installed (`npm install -g aws-cdk`)

#### CDK Python
- Python 3.7+ installed
- pip package manager
- AWS CDK CLI installed (`pip install aws-cdk-lib`)

#### Terraform
- Terraform 1.0+ installed
- Basic understanding of HCL syntax

## Configuration

Before deploying any implementation, you'll need to configure the following parameters:

- **Source Database Identifier**: The identifier of your existing RDS database
- **Primary Region**: AWS region where your primary database is located
- **Secondary Region**: AWS region for disaster recovery resources
- **Notification Email**: Email address for disaster recovery alerts
- **Database Engine**: MySQL or PostgreSQL (auto-detected from source database)

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name rds-disaster-recovery \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=SourceDBIdentifier,ParameterValue=your-db-identifier \
                 ParameterKey=PrimaryRegion,ParameterValue=us-east-1 \
                 ParameterKey=SecondaryRegion,ParameterValue=us-west-2 \
                 ParameterKey=NotificationEmail,ParameterValue=admin@example.com \
    --capabilities CAPABILITY_IAM

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name rds-disaster-recovery \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name rds-disaster-recovery \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure your parameters in cdk.json or use context
npx cdk context --set sourceDBIdentifier=your-db-identifier
npx cdk context --set primaryRegion=us-east-1
npx cdk context --set secondaryRegion=us-west-2
npx cdk context --set notificationEmail=admin@example.com

# Bootstrap CDK (if not already done)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy

# View stack outputs
npx cdk deploy --outputs-file outputs.json
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure your parameters via environment variables
export SOURCE_DB_IDENTIFIER=your-db-identifier
export PRIMARY_REGION=us-east-1
export SECONDARY_REGION=us-west-2
export NOTIFICATION_EMAIL=admin@example.com

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack outputs
cdk deploy --outputs-file outputs.json
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your configuration
cat > terraform.tfvars << EOF
source_db_identifier = "your-db-identifier"
primary_region = "us-east-1"
secondary_region = "us-west-2"
notification_email = "admin@example.com"
environment = "production"
EOF

# Plan the deployment
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

# Set required environment variables
export SOURCE_DB_IDENTIFIER=your-db-identifier
export PRIMARY_REGION=us-east-1
export SECONDARY_REGION=us-west-2
export NOTIFICATION_EMAIL=admin@example.com

# Deploy the infrastructure
./scripts/deploy.sh

# The script will:
# 1. Validate prerequisites
# 2. Create cross-region read replica
# 3. Set up monitoring and alerting
# 4. Deploy Lambda automation
# 5. Create CloudWatch dashboard
```

## Post-Deployment Verification

After successful deployment, verify your disaster recovery setup:

1. **Check Read Replica Status**:
   ```bash
   aws rds describe-db-instances \
       --db-instance-identifier your-replica-name \
       --region $SECONDARY_REGION \
       --query "DBInstances[0].{Status:DBInstanceStatus,Lag:StatusInfos}"
   ```

2. **Verify SNS Subscriptions**:
   - Check your email for subscription confirmation messages
   - Confirm all subscriptions to receive notifications

3. **Test CloudWatch Dashboard**:
   - Navigate to CloudWatch in AWS Console
   - Locate your disaster recovery dashboard
   - Verify metrics are populating correctly

4. **Review Lambda Function Logs**:
   ```bash
   aws logs describe-log-groups \
       --log-group-name-prefix "/aws/lambda/rds-dr-manager"
   ```

## Monitoring and Alerting

The deployed solution includes comprehensive monitoring:

- **CPU Utilization**: Alerts when database CPU exceeds 80%
- **Replica Lag**: Notifications when replication lag exceeds 5 minutes
- **Connection Health**: Alerts for database connection issues
- **Automated Response**: Lambda functions process alerts and take appropriate actions

### CloudWatch Dashboard

Access your disaster recovery dashboard at:
```
https://console.aws.amazon.com/cloudwatch/home?region=${PRIMARY_REGION}#dashboards:name=rds-dr-dashboard-${RANDOM_SUFFIX}
```

## Disaster Recovery Procedures

### Manual Failover Process

In case of a disaster requiring database failover:

1. **Assess the Situation**:
   - Verify primary database is truly unavailable
   - Check recent backup and replica lag status

2. **Promote Read Replica**:
   ```bash
   aws rds promote-read-replica \
       --db-instance-identifier your-replica-name \
       --region $SECONDARY_REGION
   ```

3. **Update Application Configuration**:
   - Update database connection strings to point to promoted replica
   - Update DNS records if using custom domain names
   - Restart applications to use new database endpoint

4. **Verify Data Integrity**:
   - Perform application-level health checks
   - Verify critical data is accessible and accurate

### Recovery Time and Point Objectives

- **RTO (Recovery Time Objective)**: 5-15 minutes for manual failover
- **RPO (Recovery Point Objective)**: Typically under 5 seconds (depends on replica lag)

## Cost Considerations

Estimated monthly costs for disaster recovery infrastructure:

- **Read Replica**: Approximately equal to primary database instance cost
- **Data Transfer**: $0.02/GB for cross-region replication
- **SNS Notifications**: $0.50 per million notifications
- **Lambda**: Minimal cost for monitoring functions
- **CloudWatch**: Standard monitoring and dashboard charges

### Cost Optimization Tips

- Use smaller instance types for read replicas in non-critical environments
- Consider automated scaling based on primary database load
- Implement lifecycle policies for CloudWatch logs retention

## Security Best Practices

The deployed infrastructure follows AWS security best practices:

- **Least Privilege IAM**: Lambda functions have minimal required permissions
- **Encryption**: Read replicas inherit encryption settings from source database
- **Network Security**: Resources deployed in appropriate VPC subnets
- **Monitoring**: All actions logged to CloudTrail

### Additional Security Recommendations

- Enable VPC Flow Logs for network monitoring
- Use AWS Systems Manager Parameter Store for sensitive configuration
- Implement database activity monitoring with Performance Insights
- Regular security assessments of IAM policies

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name rds-disaster-recovery

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name rds-disaster-recovery
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
npx cdk destroy
```

### Using CDK Python

```bash
cd cdk-python/
source .venv/bin/activate  # If using virtual environment
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy

# Confirm destruction when prompted
# Type 'yes' to proceed with resource deletion
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh

# The script will:
# 1. Prompt for confirmation
# 2. Delete resources in proper order
# 3. Verify successful cleanup
```

## Customization

### Common Customizations

1. **Adjust Monitoring Thresholds**:
   - Modify CloudWatch alarm thresholds based on your performance baselines
   - Add custom metrics for application-specific monitoring

2. **Enhanced Automation**:
   - Implement automatic failover for non-critical environments
   - Add integration with configuration management systems

3. **Multi-Region Expansion**:
   - Deploy read replicas to multiple regions
   - Implement intelligent routing based on geographic location

4. **Backup Integration**:
   - Coordinate with existing backup strategies
   - Implement point-in-time recovery procedures

### Variable Definitions

Refer to the variable definitions in each implementation:

- **CloudFormation**: Check `Parameters` section in cloudformation.yaml
- **CDK**: Review parameter definitions in stack constructors
- **Terraform**: See variables.tf file for all configurable options
- **Bash Scripts**: Environment variables documented in script headers

## Troubleshooting

### Common Issues

1. **Read Replica Creation Fails**:
   - Verify source database is in available state
   - Check cross-region permissions and quotas
   - Ensure automated backups are enabled on source database

2. **Lambda Function Errors**:
   - Check CloudWatch Logs for detailed error messages
   - Verify IAM permissions for RDS and SNS operations
   - Ensure environment variables are correctly configured

3. **CloudWatch Alarms Not Triggering**:
   - Verify metric names and dimensions
   - Check alarm threshold values against actual metrics
   - Ensure SNS topic permissions allow CloudWatch to publish

4. **Email Notifications Not Received**:
   - Check SNS subscription status (must be confirmed)
   - Verify email address is correctly configured
   - Check spam/junk folders for notification emails

### Support Resources

- [AWS RDS User Guide](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/)
- [Disaster Recovery Best Practices](https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/)
- [AWS Support Center](https://console.aws.amazon.com/support/)

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation for detailed implementation guidance
2. Check AWS service documentation for specific resource configurations
3. Consult AWS Support for service-specific issues
4. Review CloudWatch Logs for Lambda function execution details

## Contributing

To improve this infrastructure code:

1. Test changes in non-production environments
2. Follow AWS best practices for security and performance
3. Update documentation to reflect any modifications
4. Consider backward compatibility with existing deployments