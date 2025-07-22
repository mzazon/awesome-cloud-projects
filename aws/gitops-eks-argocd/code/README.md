# Infrastructure as Code for GitOps for EKS with ArgoCD

This directory contains Infrastructure as Code (IaC) implementations for the recipe "GitOps for EKS with ArgoCD".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- kubectl installed (version 1.24 or later)
- eksctl installed (version 0.140.0 or later)
- Helm CLI installed (version 3.8 or later)
- ArgoCD CLI installed (optional but recommended)
- Git configured with appropriate CodeCommit credentials
- Appropriate AWS IAM permissions for:
  - Amazon EKS cluster creation and management
  - AWS CodeCommit repository creation and access
  - IAM role and policy creation
  - Application Load Balancer provisioning
  - VPC and networking resource management

## Architecture Overview

This implementation creates:

- **Amazon EKS Cluster**: Managed Kubernetes control plane with worker nodes
- **AWS CodeCommit Repository**: Git repository for GitOps configuration storage
- **ArgoCD Installation**: GitOps continuous delivery tool deployed on EKS
- **Application Load Balancer**: External access to ArgoCD web interface
- **IAM Roles and Policies**: Secure access control for all components
- **Sample Application**: Demonstration workload managed via GitOps

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name gitops-eks-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ClusterName,ParameterValue=gitops-cluster \
                 ParameterKey=RepoName,ParameterValue=gitops-config-repo \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name gitops-eks-stack

# Update kubeconfig for cluster access
aws eks update-kubeconfig \
    --region $(aws configure get region) \
    --name gitops-cluster
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Deploy the stack
cdk deploy --require-approval never

# Update kubeconfig after deployment
aws eks update-kubeconfig \
    --region $(aws configure get region) \
    --name $(cdk output ClusterName)
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Deploy the stack
cdk deploy --require-approval never

# Update kubeconfig after deployment
aws eks update-kubeconfig \
    --region $(aws configure get region) \
    --name $(cdk output ClusterName)
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply the configuration
terraform apply -auto-approve

# Update kubeconfig after deployment
aws eks update-kubeconfig \
    --region $(terraform output -raw aws_region) \
    --name $(terraform output -raw cluster_name)
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will automatically update kubeconfig
```

## Post-Deployment Configuration

After deploying the infrastructure, complete the GitOps setup:

### 1. Access ArgoCD

```bash
# Get ArgoCD admin password
ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret \
    -n argocd \
    -o jsonpath='{.data.password}' | base64 -d)

# Get ArgoCD URL
ARGOCD_URL=$(kubectl get ingress argocd-server-ingress \
    -n argocd \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "ArgoCD URL: https://${ARGOCD_URL}"
echo "Username: admin"
echo "Password: ${ARGOCD_PASSWORD}"
```

### 2. Configure Git Repository

```bash
# Get CodeCommit repository URL
REPO_URL=$(aws codecommit get-repository \
    --repository-name gitops-config-repo \
    --query 'repositoryMetadata.cloneUrlHttp' \
    --output text)

# Clone and set up repository structure
git clone ${REPO_URL} gitops-repo
cd gitops-repo

# Create GitOps directory structure
mkdir -p {applications,environments}/{development,staging,production}
mkdir -p manifests/base

# Create sample application manifests
cat > manifests/base/deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-app
  labels:
    app: sample-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: sample-app
  template:
    metadata:
      labels:
        app: sample-app
    spec:
      containers:
      - name: nginx
        image: nginx:1.21
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "250m"
          limits:
            memory: "128Mi"
            cpu: "500m"
EOF

cat > manifests/base/service.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: sample-app-service
spec:
  selector:
    app: sample-app
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
  type: ClusterIP
EOF

cat > manifests/base/kustomization.yaml << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml
EOF

# Create ArgoCD application
cat > applications/development/sample-app.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sample-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ${REPO_URL}
    targetRevision: HEAD
    path: manifests/base
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

# Commit and push
git add .
git commit -m "Initial GitOps configuration"
git push origin main
```

### 3. Deploy Application via ArgoCD

```bash
# Apply the ArgoCD application
kubectl apply -f applications/development/sample-app.yaml

# Verify deployment
kubectl get applications -n argocd
kubectl get pods -l app=sample-app
```

## Validation

### Verify Infrastructure

```bash
# Check EKS cluster status
kubectl get nodes

# Verify ArgoCD components
kubectl get pods -n argocd

# Check application status
kubectl get applications -n argocd
kubectl get pods -l app=sample-app
```

### Test GitOps Workflow

```bash
cd gitops-repo

# Modify application configuration
sed -i 's/replicas: 2/replicas: 3/' manifests/base/deployment.yaml

# Commit and push changes
git add manifests/base/deployment.yaml
git commit -m "Scale sample application to 3 replicas"
git push origin main

# Wait for ArgoCD to sync (automated)
sleep 60
kubectl get pods -l app=sample-app
```

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name gitops-eks-stack

# Wait for stack deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name gitops-eks-stack
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
cdk destroy --force
```

### Using CDK Python

```bash
cd cdk-python/
source .venv/bin/activate  # If using virtual environment
cdk destroy --force
```

### Using Terraform

```bash
cd terraform/
terraform destroy -auto-approve
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Customization

### Key Variables/Parameters

- **ClusterName**: Name for the EKS cluster
- **RepoName**: Name for the CodeCommit repository
- **NodeInstanceType**: EC2 instance type for EKS worker nodes
- **MinSize/MaxSize**: Auto Scaling Group size limits
- **KubernetesVersion**: EKS cluster version

### Environment-Specific Configuration

1. **Development**: Single-node cluster, minimal resources
2. **Staging**: Multi-node cluster, moderate resources
3. **Production**: High-availability cluster, enhanced monitoring

### Security Customization

- Modify IAM roles and policies for least privilege access
- Configure VPC security groups for network isolation
- Enable EKS encryption for etcd and secrets
- Implement Pod Security Standards

## Troubleshooting

### Common Issues

1. **EKS Cluster Creation Fails**
   - Check IAM permissions for EKS service role
   - Verify VPC and subnet configurations
   - Ensure sufficient IP addresses in subnets

2. **ArgoCD Access Issues**
   - Verify ALB provisioning and DNS resolution
   - Check security group configurations
   - Validate ingress annotations

3. **GitOps Sync Failures**
   - Verify CodeCommit repository permissions
   - Check ArgoCD repository connection
   - Validate Kubernetes manifest syntax

### Debugging Commands

```bash
# Check EKS cluster status
aws eks describe-cluster --name gitops-cluster

# View ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server

# Check application sync status
kubectl describe application sample-app -n argocd

# View pod events
kubectl describe pod -l app=sample-app
```

## Cost Optimization

- Use Spot instances for development environments
- Configure cluster autoscaler for dynamic scaling
- Implement Horizontal Pod Autoscaler for applications
- Monitor costs with AWS Cost Explorer
- Schedule non-production cluster shutdown

## Security Best Practices

- Enable VPC Flow Logs for network monitoring
- Implement AWS Config for compliance monitoring
- Use AWS Secrets Manager for sensitive data
- Enable CloudTrail for audit logging
- Implement network policies for pod-to-pod communication

## Support

For issues with this infrastructure code:

1. Refer to the original recipe documentation
2. Check AWS EKS documentation
3. Review ArgoCD documentation
4. Consult AWS support for account-specific issues

## Additional Resources

- [Amazon EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [AWS CodeCommit User Guide](https://docs.aws.amazon.com/codecommit/latest/userguide/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [GitOps Best Practices](https://opengitops.dev/)