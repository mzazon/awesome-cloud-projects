---
title: EKS Ingress with AWS Load Balancer Controller
id: 51b618d0
category: containers
difficulty: 300
subject: aws
services: eks,elbv2,ec2,iam
estimated-time: 180 minutes
recipe-version: 1.3
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: 2025-07-23
passed-qa: null
tags: eks,alb,nlb,ec2,route53,ingress
recipe-generator-version: 1.3
---

# EKS Ingress with AWS Load Balancer Controller

## Problem

Organizations running containerized applications on Kubernetes face complex challenges when managing external traffic routing, load balancing, and SSL termination. Traditional ingress controllers require manual configuration of AWS load balancers, lack integration with AWS services like WAF and ACM, and provide limited visibility into application performance. Without proper ingress management, teams struggle with inconsistent routing rules, security vulnerabilities, and inability to leverage AWS-native features for high availability and scalability.

## Solution

The AWS Load Balancer Controller automates the provisioning and management of AWS Application Load Balancers (ALB) and Network Load Balancers (NLB) for Kubernetes ingress resources. This solution provides native AWS integration, automatic SSL certificate management, advanced routing capabilities, and seamless integration with AWS security services like WAF and Shield Advanced.

## Architecture Diagram

```mermaid
graph TB
    subgraph "Internet"
        CLIENT[Client Requests]
    end
    
    subgraph "AWS Route 53"
        DNS[DNS Resolution]
    end
    
    subgraph "VPC"
        subgraph "Public Subnets"
            ALB[Application Load Balancer]
            NLB[Network Load Balancer]
        end
        
        subgraph "Private Subnets"
            subgraph "EKS Cluster"
                subgraph "Control Plane"
                    API[EKS API Server]
                end
                
                subgraph "Worker Nodes"
                    subgraph "Node 1"
                        LBC[Load Balancer Controller]
                        POD1[App Pod 1]
                    end
                    
                    subgraph "Node 2"
                        POD2[App Pod 2]
                        POD3[App Pod 3]
                    end
                    
                    subgraph "Node 3"
                        POD4[App Pod 4]
                        POD5[App Pod 5]
                    end
                end
            end
        end
    end
    
    subgraph "AWS Services"
        ACM[Certificate Manager]
        WAF[Web Application Firewall]
        CW[CloudWatch]
        IAM[IAM Roles]
    end
    
    CLIENT --> DNS
    DNS --> ALB
    DNS --> NLB
    ALB --> POD1
    ALB --> POD2
    ALB --> POD3
    NLB --> POD4
    NLB --> POD5
    
    LBC --> API
    LBC --> ALB
    LBC --> NLB
    
    ALB -.-> ACM
    ALB -.-> WAF
    ALB -.-> CW
    LBC -.-> IAM
    
    style ALB fill:#FF9900
    style NLB fill:#FF9900
    style EKS fill:#3F8624
    style LBC fill:#FF4B4B
```

## Prerequisites

1. AWS account with appropriate permissions for EKS, Elastic Load Balancing, IAM, and Route 53
2. AWS CLI v2 installed and configured (or AWS CloudShell)
3. kubectl (version 1.22 or later) installed and configured
4. Helm 3.x installed
5. eksctl installed (optional, for cluster creation)
6. Basic knowledge of Kubernetes concepts and AWS networking
7. Existing VPC with proper subnet tagging or ability to create new VPC
8. Estimated cost: $100-200/month for EKS cluster, ALB/NLB, and associated resources

> **Note**: This recipe assumes you have an existing EKS cluster. If you need to create one, add approximately 1 hour for cluster setup.

## Preparation

```bash
# Set environment variables
export AWS_REGION=$(aws configure get region)
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
    --query Account --output text)

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword)

export CLUSTER_NAME="eks-ingress-demo-${RANDOM_SUFFIX}"
export DOMAIN_NAME="demo-${RANDOM_SUFFIX}.example.com"
export NAMESPACE="ingress-demo"

# Create EKS cluster (if you don't have one)
eksctl create cluster \
    --name $CLUSTER_NAME \
    --region $AWS_REGION \
    --nodes 3 \
    --node-type t3.medium \
    --managed \
    --version 1.30

# Update kubeconfig
aws eks update-kubeconfig \
    --region $AWS_REGION \
    --name $CLUSTER_NAME

# Verify cluster connectivity
kubectl get nodes

# Create namespace for demo applications
kubectl create namespace $NAMESPACE

echo "✅ AWS environment configured"
```

## Steps

1. **Create IAM Service Account for AWS Load Balancer Controller**:

   IAM Roles for Service Accounts (IRSA) enables secure, fine-grained permissions for Kubernetes service accounts by mapping them to AWS IAM roles. This eliminates the need for hardcoded credentials and follows the principle of least privilege access. The AWS Load Balancer Controller requires specific IAM permissions to create and manage ALBs and NLBs on your behalf, making this security configuration essential for proper operation.

   ```bash
   # Create IAM OIDC identity provider for the cluster
   eksctl utils associate-iam-oidc-provider \
       --region $AWS_REGION \
       --cluster $CLUSTER_NAME \
       --approve
   
   # Download the latest IAM policy document
   curl -o iam-policy.json https://raw.githubusercontent.com/\
   kubernetes-sigs/aws-load-balancer-controller/v2.13.3/docs/install/iam_policy.json
   
   # Create the IAM policy
   POLICY_ARN=$(aws iam create-policy \
       --policy-name AWSLoadBalancerControllerIAMPolicy-${RANDOM_SUFFIX} \
       --policy-document file://iam-policy.json \
       --query 'Policy.Arn' --output text)
   
   echo "✅ Created IAM policy: $POLICY_ARN"
   ```

   The OIDC identity provider enables secure token exchange between Kubernetes and AWS IAM, while the IAM policy grants the controller permissions to manage Elastic Load Balancing resources. This foundation ensures the controller can automatically provision and configure load balancers based on your ingress specifications while maintaining AWS security best practices.

2. **Create Service Account with IAM Role**:

   The service account acts as the identity for the AWS Load Balancer Controller pods, enabling them to assume the IAM role and interact with AWS APIs. This step combines Kubernetes RBAC with AWS IAM to create a secure, least-privilege access model that eliminates the need for storing AWS credentials as secrets.

   ```bash
   # Create service account with IAM role
   eksctl create iamserviceaccount \
       --cluster=$CLUSTER_NAME \
       --namespace=kube-system \
       --name=aws-load-balancer-controller \
       --role-name=AmazonEKSLoadBalancerControllerRole-${RANDOM_SUFFIX} \
       --attach-policy-arn=$POLICY_ARN \
       --approve
   
   # Verify the service account was created with IAM role annotation
   kubectl get serviceaccount aws-load-balancer-controller \
       -n kube-system -o yaml | grep eks.amazonaws.com/role-arn
   
   echo "✅ Created service account with IAM role"
   ```

   The service account is now configured with the necessary IAM permissions to manage AWS load balancers. This security model ensures that only the controller pods can perform load balancer operations, maintaining strict access controls while enabling automated infrastructure management through IRSA integration.

3. **Install AWS Load Balancer Controller using Helm**:

   The AWS Load Balancer Controller is a Kubernetes controller that watches for ingress resources and automatically provisions AWS Application Load Balancers (ALB) and Network Load Balancers (NLB). Installing it via Helm ensures proper configuration and enables easy upgrades. Version 2.13.3 includes enhanced performance improvements, security fixes, and Layer 4 Gateway API support.

   ```bash
   # Add the EKS Helm repository
   helm repo add eks https://aws.github.io/eks-charts
   helm repo update
   
   # Install the AWS Load Balancer Controller
   helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
       -n kube-system \
       --set clusterName=$CLUSTER_NAME \
       --set serviceAccount.create=false \
       --set serviceAccount.name=aws-load-balancer-controller \
       --set region=$AWS_REGION \
       --set vpcId=$(aws eks describe-cluster --name $CLUSTER_NAME \
           --query 'cluster.resourcesVpcConfig.vpcId' --output text) \
       --set image.tag=v2.13.3
   
   # Wait for controller to be ready
   kubectl wait --for=condition=ready pod \
       -l app.kubernetes.io/name=aws-load-balancer-controller \
       -n kube-system --timeout=300s
   
   echo "✅ AWS Load Balancer Controller v2.13.3 installed successfully"
   ```

   The controller is now running in your cluster and ready to respond to ingress resources. It will automatically create and configure AWS load balancers based on your ingress specifications, providing seamless integration between Kubernetes networking and AWS load balancing services. Learn more about the controller's capabilities in the [AWS Load Balancer Controller documentation](https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html).

4. **Deploy Sample Applications for Testing**:

   Before configuring ingress resources, we need target applications to demonstrate various traffic routing scenarios. These sample applications represent different versions of a service, enabling us to showcase advanced routing capabilities like weighted traffic distribution, canary deployments, and A/B testing patterns that are essential for modern application deployment strategies.

   ```bash
   # Create first sample application with custom content
   kubectl apply -f - <<EOF
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     namespace: $NAMESPACE
     name: sample-app-v1
   spec:
     replicas: 3
     selector:
       matchLabels:
         app: sample-app
         version: v1
     template:
       metadata:
         labels:
           app: sample-app
           version: v1
       spec:
         containers:
         - name: app
           image: nginx:1.25
           ports:
           - containerPort: 80
           volumeMounts:
           - name: content
             mountPath: /usr/share/nginx/html
         volumes:
         - name: content
           configMap:
             name: app-content-v1
   ---
   apiVersion: v1
   kind: ConfigMap
   metadata:
     namespace: $NAMESPACE
     name: app-content-v1
   data:
     index.html: |
       <html><body>
       <h1>Application Version 1</h1>
       <p>This is version 1 of the sample application</p>
       </body></html>
   ---
   apiVersion: v1
   kind: Service
   metadata:
     namespace: $NAMESPACE
     name: sample-app-v1
   spec:
     selector:
       app: sample-app
       version: v1
     ports:
     - port: 80
       targetPort: 80
     type: ClusterIP
   EOF
   
   # Create second sample application with different content
   kubectl apply -f - <<EOF
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     namespace: $NAMESPACE
     name: sample-app-v2
   spec:
     replicas: 2
     selector:
       matchLabels:
         app: sample-app
         version: v2
     template:
       metadata:
         labels:
           app: sample-app
           version: v2
       spec:
         containers:
         - name: app
           image: nginx:1.25
           ports:
           - containerPort: 80
           volumeMounts:
           - name: content
             mountPath: /usr/share/nginx/html
         volumes:
         - name: content
           configMap:
             name: app-content-v2
   ---
   apiVersion: v1
   kind: ConfigMap
   metadata:
     namespace: $NAMESPACE
     name: app-content-v2
   data:
     index.html: |
       <html><body>
       <h1>Application Version 2</h1>
       <p>This is version 2 of the sample application</p>
       </body></html>
   ---
   apiVersion: v1
   kind: Service
   metadata:
     namespace: $NAMESPACE
     name: sample-app-v2
   spec:
     selector:
       app: sample-app
       version: v2
     ports:
     - port: 80
       targetPort: 80
     type: ClusterIP
   EOF
   
   echo "✅ Sample applications deployed with unique content"
   ```

   The applications are now deployed with ClusterIP services and distinct content, making them accessible within the cluster but not externally. This setup provides the foundation for demonstrating how the AWS Load Balancer Controller bridges internal Kubernetes services with external AWS load balancers, enabling secure and scalable application exposure with visible differences between versions.

5. **Create Basic Application Load Balancer Ingress**:

   Application Load Balancers (ALB) operate at Layer 7 of the OSI model, providing advanced HTTP/HTTPS routing capabilities including host-based routing, path-based routing, and integration with AWS services. Creating an ingress resource automatically triggers the AWS Load Balancer Controller to provision an ALB with the specified configuration, eliminating manual infrastructure management while ensuring optimal integration with your Kubernetes workloads.

   ```bash
   # Create basic ALB ingress
   kubectl apply -f - <<EOF
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     namespace: $NAMESPACE
     name: sample-app-basic-alb
     annotations:
       alb.ingress.kubernetes.io/scheme: internet-facing
       alb.ingress.kubernetes.io/target-type: ip
       alb.ingress.kubernetes.io/healthcheck-path: /
       alb.ingress.kubernetes.io/healthcheck-interval-seconds: '10'
       alb.ingress.kubernetes.io/healthcheck-timeout-seconds: '5'
       alb.ingress.kubernetes.io/healthy-threshold-count: '2'
       alb.ingress.kubernetes.io/unhealthy-threshold-count: '3'
       alb.ingress.kubernetes.io/tags: Environment=demo,Team=platform
   spec:
     ingressClassName: alb
     rules:
     - host: basic.$DOMAIN_NAME
       http:
         paths:
         - path: /
           pathType: Prefix
           backend:
             service:
               name: sample-app-v1
               port:
                 number: 80
   EOF
   
   echo "✅ Basic ALB ingress created"
   ```

   The ALB is now being provisioned with optimized health checks and proper target group configuration. The `target-type: ip` annotation ensures direct routing to pod IPs rather than node ports, improving performance and reducing latency. This configuration follows AWS Well-Architected principles for high availability and performance. Learn more about ALB configuration in the [Application Load Balancer documentation](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/introduction.html).

6. **Create Advanced ALB Ingress with SSL and Path-Based Routing**:

   SSL/TLS termination at the load balancer level provides superior security and performance compared to pod-level encryption. AWS Certificate Manager (ACM) automatically handles certificate provisioning, renewal, and validation, eliminating the operational overhead of manual certificate management. This configuration demonstrates path-based routing, where different URL paths route to different backend services, enabling microservices architectures and API versioning strategies.

   ```bash
   # For demo purposes, create a self-signed certificate placeholder
   # In production, use ACM to create or import certificates
   echo "Note: Using placeholder certificate for demo. In production, use ACM certificates."
   
   # Create advanced ALB ingress with path-based routing
   kubectl apply -f - <<EOF
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     namespace: $NAMESPACE
     name: sample-app-advanced-alb
     annotations:
       alb.ingress.kubernetes.io/scheme: internet-facing
       alb.ingress.kubernetes.io/target-type: ip
       alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
       alb.ingress.kubernetes.io/load-balancer-attributes: idle_timeout.timeout_seconds=60
       alb.ingress.kubernetes.io/target-group-attributes: deregistration_delay.timeout_seconds=30,stickiness.enabled=false
       alb.ingress.kubernetes.io/healthcheck-path: /
       alb.ingress.kubernetes.io/healthcheck-protocol: HTTP
       alb.ingress.kubernetes.io/group.name: advanced-ingress
       alb.ingress.kubernetes.io/group.order: '1'
   spec:
     ingressClassName: alb
     rules:
     - host: advanced.$DOMAIN_NAME
       http:
         paths:
         - path: /v1
           pathType: Prefix
           backend:
             service:
               name: sample-app-v1
               port:
                 number: 80
         - path: /v2
           pathType: Prefix
           backend:
             service:
               name: sample-app-v2
               port:
                 number: 80
         - path: /
           pathType: Prefix
           backend:
             service:
               name: sample-app-v1
               port:
                 number: 80
   EOF
   
   echo "✅ Advanced ALB ingress with path-based routing created"
   ```

   The advanced ingress configuration now provides path-based routing to different service versions, enabling secure API versioning and gradual migration strategies. The configuration includes optimized timeouts and health checks for production-ready performance. In production environments, add SSL certificates from ACM using the `certificate-arn` annotation. Learn more about SSL/TLS configuration in the [AWS Certificate Manager documentation](https://docs.aws.amazon.com/acm/latest/userguide/acm-overview.html).

7. **Create Weighted Traffic Routing Ingress**:

   Weighted traffic routing enables sophisticated deployment strategies like canary releases, blue-green deployments, and A/B testing. By distributing traffic based on configurable weights, you can gradually roll out new application versions while monitoring performance and user experience. This approach minimizes risk by allowing incremental traffic shifts and quick rollbacks if issues are detected.

   ```bash
   # Create weighted routing ingress
   kubectl apply -f - <<EOF
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     namespace: $NAMESPACE
     name: sample-app-weighted-routing
     annotations:
       alb.ingress.kubernetes.io/scheme: internet-facing
       alb.ingress.kubernetes.io/target-type: ip
       alb.ingress.kubernetes.io/group.name: weighted-routing
       alb.ingress.kubernetes.io/actions.weighted-routing: |
         {
           "type": "forward",
           "forwardConfig": {
             "targetGroups": [
               {
                 "serviceName": "sample-app-v1",
                 "servicePort": "80",
                 "weight": 70
               },
               {
                 "serviceName": "sample-app-v2",
                 "servicePort": "80",
                 "weight": 30
               }
             ]
           }
         }
   spec:
     ingressClassName: alb
     rules:
     - host: weighted.$DOMAIN_NAME
       http:
         paths:
         - path: /
           pathType: Prefix
           backend:
             service:
               name: weighted-routing
               port:
                 name: use-annotation
   EOF
   
   echo "✅ Weighted routing ingress created (70% v1, 30% v2)"
   ```

   The weighted routing configuration now directs 70% of traffic to v1 and 30% to v2, enabling controlled exposure of new features. This pattern is essential for modern deployment strategies and risk mitigation, allowing teams to test new versions with real user traffic while maintaining the ability to quickly adjust weights or rollback. Learn more about weighted routing strategies in the [ELB documentation](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-listeners.html).

8. **Create Network Load Balancer Service**:

   Network Load Balancers (NLB) operate at Layer 4 (TCP/UDP) and provide ultra-low latency, high throughput, and the ability to handle millions of requests per second. Unlike ALBs, NLBs preserve the client IP address and are ideal for TCP-based applications, gaming applications, or when you need static IP addresses. NLBs are also required for applications that need to support non-HTTP protocols or when you need to maintain session affinity at the network level.

   ```bash
   # Create NLB service for TCP traffic
   kubectl apply -f - <<EOF
   apiVersion: v1
   kind: Service
   metadata:
     namespace: $NAMESPACE
     name: sample-app-nlb
     annotations:
       service.beta.kubernetes.io/aws-load-balancer-type: nlb
       service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
       service.beta.kubernetes.io/aws-load-balancer-backend-protocol: tcp
       service.beta.kubernetes.io/aws-load-balancer-target-type: ip
       service.beta.kubernetes.io/aws-load-balancer-attributes: load_balancing.cross_zone.enabled=true
       service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol: HTTP
       service.beta.kubernetes.io/aws-load-balancer-healthcheck-path: /
       service.beta.kubernetes.io/aws-load-balancer-healthcheck-interval: '10'
       service.beta.kubernetes.io/aws-load-balancer-healthcheck-timeout: '5'
       service.beta.kubernetes.io/aws-load-balancer-healthcheck-healthy-threshold: '2'
       service.beta.kubernetes.io/aws-load-balancer-healthcheck-unhealthy-threshold: '3'
   spec:
     selector:
       app: sample-app
       version: v1
     ports:
     - port: 80
       targetPort: 80
       protocol: TCP
     type: LoadBalancer
   EOF
   
   echo "✅ NLB service created with cross-zone load balancing"
   ```

   The NLB provides high-performance TCP load balancing with cross-zone load balancing enabled for optimal traffic distribution across all availability zones. This configuration is essential for applications requiring ultra-low latency or when you need to preserve client IP addresses for security or compliance requirements. The NLB automatically provisions static IP addresses and supports millions of concurrent connections.

9. **Create IngressClass for Custom Configuration**:

   IngressClasses provide a way to define reusable ingress configurations and enable multi-tenant environments where different teams can have different ingress controllers or configurations. IngressClassParams allow you to set default values for all ingresses using that class, reducing configuration repetition and ensuring consistency across your applications. This approach is particularly valuable in enterprise environments where governance and standardization are critical.

   ```bash
   # Create custom IngressClass with parameters
   kubectl apply -f - <<EOF
   apiVersion: networking.k8s.io/v1
   kind: IngressClass
   metadata:
     name: custom-alb
     annotations:
       ingressclass.kubernetes.io/is-default-class: "false"
   spec:
     controller: ingress.k8s.aws/alb
     parameters:
       apiVersion: elbv2.k8s.aws/v1beta1
       kind: IngressClassParams
       name: custom-alb-params
   ---
   apiVersion: elbv2.k8s.aws/v1beta1
   kind: IngressClassParams
   metadata:
     name: custom-alb-params
   spec:
     scheme: internet-facing
     targetType: ip
     tags:
       Environment: demo
       Team: platform
       ManagedBy: aws-load-balancer-controller
     loadBalancerAttributes:
       - key: idle_timeout.timeout_seconds
         value: "30"
       - key: routing.http.drop_invalid_header_fields.enabled
         value: "true"
   EOF
   
   echo "✅ Custom IngressClass with security parameters created"
   ```

   The custom IngressClass now provides standardized configurations for all ingresses that reference it, ensuring consistent tagging, target types, scheme settings, and security parameters. This approach simplifies ingress management and enables centralized policy enforcement across your cluster, including security hardening through invalid header field dropping. Learn more about IngressClass configuration in the [EKS documentation](https://docs.aws.amazon.com/eks/latest/userguide/alb-ingress.html).

10. **Create Ingress with Custom Actions and Conditions**:

    Advanced routing actions and conditions enable sophisticated traffic management patterns including user-agent based redirects, geographic routing, and custom rate limiting. These capabilities allow you to implement complex business logic at the load balancer level, reducing the need for application-level filtering and improving performance. This approach is particularly valuable for mobile applications, API management, and security enforcement.

    ```bash
    # Create ingress with custom routing conditions
    kubectl apply -f - <<EOF
    apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      namespace: $NAMESPACE
      name: sample-app-conditional-routing
      annotations:
        alb.ingress.kubernetes.io/scheme: internet-facing
        alb.ingress.kubernetes.io/target-type: ip
        alb.ingress.kubernetes.io/actions.mobile-redirect: |
          {
            "type": "redirect",
            "redirectConfig": {
              "host": "mobile.example.com",
              "path": "/#{path}",
              "port": "443",
              "protocol": "HTTPS",
              "statusCode": "HTTP_302"
            }
          }
        alb.ingress.kubernetes.io/conditions.mobile-redirect: |
          [
            {
              "field": "http-header",
              "httpHeaderConfig": {
                "httpHeaderName": "User-Agent",
                "values": ["*Mobile*", "*Android*", "*iPhone*"]
              }
            }
          ]
        alb.ingress.kubernetes.io/actions.api-fixed-response: |
          {
            "type": "fixed-response",
            "fixedResponseConfig": {
              "contentType": "application/json",
              "statusCode": "200",
              "messageBody": "{\"message\": \"API endpoint - custom response\"}"
            }
          }
        alb.ingress.kubernetes.io/conditions.api-fixed-response: |
          [
            {
              "field": "path-pattern",
              "pathPatternConfig": {
                "values": ["/api/status"]
              }
            }
          ]
    spec:
      ingressClassName: alb
      rules:
      - host: conditional.$DOMAIN_NAME
        http:
          paths:
          - path: /mobile
            pathType: Prefix
            backend:
              service:
                name: mobile-redirect
                port:
                  name: use-annotation
          - path: /api/status
            pathType: Prefix
            backend:
              service:
                name: api-fixed-response
                port:
                  name: use-annotation
          - path: /
            pathType: Prefix
            backend:
              service:
                name: sample-app-v1
                port:
                  number: 80
    EOF
    
    echo "✅ Conditional routing ingress with custom actions created"
    ```

    The conditional routing configuration demonstrates powerful traffic management capabilities, including mobile user redirection and custom API responses. This approach enables sophisticated user experience optimizations and API management directly at the load balancer level, reducing application complexity and improving performance while providing fine-grained control over request handling.

11. **Configure Ingress Group for Multiple Ingresses**:

    Ingress groups enable multiple ingress resources to share a single Application Load Balancer, significantly reducing costs and simplifying management. This approach is particularly valuable in multi-tenant environments or when you have multiple microservices that need external access. By sharing ALBs, you can reduce the number of load balancers while maintaining independent ingress configurations for different applications or teams.

    ```bash
    # Create multiple ingresses sharing the same ALB
    kubectl apply -f - <<EOF
    apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      namespace: $NAMESPACE
      name: shared-alb-app1
      annotations:
        alb.ingress.kubernetes.io/scheme: internet-facing
        alb.ingress.kubernetes.io/target-type: ip
        alb.ingress.kubernetes.io/group.name: shared-alb
        alb.ingress.kubernetes.io/group.order: '1'
    spec:
      ingressClassName: alb
      rules:
      - host: app1.$DOMAIN_NAME
        http:
          paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: sample-app-v1
                port:
                  number: 80
    ---
    apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      namespace: $NAMESPACE
      name: shared-alb-app2
      annotations:
        alb.ingress.kubernetes.io/scheme: internet-facing
        alb.ingress.kubernetes.io/target-type: ip
        alb.ingress.kubernetes.io/group.name: shared-alb
        alb.ingress.kubernetes.io/group.order: '2'
    spec:
      ingressClassName: alb
      rules:
      - host: app2.$DOMAIN_NAME
        http:
          paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: sample-app-v2
                port:
                  number: 80
    EOF
    
    echo "✅ Shared ALB ingress group created for cost optimization"
    ```

    The ingress group configuration reduces infrastructure costs by consolidating multiple applications onto a single ALB while maintaining independent routing rules. The `group.order` annotation ensures predictable rule evaluation order, preventing conflicts between different ingress resources. This pattern can reduce ALB costs by up to 80% in environments with many microservices.

12. **Enable Monitoring and Logging**:

    Access logs provide detailed information about requests made to your load balancer, including client IP addresses, request paths, response codes, and processing times. This data is essential for security analysis, performance monitoring, and troubleshooting. Storing access logs in S3 enables integration with analytics tools like Amazon Athena, CloudWatch Logs Insights, and third-party SIEM systems for comprehensive observability.

    ```bash
    # Create S3 bucket for access logs with proper permissions
    S3_BUCKET="alb-access-logs-${RANDOM_SUFFIX}"
    aws s3 mb s3://$S3_BUCKET --region $AWS_REGION
    
    # Get the ELB service account ID for your region
    ELB_ACCOUNT_ID=$(aws --region $AWS_REGION \
        elbv2 describe-account-attributes \
        --attribute-names access-logs-s3-bucket-and-prefix \
        --query 'AccountAttributes[0].AttributeValue' \
        --output text 2>/dev/null || echo "127311923021")
    
    # Create bucket policy for ELB access logs
    aws s3api put-bucket-policy \
        --bucket $S3_BUCKET \
        --policy "{
          \"Version\": \"2012-10-17\",
          \"Statement\": [
            {
              \"Effect\": \"Allow\",
              \"Principal\": {
                \"AWS\": \"arn:aws:iam::${ELB_ACCOUNT_ID}:root\"
              },
              \"Action\": \"s3:PutObject\",
              \"Resource\": \"arn:aws:s3:::${S3_BUCKET}/alb-logs/AWSLogs/${AWS_ACCOUNT_ID}/*\"
            },
            {
              \"Effect\": \"Allow\",
              \"Principal\": {
                \"Service\": \"delivery.logs.amazonaws.com\"
              },
              \"Action\": \"s3:PutObject\",
              \"Resource\": \"arn:aws:s3:::${S3_BUCKET}/alb-logs/AWSLogs/${AWS_ACCOUNT_ID}/*\"
            },
            {
              \"Effect\": \"Allow\",
              \"Principal\": {
                \"AWS\": \"arn:aws:iam::${ELB_ACCOUNT_ID}:root\"
              },
              \"Action\": \"s3:GetBucketAcl\",
              \"Resource\": \"arn:aws:s3:::${S3_BUCKET}\"
            }
          ]
        }"
    
    # Create ingress with access logging enabled
    kubectl apply -f - <<EOF
    apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      namespace: $NAMESPACE
      name: sample-app-logging
      annotations:
        alb.ingress.kubernetes.io/scheme: internet-facing
        alb.ingress.kubernetes.io/target-type: ip
        alb.ingress.kubernetes.io/load-balancer-attributes: |
          access_logs.s3.enabled=true,
          access_logs.s3.bucket=$S3_BUCKET,
          access_logs.s3.prefix=alb-logs
    spec:
      ingressClassName: alb
      rules:
      - host: logging.$DOMAIN_NAME
        http:
          paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: sample-app-v1
                port:
                  number: 80
    EOF
    
    echo "✅ Ingress with comprehensive logging enabled"
    ```

    The access logging configuration enables comprehensive request tracking and analysis with proper S3 bucket permissions. This observability foundation supports security monitoring, performance optimization, and compliance requirements. The S3 storage approach provides cost-effective, scalable log retention with flexible analytics capabilities through services like Amazon Athena.

## Validation & Testing

1. **Verify AWS Load Balancer Controller Installation**:

   ```bash
   # Check controller deployment status
   kubectl get deployment -n kube-system aws-load-balancer-controller
   
   # Check controller logs for any errors
   kubectl logs -n kube-system \
       deployment/aws-load-balancer-controller --tail=50
   
   # Verify controller version
   kubectl get deployment -n kube-system aws-load-balancer-controller \
       -o jsonpath='{.spec.template.spec.containers[0].image}'
   ```

   Expected output: Controller should be running with 2/2 ready replicas and image version v2.13.3

2. **Verify ALB and NLB Creation**:

   ```bash
   # List all load balancers created by the controller
   aws elbv2 describe-load-balancers \
       --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-`)].{Name:LoadBalancerName,DNS:DNSName,Scheme:Scheme,Type:Type}' \
       --output table
   
   # Get ingress status and DNS names
   kubectl get ingress -n $NAMESPACE -o wide
   
   # Get service details for NLB
   kubectl get service -n $NAMESPACE -o wide
   ```

3. **Test HTTP Connectivity and Routing**:

   ```bash
   # Get ALB DNS names
   BASIC_ALB_DNS=$(kubectl get ingress sample-app-basic-alb -n $NAMESPACE \
       -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
   
   # Test basic connectivity
   echo "Testing basic ALB connectivity:"
   curl -H "Host: basic.$DOMAIN_NAME" http://$BASIC_ALB_DNS/ || echo "ALB still provisioning..."
   
   # Test path-based routing
   ADVANCED_ALB_DNS=$(kubectl get ingress sample-app-advanced-alb -n $NAMESPACE \
       -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
   
   echo "Testing path-based routing:"
   curl -H "Host: advanced.$DOMAIN_NAME" http://$ADVANCED_ALB_DNS/v1
   curl -H "Host: advanced.$DOMAIN_NAME" http://$ADVANCED_ALB_DNS/v2
   
   # Test weighted routing distribution
   WEIGHTED_DNS=$(kubectl get ingress sample-app-weighted-routing -n $NAMESPACE \
       -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
   
   echo "Testing weighted routing (should show ~70% v1, ~30% v2):"
   for i in {1..10}; do
       curl -s -H "Host: weighted.$DOMAIN_NAME" http://$WEIGHTED_DNS/ | grep -o "Version [12]"
   done
   ```

4. **Test Target Group Health**:

   ```bash
   # Get target group ARNs
   aws elbv2 describe-target-groups \
       --query 'TargetGroups[?contains(TargetGroupName, `k8s-`)].{Name:TargetGroupName,ARN:TargetGroupArn}' \
       --output table
   
   # Check target health for a specific target group
   TG_ARN=$(aws elbv2 describe-target-groups \
       --query 'TargetGroups[?contains(TargetGroupName, `k8s-`)].TargetGroupArn' \
       --output text | head -1)
   
   if [ ! -z "$TG_ARN" ]; then
       aws elbv2 describe-target-health \
           --target-group-arn $TG_ARN \
           --query 'TargetHealthDescriptions[*].{Target:Target.Id,Port:Target.Port,Health:TargetHealth.State}' \
           --output table
   fi
   ```

5. **Verify Ingress Controller Performance**:

   ```bash
   # Check controller resource usage
   kubectl top pods -n kube-system \
       -l app.kubernetes.io/name=aws-load-balancer-controller 2>/dev/null || \
       echo "Metrics server not available"
   
   # Check ingress resource status
   kubectl describe ingress -n $NAMESPACE | grep -A5 "Events:"
   
   # Verify custom IngressClass
   kubectl get ingressclass custom-alb -o yaml
   ```

## Cleanup

1. **Delete Ingress Resources**:

   ```bash
   # Delete all ingresses in the namespace
   kubectl delete ingress --all -n $NAMESPACE
   
   # Wait for ALBs to be deleted (this may take a few minutes)
   echo "Waiting for ALBs to be deleted..."
   sleep 120
   
   echo "✅ Deleted all ingresses"
   ```

2. **Delete Service Resources**:

   ```bash
   # Delete NLB service
   kubectl delete service sample-app-nlb -n $NAMESPACE
   
   # Delete other services
   kubectl delete service sample-app-v1 sample-app-v2 -n $NAMESPACE
   
   echo "✅ Deleted services and NLB"
   ```

3. **Delete Applications and Namespace**:

   ```bash
   # Delete all resources in the namespace
   kubectl delete namespace $NAMESPACE
   
   echo "✅ Deleted applications and namespace"
   ```

4. **Delete Custom IngressClass Resources**:

   ```bash
   # Delete custom IngressClass and parameters
   kubectl delete ingressclass custom-alb
   kubectl delete ingressclassparams custom-alb-params
   
   echo "✅ Deleted custom IngressClass resources"
   ```

5. **Uninstall AWS Load Balancer Controller**:

   ```bash
   # Uninstall using Helm
   helm uninstall aws-load-balancer-controller -n kube-system
   
   # Delete service account and IAM role
   eksctl delete iamserviceaccount \
       --cluster=$CLUSTER_NAME \
       --namespace=kube-system \
       --name=aws-load-balancer-controller
   
   echo "✅ Uninstalled AWS Load Balancer Controller"
   ```

6. **Delete IAM Policy and S3 Bucket**:

   ```bash
   # Delete IAM policy
   aws iam delete-policy \
       --policy-arn $POLICY_ARN
   
   # Delete S3 bucket and contents
   aws s3 rb s3://$S3_BUCKET --force 2>/dev/null || echo "S3 bucket already deleted"
   
   # Clean up local files
   rm -f iam-policy.json
   
   echo "✅ Deleted IAM policy and S3 bucket"
   ```

7. **Delete EKS Cluster (Optional)**:

   ```bash
   # Delete cluster if it was created for this demo
   read -p "Delete EKS cluster $CLUSTER_NAME? (y/N): " -n 1 -r
   echo
   if [[ $REPLY =~ ^[Yy]$ ]]; then
       eksctl delete cluster --name $CLUSTER_NAME --region $AWS_REGION
       echo "✅ Deleted EKS cluster"
   else
       echo "EKS cluster preserved"
   fi
   ```

## Discussion

The AWS Load Balancer Controller represents a significant advancement in Kubernetes ingress management on AWS, providing native integration with AWS services that traditional ingress controllers cannot match. This controller automatically provisions and configures Application Load Balancers (ALB) for HTTP/HTTPS traffic and Network Load Balancers (NLB) for TCP/UDP traffic, eliminating the manual overhead of load balancer management while ensuring optimal integration with the AWS ecosystem.

The architecture supports advanced traffic routing patterns through ingress annotations, enabling sophisticated scenarios like weighted routing for canary deployments, conditional routing based on headers or source IP, and custom actions for redirects or fixed responses. The controller's integration with AWS Certificate Manager (ACM) automates SSL/TLS certificate management, while integration with AWS WAF provides application-layer security without additional infrastructure complexity. Version 2.13.3 brings enhanced security features, improved performance through reduced API calls, and beta support for Layer 4 Gateway API routing.

Performance and scalability benefits include automatic target group management with health checks, cross-zone load balancing, and the ability to share load balancers across multiple ingresses through ingress groups. The controller also provides extensive monitoring capabilities through CloudWatch metrics and access logs, enabling comprehensive observability into application traffic patterns and performance characteristics. The implementation follows AWS Well-Architected Framework principles for operational excellence, security, reliability, performance efficiency, and cost optimization.

Security features include integration with AWS Shield for DDoS protection, support for mutual TLS authentication, and the ability to configure security groups and NACLs for network-level security. The controller's IAM integration through IRSA (IAM Roles for Service Accounts) ensures least-privilege access, maintaining security best practices throughout the deployment. Learn more about the AWS Load Balancer Controller in the [official documentation](https://kubernetes-sigs.github.io/aws-load-balancer-controller/) and the [AWS EKS user guide](https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html).

> **Tip**: Use ingress groups to share ALBs across multiple ingresses, reducing costs by up to 80% and simplifying management while maintaining routing flexibility and independent application configurations.

## Challenge

Extend this solution by implementing these enhancements:

1. **Implement Blue/Green Deployments**: Create a sophisticated traffic shifting mechanism using weighted routing that gradually moves traffic from blue to green environments with automated rollback capabilities based on CloudWatch alarms and health check failures.

2. **Add Multi-Region Ingress**: Deploy the same ingress configuration across multiple AWS regions with Route 53 health checks and failover routing to create a globally distributed application with automatic failover and latency-based routing.

3. **Integrate with Service Mesh**: Combine the AWS Load Balancer Controller with AWS App Mesh to create a complete traffic management solution that handles both north-south (ingress) and east-west (service-to-service) traffic with advanced observability and security policies.

4. **Implement Advanced Authentication**: Configure OAuth 2.0/OIDC authentication at the ALB level using Amazon Cognito or external identity providers, with fine-grained authorization rules based on user attributes and JWT claims for API access control.

5. **Create Cost Optimization Automation**: Develop Lambda functions that automatically analyze ALB usage patterns, right-size capacity units, consolidate underutilized load balancers, and implement scheduled scaling for predictable traffic patterns to optimize costs.

## Infrastructure Code

### Available Infrastructure as Code:

- [Infrastructure Code Overview](code/README.md) - Detailed description of all infrastructure components
- [AWS CDK (Python)](code/cdk-python/) - AWS CDK Python implementation
- [AWS CDK (TypeScript)](code/cdk-typescript/) - AWS CDK TypeScript implementation
- [CloudFormation](code/cloudformation.yaml) - AWS CloudFormation template
- [Bash CLI Scripts](code/scripts/) - Example bash scripts using AWS CLI commands to deploy infrastructure
- [Terraform](code/terraform/) - Terraform configuration files