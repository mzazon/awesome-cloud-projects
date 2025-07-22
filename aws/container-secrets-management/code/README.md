# Infrastructure as Code for Container Secrets Management with Secrets Manager

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Container Secrets Management with Secrets Manager".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- kubectl installed and configured for EKS cluster access
- Helm v3 installed for CSI driver deployment
- Appropriate AWS permissions for:
  - AWS Secrets Manager
  - Amazon ECS
  - Amazon EKS
  - AWS IAM
  - AWS Lambda
  - AWS KMS
  - Amazon CloudWatch
  - AWS CloudTrail
- Basic understanding of container orchestration and IAM roles
- Estimated cost: $10-20/month for secrets storage and rotation

## Architecture Overview

This solution implements comprehensive container secrets management using:

- **AWS Secrets Manager** for centralized secret storage with automatic rotation
- **Amazon ECS** with native secrets integration via task roles
- **Amazon EKS** with Secrets Store CSI Driver and AWS Secrets and Configuration Provider (ASCP)
- **AWS Lambda** for automatic secret rotation
- **AWS KMS** for encryption at rest
- **Amazon CloudWatch** for monitoring and alerting
- **AWS IAM** for fine-grained access control

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name container-secrets-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=ClusterName,ParameterValue=my-secrets-cluster \
                 ParameterKey=SecretName,ParameterValue=my-app-secrets

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name container-secrets-stack \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name container-secrets-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# Get outputs
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

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# Get outputs
cdk output
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# Get outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will:
# 1. Create KMS key for encryption
# 2. Create secrets in AWS Secrets Manager
# 3. Set up IAM roles and policies
# 4. Create ECS cluster and task definitions
# 5. Create EKS cluster
# 6. Install Secrets Store CSI Driver
# 7. Configure IRSA for EKS
# 8. Deploy sample applications
# 9. Set up Lambda for automatic rotation
# 10. Configure monitoring and alerting
```

## Post-Deployment Configuration

### EKS Cluster Access

After deployment, configure kubectl access to your EKS cluster:

```bash
# Update kubeconfig
aws eks update-kubeconfig --name <cluster-name>

# Verify cluster access
kubectl get nodes
```

### Install Secrets Store CSI Driver (if not automated)

```bash
# Add Helm repositories
helm repo add secrets-store-csi-driver \
    https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts

helm repo add aws-secrets-manager \
    https://aws.github.io/secrets-store-csi-driver-provider-aws

helm repo update

# Install CSI Driver
helm install csi-secrets-store \
    secrets-store-csi-driver/secrets-store-csi-driver \
    --namespace kube-system \
    --set syncSecret.enabled=true \
    --set enableSecretRotation=true

# Install AWS Provider
helm install secrets-provider-aws \
    aws-secrets-manager/secrets-store-csi-driver-provider-aws \
    --namespace kube-system
```

## Testing the Deployment

### Test ECS Secrets Integration

```bash
# Get cluster name from outputs
CLUSTER_NAME=$(aws cloudformation describe-stacks \
    --stack-name container-secrets-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`ECSClusterName`].OutputValue' \
    --output text)

# Run a test task
aws ecs run-task \
    --cluster $CLUSTER_NAME \
    --task-definition "${CLUSTER_NAME}-task" \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[subnet-xxx],assignPublicIp=ENABLED}"

# Check task logs
aws logs describe-log-streams \
    --log-group-name "/ecs/${CLUSTER_NAME}"
```

### Test EKS Secrets Mount

```bash
# Verify pod is running
kubectl get pods -l app=demo-app

# Check mounted secrets
POD_NAME=$(kubectl get pods -l app=demo-app -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD_NAME -- ls -la /mnt/secrets/

# Verify environment variables
kubectl exec $POD_NAME -- env | grep -E "(DB_USERNAME|DB_PASSWORD)"
```

### Test Secret Rotation

```bash
# Get secret ARN from outputs
SECRET_ARN=$(aws cloudformation describe-stacks \
    --stack-name container-secrets-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`DatabaseSecretArn`].OutputValue' \
    --output text)

# Check rotation status
aws secretsmanager describe-secret \
    --secret-id $SECRET_ARN \
    --query 'RotationEnabled'

# Trigger manual rotation
aws secretsmanager rotate-secret --secret-id $SECRET_ARN
```

## Monitoring and Maintenance

### CloudWatch Monitoring

Access CloudWatch to monitor:
- Secret access patterns
- Rotation success/failure rates
- Unauthorized access attempts
- Application performance metrics

### Security Best Practices

1. **Regular Rotation**: Ensure automatic rotation is enabled and functioning
2. **Access Review**: Regularly review IAM policies and access patterns
3. **Audit Logging**: Monitor CloudTrail logs for secret access
4. **Least Privilege**: Follow principle of least privilege for IAM roles
5. **Encryption**: Verify KMS encryption is properly configured

### Troubleshooting

Common issues and solutions:

1. **ECS Task Fails to Start**: Check IAM task role permissions
2. **EKS Pod Can't Mount Secrets**: Verify IRSA configuration and CSI driver installation
3. **Rotation Fails**: Check Lambda function logs and IAM permissions
4. **Access Denied**: Review IAM policies and secret resource policies

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name container-secrets-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name container-secrets-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# TypeScript
cd cdk-typescript/
cdk destroy

# Python
cd cdk-python/
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# 1. Delete Kubernetes resources
# 2. Uninstall Helm charts
# 3. Delete EKS cluster
# 4. Delete ECS resources
# 5. Delete Lambda function
# 6. Delete secrets (with force delete)
# 7. Schedule KMS key deletion
# 8. Clean up CloudWatch resources
# 9. Remove local files
```

## Customization

### Key Parameters

- **ClusterName**: Name for ECS and EKS clusters
- **SecretName**: Base name for secrets in Secrets Manager
- **KMSKeyId**: Custom KMS key for encryption
- **RotationSchedule**: Automatic rotation frequency (days)
- **VPCConfiguration**: Custom VPC settings
- **LogRetentionDays**: CloudWatch log retention period

### Environment Variables

The bash scripts use these environment variables:
- `AWS_REGION`: Target AWS region
- `CLUSTER_NAME`: Cluster identifier
- `SECRET_NAME`: Secret base name
- `KMS_KEY_ID`: KMS key for encryption

### Extending the Solution

Consider these enhancements:

1. **Multi-Region Deployment**: Replicate secrets across regions
2. **Custom Rotation Logic**: Implement service-specific rotation functions
3. **Additional Monitoring**: Enhanced CloudWatch dashboards and alarms
4. **Cost Optimization**: Implement secret lifecycle policies
5. **Compliance**: Add AWS Config rules for secret management compliance

## Cost Considerations

Estimated monthly costs:
- AWS Secrets Manager: $0.40 per secret per month
- KMS: $1.00 per key per month + $0.03 per 10,000 requests
- Lambda: $0.20 per 1M requests (rotation functions)
- CloudWatch: $0.50 per dashboard + log storage costs
- ECS/EKS: Depends on compute resources used

## Security Considerations

- All secrets are encrypted at rest using KMS
- IAM roles follow least privilege principle
- Network access is restricted through VPC configuration
- Audit logging is enabled through CloudTrail
- Rotation reduces credential exposure risk

## Support

For issues with this infrastructure code, refer to:
- [Original recipe documentation](../container-secrets-management-aws-secrets-manager.md)
- [AWS Secrets Manager documentation](https://docs.aws.amazon.com/secretsmanager/)
- [ECS secrets integration guide](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/secrets-envvar-secrets-manager.html)
- [EKS secrets management guide](https://docs.aws.amazon.com/eks/latest/userguide/manage-secrets.html)
- [Secrets Store CSI Driver documentation](https://secrets-store-csi-driver.sigs.k8s.io/)

## License

This code is provided under the MIT License. See LICENSE file for details.