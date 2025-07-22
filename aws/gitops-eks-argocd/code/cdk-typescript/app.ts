#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as eks from 'aws-cdk-lib/aws-eks';
import * as codecommit from 'aws-cdk-lib/aws-codecommit';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * Properties for the GitOps Workflows Stack
 */
interface GitOpsWorkflowsStackProps extends cdk.StackProps {
  /**
   * Name of the EKS cluster
   * @default 'gitops-cluster'
   */
  readonly clusterName?: string;
  
  /**
   * Name of the CodeCommit repository
   * @default 'gitops-config-repo'
   */
  readonly repositoryName?: string;
  
  /**
   * Instance type for EKS worker nodes
   * @default 't3.medium'
   */
  readonly nodeInstanceType?: ec2.InstanceType;
  
  /**
   * Desired number of worker nodes
   * @default 2
   */
  readonly desiredCapacity?: number;
  
  /**
   * Minimum number of worker nodes
   * @default 1
   */
  readonly minCapacity?: number;
  
  /**
   * Maximum number of worker nodes
   * @default 4
   */
  readonly maxCapacity?: number;
}

/**
 * CDK Stack for GitOps Workflows with EKS, ArgoCD, and CodeCommit
 * 
 * This stack creates:
 * - VPC with public and private subnets
 * - EKS cluster with managed node group
 * - CodeCommit repository for GitOps configuration
 * - IAM roles and policies for EKS and GitOps workflows
 * - CloudWatch log groups for monitoring
 */
export class GitOpsWorkflowsStack extends cdk.Stack {
  public readonly cluster: eks.Cluster;
  public readonly repository: codecommit.Repository;
  public readonly vpc: ec2.Vpc;

  constructor(scope: Construct, id: string, props: GitOpsWorkflowsStackProps = {}) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = this.node.tryGetContext('uniqueSuffix') || 
      Math.random().toString(36).substring(2, 8);

    // Set default values for stack properties
    const clusterName = props.clusterName || `gitops-cluster-${uniqueSuffix}`;
    const repositoryName = props.repositoryName || `gitops-config-${uniqueSuffix}`;
    const nodeInstanceType = props.nodeInstanceType || ec2.InstanceType.of(
      ec2.InstanceClass.T3, 
      ec2.InstanceSize.MEDIUM
    );
    const desiredCapacity = props.desiredCapacity || 2;
    const minCapacity = props.minCapacity || 1;
    const maxCapacity = props.maxCapacity || 4;

    // Create VPC for EKS cluster with best practices
    this.vpc = new ec2.Vpc(this, 'GitOpsVpc', {
      maxAzs: 3,
      natGateways: 1, // Cost optimization - single NAT gateway
      enableDnsHostnames: true,
      enableDnsSupport: true,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: 24,
          name: 'private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
      ],
    });

    // Tag VPC subnets for EKS cluster discovery
    cdk.Tags.of(this.vpc).add('kubernetes.io/cluster/' + clusterName, 'shared');

    // Create CloudWatch log group for EKS cluster logs
    const clusterLogGroup = new logs.LogGroup(this, 'EksClusterLogGroup', {
      logGroupName: `/aws/eks/${clusterName}/cluster`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create EKS cluster with GitOps-ready configuration
    this.cluster = new eks.Cluster(this, 'GitOpsCluster', {
      clusterName: clusterName,
      version: eks.KubernetesVersion.V1_28,
      vpc: this.vpc,
      vpcSubnets: [{ subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS }],
      defaultCapacity: 0, // We'll use managed node groups instead
      endpointAccess: eks.EndpointAccess.PUBLIC_AND_PRIVATE,
      clusterLogging: [
        eks.ClusterLoggingTypes.API,
        eks.ClusterLoggingTypes.AUTHENTICATOR,
        eks.ClusterLoggingTypes.SCHEDULER,
        eks.ClusterLoggingTypes.CONTROLLER_MANAGER,
      ],
      outputClusterName: true,
      outputConfigCommand: true,
    });

    // Create managed node group for worker nodes
    const nodeGroup = this.cluster.addNodegroupCapacity('GitOpsNodeGroup', {
      instanceTypes: [nodeInstanceType],
      minSize: minCapacity,
      maxSize: maxCapacity,
      desiredSize: desiredCapacity,
      diskSize: 20,
      amiType: eks.NodegroupAmiType.AL2_X86_64,
      capacityType: eks.CapacityType.ON_DEMAND,
      nodegroupName: `${clusterName}-node-group`,
      subnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
    });

    // Create IAM role for ArgoCD with necessary permissions
    const argoCdRole = new iam.Role(this, 'ArgoCdRole', {
      assumedBy: new iam.ServicePrincipal('eks.amazonaws.com'),
      description: 'IAM role for ArgoCD GitOps operations',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEKSClusterPolicy'),
      ],
    });

    // Add CodeCommit permissions to the cluster role
    this.cluster.role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'codecommit:GetRepository',
        'codecommit:ListRepositories',
        'codecommit:GitPull',
        'codecommit:GitPush',
        'codecommit:GetBranch',
        'codecommit:ListBranches',
        'codecommit:GetCommit',
      ],
      resources: ['*'],
    }));

    // Create CodeCommit repository for GitOps configuration
    this.repository = new codecommit.Repository(this, 'GitOpsRepository', {
      repositoryName: repositoryName,
      description: 'GitOps configuration repository for EKS deployments with ArgoCD',
    });

    // Create service account for AWS Load Balancer Controller
    const albServiceAccount = this.cluster.addServiceAccount('AwsLoadBalancerController', {
      name: 'aws-load-balancer-controller',
      namespace: 'kube-system',
    });

    // Add IAM policy for AWS Load Balancer Controller
    const albPolicyDocument = {
      Version: '2012-10-17',
      Statement: [
        {
          Effect: 'Allow',
          Action: [
            'iam:CreateServiceLinkedRole',
            'ec2:DescribeAccountAttributes',
            'ec2:DescribeAddresses',
            'ec2:DescribeAvailabilityZones',
            'ec2:DescribeInternetGateways',
            'ec2:DescribeVpcs',
            'ec2:DescribeSubnets',
            'ec2:DescribeSecurityGroups',
            'ec2:DescribeInstances',
            'ec2:DescribeNetworkInterfaces',
            'ec2:DescribeTags',
            'ec2:GetCoipPoolUsage',
            'ec2:DescribeCoipPools',
            'elasticloadbalancing:DescribeLoadBalancers',
            'elasticloadbalancing:DescribeLoadBalancerAttributes',
            'elasticloadbalancing:DescribeListeners',
            'elasticloadbalancing:DescribeListenerCertificates',
            'elasticloadbalancing:DescribeSSLPolicies',
            'elasticloadbalancing:DescribeRules',
            'elasticloadbalancing:DescribeTargetGroups',
            'elasticloadbalancing:DescribeTargetGroupAttributes',
            'elasticloadbalancing:DescribeTargetHealth',
            'elasticloadbalancing:DescribeTags',
          ],
          Resource: '*',
        },
        {
          Effect: 'Allow',
          Action: [
            'cognito-idp:DescribeUserPoolClient',
            'acm:ListCertificates',
            'acm:DescribeCertificate',
            'iam:ListServerCertificates',
            'iam:GetServerCertificate',
            'waf-regional:GetWebACL',
            'waf-regional:GetWebACLForResource',
            'waf-regional:AssociateWebACL',
            'waf-regional:DisassociateWebACL',
            'wafv2:GetWebACL',
            'wafv2:GetWebACLForResource',
            'wafv2:AssociateWebACL',
            'wafv2:DisassociateWebACL',
            'shield:DescribeProtection',
            'shield:DescribeSubscription',
            'shield:GetSubscriptionState',
          ],
          Resource: '*',
        },
        {
          Effect: 'Allow',
          Action: [
            'ec2:CreateSecurityGroup',
            'ec2:CreateTags',
          ],
          Resource: 'arn:aws:ec2:*:*:security-group/*',
          Condition: {
            StringEquals: {
              'ec2:CreateAction': 'CreateSecurityGroup',
            },
            Null: {
              'aws:RequestTag/elbv2.k8s.aws/cluster': 'false',
            },
          },
        },
        {
          Effect: 'Allow',
          Action: [
            'elasticloadbalancing:CreateLoadBalancer',
            'elasticloadbalancing:CreateTargetGroup',
          ],
          Resource: '*',
          Condition: {
            Null: {
              'aws:RequestTag/elbv2.k8s.aws/cluster': 'false',
            },
          },
        },
        {
          Effect: 'Allow',
          Action: [
            'elasticloadbalancing:CreateListener',
            'elasticloadbalancing:DeleteListener',
            'elasticloadbalancing:CreateRule',
            'elasticloadbalancing:DeleteRule',
          ],
          Resource: '*',
        },
        {
          Effect: 'Allow',
          Action: [
            'elasticloadbalancing:AddTags',
            'elasticloadbalancing:RemoveTags',
          ],
          Resource: [
            'arn:aws:elasticloadbalancing:*:*:targetgroup/*/*',
            'arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*',
            'arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*',
          ],
          Condition: {
            Null: {
              'aws:RequestTag/elbv2.k8s.aws/cluster': 'true',
              'aws:ResourceTag/elbv2.k8s.aws/cluster': 'false',
            },
          },
        },
        {
          Effect: 'Allow',
          Action: [
            'elasticloadbalancing:AddTags',
            'elasticloadbalancing:RemoveTags',
          ],
          Resource: [
            'arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*',
            'arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*',
            'arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*',
            'arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*',
          ],
        },
        {
          Effect: 'Allow',
          Action: [
            'elasticloadbalancing:ModifyLoadBalancerAttributes',
            'elasticloadbalancing:SetIpAddressType',
            'elasticloadbalancing:SetSecurityGroups',
            'elasticloadbalancing:SetSubnets',
            'elasticloadbalancing:DeleteLoadBalancer',
            'elasticloadbalancing:ModifyTargetGroup',
            'elasticloadbalancing:ModifyTargetGroupAttributes',
            'elasticloadbalancing:DeleteTargetGroup',
          ],
          Resource: '*',
          Condition: {
            Null: {
              'aws:ResourceTag/elbv2.k8s.aws/cluster': 'false',
            },
          },
        },
        {
          Effect: 'Allow',
          Action: [
            'elasticloadbalancing:RegisterTargets',
            'elasticloadbalancing:DeregisterTargets',
          ],
          Resource: 'arn:aws:elasticloadbalancing:*:*:targetgroup/*/*',
        },
        {
          Effect: 'Allow',
          Action: [
            'elasticloadbalancing:SetWebAcl',
            'elasticloadbalancing:ModifyListener',
            'elasticloadbalancing:AddListenerCertificates',
            'elasticloadbalancing:RemoveListenerCertificates',
            'elasticloadbalancing:ModifyRule',
          ],
          Resource: '*',
        },
      ],
    };

    albServiceAccount.role.attachInlinePolicy(new iam.Policy(this, 'AlbControllerPolicy', {
      document: iam.PolicyDocument.fromJson(albPolicyDocument),
    }));

    // Install AWS Load Balancer Controller using Helm
    const albController = this.cluster.addHelmChart('AwsLoadBalancerController', {
      chart: 'aws-load-balancer-controller',
      repository: 'https://aws.github.io/eks-charts',
      namespace: 'kube-system',
      values: {
        clusterName: clusterName,
        serviceAccount: {
          create: false,
          name: 'aws-load-balancer-controller',
        },
      },
    });

    // Install ArgoCD using Helm chart
    const argoCdChart = this.cluster.addHelmChart('ArgoCD', {
      chart: 'argo-cd',
      repository: 'https://argoproj.github.io/argo-helm',
      namespace: 'argocd',
      createNamespace: true,
      values: {
        server: {
          service: {
            type: 'ClusterIP',
          },
          ingress: {
            enabled: true,
            ingressClassName: 'alb',
            annotations: {
              'alb.ingress.kubernetes.io/scheme': 'internet-facing',
              'alb.ingress.kubernetes.io/target-type': 'ip',
              'alb.ingress.kubernetes.io/listen-ports': '[{"HTTP": 80}, {"HTTPS": 443}]',
              'alb.ingress.kubernetes.io/ssl-redirect': '443',
            },
            hosts: ['*'],
            paths: [
              {
                path: '/',
                pathType: 'Prefix',
              },
            ],
          },
        },
        configs: {
          params: {
            'server.insecure': true,
          },
        },
      },
    });

    // Ensure ArgoCD is installed after ALB controller
    argoCdChart.node.addDependency(albController);

    // Output important information
    new cdk.CfnOutput(this, 'ClusterName', {
      value: this.cluster.clusterName,
      description: 'Name of the EKS cluster',
    });

    new cdk.CfnOutput(this, 'ClusterEndpoint', {
      value: this.cluster.clusterEndpoint,
      description: 'Endpoint of the EKS cluster',
    });

    new cdk.CfnOutput(this, 'ClusterConfigCommand', {
      value: `aws eks update-kubeconfig --region ${this.region} --name ${this.cluster.clusterName}`,
      description: 'Command to configure kubectl for this cluster',
    });

    new cdk.CfnOutput(this, 'RepositoryName', {
      value: this.repository.repositoryName,
      description: 'Name of the CodeCommit repository',
    });

    new cdk.CfnOutput(this, 'RepositoryCloneUrl', {
      value: this.repository.repositoryCloneUrlHttp,
      description: 'HTTPS clone URL for the CodeCommit repository',
    });

    new cdk.CfnOutput(this, 'ArgoCdPasswordCommand', {
      value: `kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d`,
      description: 'Command to retrieve ArgoCD admin password',
    });

    new cdk.CfnOutput(this, 'ArgoCdIngressCommand', {
      value: `kubectl get ingress argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'`,
      description: 'Command to get ArgoCD ingress hostname',
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'GitOps-Workflows');
    cdk.Tags.of(this).add('Purpose', 'EKS-ArgoCD-CodeCommit-Integration');
    cdk.Tags.of(this).add('Environment', 'Development');
  }
}

/**
 * Main CDK application
 */
const app = new cdk.App();

// Create the GitOps Workflows stack
new GitOpsWorkflowsStack(app, 'GitOpsWorkflowsStack', {
  description: 'GitOps Workflows implementation with EKS, ArgoCD, and CodeCommit',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  
  // Stack-specific properties (can be customized)
  clusterName: app.node.tryGetContext('clusterName'),
  repositoryName: app.node.tryGetContext('repositoryName'),
  nodeInstanceType: app.node.tryGetContext('nodeInstanceType') 
    ? ec2.InstanceType.of(
        app.node.tryGetContext('nodeInstanceClass') || ec2.InstanceClass.T3,
        app.node.tryGetContext('nodeInstanceSize') || ec2.InstanceSize.MEDIUM
      )
    : undefined,
  desiredCapacity: app.node.tryGetContext('desiredCapacity'),
  minCapacity: app.node.tryGetContext('minCapacity'),
  maxCapacity: app.node.tryGetContext('maxCapacity'),
});

app.synth();