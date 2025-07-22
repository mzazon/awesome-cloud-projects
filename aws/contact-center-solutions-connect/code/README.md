# Infrastructure as Code for Contact Center Solutions with Amazon Connect

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Contact Center Solutions with Amazon Connect".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a complete cloud-based contact center infrastructure including:

- Amazon Connect instance with inbound/outbound calling
- S3 bucket for call recordings and chat transcripts
- Administrative and agent user accounts
- Customer service queue with routing configuration
- Contact flow for intelligent call handling
- CloudWatch monitoring and analytics
- Phone number provisioning (toll-free when available)

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with administrative permissions for:
  - Amazon Connect
  - S3
  - IAM
  - CloudWatch
- For CDK implementations:
  - Node.js 18+ (for TypeScript)
  - Python 3.8+ (for Python)
  - CDK CLI installed (`npm install -g aws-cdk`)
- For Terraform:
  - Terraform 1.0+ installed
- Phone number for testing contact center functionality
- Estimated cost: $2-5 per day for testing (pay-per-use pricing)

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name contact-center-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ContactCenterAlias,ParameterValue=my-contact-center

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name contact-center-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# View outputs
cdk outputs
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# View outputs
cdk outputs
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply configuration
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

# The script will prompt for configuration values and deploy all resources
```

## Post-Deployment Configuration

After successful deployment, you'll need to:

1. **Access the Connect Console**:
   - Navigate to Amazon Connect in AWS Console
   - Open your instance using the instance alias
   - Log in with the admin credentials (connect-admin/TempPass123!)

2. **Claim a Phone Number** (if not done automatically):
   - Go to Routing → Phone numbers
   - Claim a toll-free or DID number
   - Associate with your contact flow

3. **Configure Additional Settings**:
   - Set up hours of operation
   - Configure agent schedules
   - Customize contact flows as needed
   - Set up additional queues and routing profiles

4. **Test the Contact Center**:
   - Have an agent log in to the Contact Control Panel (CCP)
   - Call the claimed phone number
   - Verify call routing and recording functionality

## Key Configuration Options

### CloudFormation Parameters
- `ContactCenterAlias`: Unique identifier for your Connect instance
- `EnableCallRecording`: Whether to enable call recording (default: true)
- `EnableContactLens`: Whether to enable Contact Lens analytics (default: true)

### CDK Configuration
Edit the configuration in the respective CDK app files:
- Instance alias and region settings
- Storage bucket configuration
- User and queue configurations
- Contact flow definitions

### Terraform Variables
Configure in `terraform.tfvars`:
```hcl
contact_center_alias = "my-contact-center"
aws_region = "us-east-1"
enable_call_recording = true
enable_contact_lens = true
```

## Monitoring and Analytics

The deployment includes CloudWatch integration for monitoring:

- **Real-time Metrics**: Contact volume, agent status, queue performance
- **Historical Reports**: Call trends, agent productivity, customer satisfaction
- **Contact Lens Analytics**: AI-powered conversation analysis and sentiment detection
- **Custom Dashboards**: Pre-configured CloudWatch dashboards for key metrics

Access monitoring through:
- Amazon Connect real-time metrics dashboard
- CloudWatch console for detailed metrics
- Contact Lens for conversation analytics

## Security Considerations

This implementation follows AWS security best practices:

- **IAM Roles**: Least privilege access for all components
- **Data Encryption**: S3 buckets encrypted at rest
- **Call Recording**: Secure storage in S3 with appropriate access controls
- **User Management**: Separate security profiles for admins and agents
- **Network Security**: VPC isolation where applicable

## Customization Options

### Adding Additional Queues
Modify the queue configuration in your chosen IaC tool to add specialized queues:
- Technical support queue
- Billing inquiries queue
- Sales queue

### Skills-Based Routing
Extend the routing profiles to include agent skills:
- Language skills
- Product expertise
- Seniority levels

### Integration with External Systems
Add integrations with:
- CRM systems (Salesforce, ServiceNow)
- Knowledge bases
- Customer databases
- Third-party analytics tools

### Advanced Contact Flows
Enhance contact flows with:
- Interactive Voice Response (IVR)
- Callback functionality
- Queue callback options
- Integration with Amazon Lex chatbots

## Cleanup

### Using CloudFormation
```bash
# Delete the stack and all resources
aws cloudformation delete-stack --stack-name contact-center-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name contact-center-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
# From the CDK directory
cdk destroy

# Confirm deletion when prompted
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

## Cost Optimization

To minimize costs during testing:

1. **Limited Agent Hours**: Only staff agents during testing periods
2. **Call Volume Management**: Limit test calls to necessary validation
3. **Resource Cleanup**: Remove resources immediately after testing
4. **Regional Selection**: Deploy in regions with lower Connect pricing

## Troubleshooting

### Common Issues

**Phone Number Claiming Fails**:
- Check regional availability of toll-free numbers
- Try DID numbers if toll-free unavailable
- Manually claim through Connect console

**Agent Login Issues**:
- Verify user creation and security profile assignment
- Check password requirements and force password reset
- Ensure proper routing profile configuration

**Call Recording Not Working**:
- Verify S3 bucket permissions
- Check contact flow recording configuration
- Confirm storage association with Connect instance

**Contact Flow Errors**:
- Validate JSON syntax in contact flow definition
- Ensure queue ARNs are correctly formatted
- Check for missing action transitions

### Getting Help

- Review AWS Connect documentation: https://docs.aws.amazon.com/connect/
- Check AWS Connect limits and quotas
- Use AWS Support for deployment issues
- Refer to the original recipe for step-by-step guidance

## Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Refer to the original recipe documentation
3. Consult AWS Connect documentation
4. Use AWS Support for production issues

## Additional Resources

- [Amazon Connect Admin Guide](https://docs.aws.amazon.com/connect/latest/adminguide/)
- [Amazon Connect API Reference](https://docs.aws.amazon.com/connect/latest/APIReference/)
- [Contact Flow Language Reference](https://docs.aws.amazon.com/connect/latest/adminguide/contact-flow-language.html)
- [Amazon Connect Pricing](https://aws.amazon.com/connect/pricing/)