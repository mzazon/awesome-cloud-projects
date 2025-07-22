# Infrastructure as Code for EKS Monitoring with CloudWatch Container Insights

This directory contains Infrastructure as Code (IaC) implementations for the recipe "EKS Monitoring with CloudWatch Container Insights".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- kubectl installed and configured with EKS cluster access
- eksctl installed (for IRSA configuration)
- Running Amazon EKS cluster (version 1.21 or later)
- IAM permissions for CloudWatch, SNS, EKS, and IAM operations
- Node.js 18+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)

## Quick Start

### Using CloudFormation
```bash
# Set required environment variables
export CLUSTER_NAME=your-eks-cluster-name
export AWS_REGION=us-west-2
export EMAIL_ADDRESS=your-email@example.com

# Deploy the CloudFormation stack
aws cloudformation create-stack \
    --stack-name eks-monitoring-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ClusterName,ParameterValue=$CLUSTER_NAME \
                 ParameterKey=EmailAddress,ParameterValue=$EMAIL_ADDRESS \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --region $AWS_REGION

# Wait for stack completion
aws cloudformation wait stack-create-complete \
    --stack-name eks-monitoring-stack \
    --region $AWS_REGION

# Deploy Kubernetes monitoring components
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cloudwatch-namespace.yaml

# Configure IRSA for CloudWatch agent
eksctl create iamserviceaccount \
    --name cloudwatch-agent \
    --namespace amazon-cloudwatch \
    --cluster $CLUSTER_NAME \
    --region $AWS_REGION \
    --attach-policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy \
    --approve \
    --override-existing-serviceaccounts

# Deploy CloudWatch agent and Fluent Bit
curl -s https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-daemonset.yaml | \
sed "s/{{cluster_name}}/$CLUSTER_NAME/;s/{{region_name}}/$AWS_REGION/" | \
kubectl apply -f -

curl -s https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/fluent-bit/fluent-bit.yaml | \
sed "s/{{cluster_name}}/$CLUSTER_NAME/;s/{{region_name}}/$AWS_REGION/;s/{{http_server_toggle}}/On/;s/{{http_server_port}}/2020/;s/{{read_from_head}}/Off/;s/{{read_from_tail}}/On/" | \
kubectl apply -f -
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Set environment variables
export CLUSTER_NAME=your-eks-cluster-name
export EMAIL_ADDRESS=your-email@example.com

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters clusterName=$CLUSTER_NAME \
           --parameters emailAddress=$EMAIL_ADDRESS

# Deploy Kubernetes monitoring components (same as CloudFormation steps above)
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cloudwatch-namespace.yaml

eksctl create iamserviceaccount \
    --name cloudwatch-agent \
    --namespace amazon-cloudwatch \
    --cluster $CLUSTER_NAME \
    --region $AWS_REGION \
    --attach-policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy \
    --approve \
    --override-existing-serviceaccounts

curl -s https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-daemonset.yaml | \
sed "s/{{cluster_name}}/$CLUSTER_NAME/;s/{{region_name}}/$AWS_REGION/" | \
kubectl apply -f -

curl -s https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/fluent-bit/fluent-bit.yaml | \
sed "s/{{cluster_name}}/$CLUSTER_NAME/;s/{{region_name}}/$AWS_REGION/;s/{{http_server_toggle}}/On/;s/{{http_server_port}}/2020/;s/{{read_from_head}}/Off/;s/{{read_from_tail}}/On/" | \
kubectl apply -f -
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export CLUSTER_NAME=your-eks-cluster-name
export EMAIL_ADDRESS=your-email@example.com

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters clusterName=$CLUSTER_NAME \
           --parameters emailAddress=$EMAIL_ADDRESS

# Deploy Kubernetes monitoring components (same as CloudFormation steps above)
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cloudwatch-namespace.yaml

eksctl create iamserviceaccount \
    --name cloudwatch-agent \
    --namespace amazon-cloudwatch \
    --cluster $CLUSTER_NAME \
    --region $AWS_REGION \
    --attach-policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy \
    --approve \
    --override-existing-serviceaccounts

curl -s https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-daemonset.yaml | \
sed "s/{{cluster_name}}/$CLUSTER_NAME/;s/{{region_name}}/$AWS_REGION/" | \
kubectl apply -f -

curl -s https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/fluent-bit/fluent-bit.yaml | \
sed "s/{{cluster_name}}/$CLUSTER_NAME/;s/{{region_name}}/$AWS_REGION/;s/{{http_server_toggle}}/On/;s/{{http_server_port}}/2020/;s/{{read_from_head}}/Off/;s/{{read_from_tail}}/On/" | \
kubectl apply -f -
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
cluster_name = "your-eks-cluster-name"
email_address = "your-email@example.com"
aws_region = "us-west-2"
EOF

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply

# Note: Terraform will handle both AWS resources and Kubernetes deployments
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export CLUSTER_NAME=your-eks-cluster-name
export EMAIL_ADDRESS=your-email@example.com
export AWS_REGION=us-west-2

# Deploy the complete monitoring solution
./scripts/deploy.sh
```

## Validation

After deployment, validate the monitoring setup:

1. **Check CloudWatch metrics**:
   ```bash
   aws cloudwatch list-metrics \
       --namespace ContainerInsights \
       --dimensions Name=ClusterName,Value=$CLUSTER_NAME
   ```

2. **Verify monitoring pods are running**:
   ```bash
   kubectl get pods -n amazon-cloudwatch
   ```

3. **Test alerting** (optional):
   ```bash
   kubectl run cpu-stress --image=progrium/stress \
       -- stress --cpu 2 --timeout 300s
   ```

4. **Access Container Insights dashboard**:
   - Navigate to CloudWatch > Insights > Container Insights
   - Select your cluster name
   - Verify metrics and performance data are displayed

## Cleanup

### Using CloudFormation
```bash
# Delete Kubernetes resources first
kubectl delete namespace amazon-cloudwatch

# Delete IRSA service account
eksctl delete iamserviceaccount \
    --name cloudwatch-agent \
    --namespace amazon-cloudwatch \
    --cluster $CLUSTER_NAME \
    --region $AWS_REGION

# Delete CloudFormation stack
aws cloudformation delete-stack \
    --stack-name eks-monitoring-stack \
    --region $AWS_REGION

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name eks-monitoring-stack \
    --region $AWS_REGION
```

### Using CDK TypeScript/Python
```bash
# Delete Kubernetes resources first
kubectl delete namespace amazon-cloudwatch

# Delete IRSA service account
eksctl delete iamserviceaccount \
    --name cloudwatch-agent \
    --namespace amazon-cloudwatch \
    --cluster $CLUSTER_NAME \
    --region $AWS_REGION

# Destroy CDK stack
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

## Customization

### CloudFormation Parameters
- `ClusterName`: Name of your EKS cluster
- `EmailAddress`: Email address for SNS notifications
- `CPUThreshold`: CPU utilization alarm threshold (default: 80)
- `MemoryThreshold`: Memory utilization alarm threshold (default: 85)

### CDK Context Variables
Modify `cdk.json` or use CDK context:
```bash
cdk deploy -c clusterName=my-cluster -c emailAddress=admin@company.com
```

### Terraform Variables
Edit `terraform.tfvars` or pass variables:
```bash
terraform apply -var="cluster_name=my-cluster" -var="email_address=admin@company.com"
```

### Bash Script Environment Variables
Set these environment variables before running scripts:
- `CLUSTER_NAME`: Your EKS cluster name
- `EMAIL_ADDRESS`: Email for notifications
- `AWS_REGION`: AWS region (default: us-west-2)
- `CPU_THRESHOLD`: CPU alarm threshold (default: 80)
- `MEMORY_THRESHOLD`: Memory alarm threshold (default: 85)

## Architecture Components

This infrastructure deploys:

1. **SNS Topic**: For alert notifications
2. **CloudWatch Alarms**: For CPU, memory, and failed pods monitoring
3. **IAM Roles**: For CloudWatch agent permissions via IRSA
4. **Kubernetes Resources**: CloudWatch agent and Fluent Bit DaemonSets
5. **Container Insights**: Enhanced observability for EKS cluster

## Monitoring Features

- **Infrastructure Metrics**: Node and pod CPU, memory, disk, and network utilization
- **Application Logs**: Centralized log collection from all containers
- **Control Plane Logs**: EKS API server, audit, and scheduler logs
- **Automated Alerting**: Proactive notifications for resource thresholds
- **Dashboards**: Pre-built Container Insights dashboards in CloudWatch

## Security Considerations

- Uses IAM Roles for Service Accounts (IRSA) for secure AWS access
- Follows least privilege principle for IAM permissions
- SNS topic uses encryption in transit
- CloudWatch logs are encrypted at rest
- No long-lived credentials stored in Kubernetes

## Cost Optimization

- Fluent Bit configured for efficient log processing
- CloudWatch alarms use appropriate evaluation periods to avoid false positives
- Container Insights enhanced observability provides detailed metrics while optimizing cost
- Log retention policies can be configured to manage storage costs

## Troubleshooting

1. **CloudWatch agent not starting**: Check IRSA configuration and IAM permissions
2. **No metrics in Container Insights**: Verify cluster name matches in all configurations
3. **Alarms not triggering**: Check metric namespaces and dimension names
4. **High log costs**: Review Fluent Bit configuration and log filtering

## Support

For issues with this infrastructure code, refer to:
- [Original recipe documentation](../eks-cloudwatch-container-insights.md)
- [AWS Container Insights documentation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html)
- [Amazon EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [AWS CloudWatch documentation](https://docs.aws.amazon.com/cloudwatch/)