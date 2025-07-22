# Infrastructure as Code for HIPAA-Compliant Healthcare Analytics

This directory contains Infrastructure as Code (IaC) implementations for the recipe "HIPAA-Compliant Healthcare Analytics".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI version 2.0 or later installed and configured
- Appropriate AWS permissions for:
  - AWS HealthLake (create/manage data stores)
  - AWS Lambda (create/manage functions)
  - Amazon S3 (create/manage buckets)
  - Amazon EventBridge (create/manage rules)
  - AWS IAM (create/manage roles and policies)
- Basic understanding of FHIR R4 specification and healthcare data formats
- Knowledge of HIPAA compliance requirements for healthcare data
- Estimated cost: $50-100 for testing (varies by data volume and processing frequency)

> **Note**: AWS HealthLake is a HIPAA-eligible service. Ensure your AWS account is configured for HIPAA compliance before deploying.

## Architecture Overview

This solution deploys:

- **AWS HealthLake FHIR Data Store**: HIPAA-compliant, petabyte-scale data lake for healthcare data
- **Lambda Functions**: Serverless compute for data processing and analytics
- **S3 Buckets**: Storage for input data, output analytics, and logs
- **EventBridge Rules**: Event-driven architecture for real-time processing
- **IAM Roles**: Security and access control for services

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name healthcare-data-pipeline \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=DataStoreName,ParameterValue=my-healthcare-datastore \
                 ParameterKey=Environment,ParameterValue=dev

# Monitor stack creation
aws cloudformation wait stack-create-complete \
    --stack-name healthcare-data-pipeline

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name healthcare-data-pipeline \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters datastoreName=my-healthcare-datastore

# View outputs
cdk output
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

# Deploy the stack
cdk deploy --parameters datastore_name=my-healthcare-datastore

# View outputs
cdk output
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy infrastructure
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

# Follow the script prompts and monitor deployment progress
```

## Configuration Options

### CloudFormation Parameters

- `DataStoreName`: Name for the HealthLake FHIR data store
- `Environment`: Environment name (dev, test, prod)
- `InputBucketName`: Custom name for input S3 bucket (optional)
- `OutputBucketName`: Custom name for output S3 bucket (optional)

### CDK Configuration

Edit the configuration variables in the CDK app files:

- **TypeScript**: Modify variables in `app.ts`
- **Python**: Modify variables in `app.py`

### Terraform Variables

Configure deployment by setting variables in `terraform.tfvars`:

```hcl
datastore_name = "my-healthcare-datastore"
environment    = "dev"
aws_region     = "us-east-1"

# Optional: Custom bucket names
input_bucket_name  = "my-healthcare-input-bucket"
output_bucket_name = "my-healthcare-output-bucket"
```

## Testing the Deployment

After deployment, test the infrastructure:

1. **Upload Sample FHIR Data**:
   ```bash
   # Create sample patient data
   cat > patient-sample.json << 'EOF'
   {
     "resourceType": "Patient",
     "id": "patient-001",
     "active": true,
     "name": [{"use": "usual", "family": "Doe", "given": ["John"]}],
     "gender": "male",
     "birthDate": "1985-03-15"
   }
   EOF
   
   # Upload to input bucket
   aws s3 cp patient-sample.json s3://YOUR_INPUT_BUCKET/fhir-data/
   ```

2. **Start Import Job**:
   ```bash
   # Get the data store ID from stack outputs
   DATASTORE_ID=$(aws cloudformation describe-stacks \
       --stack-name healthcare-data-pipeline \
       --query 'Stacks[0].Outputs[?OutputKey==`DataStoreId`].OutputValue' \
       --output text)
   
   # Start import job
   aws healthlake start-fhir-import-job \
       --input-data-config S3Uri=s3://YOUR_INPUT_BUCKET/fhir-data/ \
       --output-data-config S3Uri=s3://YOUR_OUTPUT_BUCKET/import-logs/ \
       --datastore-id $DATASTORE_ID \
       --data-access-role-arn YOUR_HEALTHLAKE_ROLE_ARN
   ```

3. **Monitor Processing**:
   ```bash
   # Check Lambda function logs
   aws logs tail /aws/lambda/YOUR_PROCESSOR_FUNCTION_NAME --follow
   
   # Check analytics outputs in S3
   aws s3 ls s3://YOUR_OUTPUT_BUCKET/analytics/ --recursive
   ```

## Security Considerations

This implementation follows AWS security best practices:

- **Encryption**: All S3 buckets use AES-256 encryption
- **IAM Roles**: Least privilege access for all services
- **VPC**: Optional VPC deployment for network isolation
- **HIPAA Compliance**: HealthLake provides HIPAA-eligible infrastructure
- **Audit Logging**: CloudTrail integration for API monitoring

## Cost Optimization

To minimize costs during testing:

1. **Use Smaller Data Sets**: Start with sample data to understand pricing
2. **Monitor Usage**: Set up billing alerts for unexpected charges
3. **Clean Up Regularly**: Use the destroy scripts after testing
4. **Right-Size Resources**: Adjust Lambda memory and timeout settings

## Monitoring and Troubleshooting

### CloudWatch Dashboards

The deployment creates CloudWatch dashboards for monitoring:

- HealthLake import/export job status
- Lambda function performance and errors
- S3 bucket access patterns
- EventBridge rule invocations

### Common Issues

1. **Import Job Failures**:
   - Check FHIR data format compliance
   - Verify S3 bucket permissions
   - Review CloudWatch logs for detailed errors

2. **Lambda Timeouts**:
   - Increase function timeout settings
   - Optimize code for better performance
   - Consider using Step Functions for long-running processes

3. **Access Denied Errors**:
   - Verify IAM role permissions
   - Check S3 bucket policies
   - Ensure HealthLake service role is properly configured

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name healthcare-data-pipeline

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name healthcare-data-pipeline
```

### Using CDK

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
./scripts/destroy.sh
```

## Advanced Customization

### Adding Custom Analytics

Extend the analytics Lambda function to include:

1. **Patient Cohort Analysis**: Group patients by conditions or treatments
2. **Clinical Decision Support**: Generate alerts for critical conditions
3. **Population Health Metrics**: Calculate aggregate health indicators
4. **Quality Measures**: Track healthcare quality indicators

### Integration Patterns

1. **Real-time Streaming**: Connect Kinesis Data Streams for real-time data ingestion
2. **Machine Learning**: Integrate Amazon SageMaker for predictive analytics
3. **Data Lakes**: Export to S3 for integration with Amazon Athena or EMR
4. **APIs**: Create API Gateway endpoints for external system integration

### Multi-Region Deployment

For disaster recovery and high availability:

1. Deploy HealthLake data stores in multiple regions
2. Set up cross-region replication for S3 buckets
3. Configure EventBridge cross-region rules
4. Implement automated failover mechanisms

## Compliance and Governance

### HIPAA Compliance Checklist

- [ ] AWS Business Associate Agreement (BAA) signed
- [ ] Encryption enabled for all data at rest and in transit
- [ ] Access logging enabled for all resources
- [ ] IAM roles follow least privilege principle
- [ ] Data retention policies configured
- [ ] Audit trails enabled via CloudTrail

### Data Governance

- **Data Classification**: Tag resources with appropriate data sensitivity levels
- **Access Controls**: Implement role-based access control (RBAC)
- **Data Lineage**: Track data flow through the pipeline
- **Retention Policies**: Configure automated data lifecycle management

## Support and Resources

- [AWS HealthLake Documentation](https://docs.aws.amazon.com/healthlake/)
- [FHIR R4 Specification](https://hl7.org/fhir/R4/)
- [AWS HIPAA Compliance Guide](https://docs.aws.amazon.com/whitepapers/latest/architecting-hipaa-security-and-compliance-on-aws/welcome.html)
- [Healthcare Data on AWS](https://aws.amazon.com/health/)

For issues with this infrastructure code, refer to the original recipe documentation or AWS support channels.

## Contributing

When modifying this infrastructure code:

1. Test all changes in a development environment
2. Follow AWS Well-Architected Framework principles
3. Update documentation for any configuration changes
4. Validate HIPAA compliance impact of modifications
5. Consider cost implications of infrastructure changes