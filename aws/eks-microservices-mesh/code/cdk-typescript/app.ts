#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as eks from 'aws-cdk-lib/aws-eks';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as appmesh from 'aws-cdk-lib/aws-appmesh';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';

/**
 * Stack for deploying microservices on EKS with AWS App Mesh service mesh
 * 
 * This stack creates:
 * - VPC with public and private subnets across AZs
 * - EKS cluster with managed node groups
 * - App Mesh service mesh
 * - ECR repositories for microservices
 * - IAM roles and policies for service mesh integration
 * - CloudWatch logging and monitoring setup
 */
export class MicroservicesEksServiceMeshStack extends cdk.Stack {
  public readonly cluster: eks.Cluster;
  public readonly vpc: ec2.Vpc;
  public readonly mesh: appmesh.Mesh;
  public readonly ecrRepositories: { [key: string]: ecr.Repository };

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8);
    const clusterName = `microservices-mesh-cluster-${uniqueSuffix}`;
    const meshName = `microservices-mesh-${uniqueSuffix}`;

    // Create VPC with optimal configuration for EKS and App Mesh
    this.vpc = new ec2.Vpc(this, 'MicroservicesVpc', {
      ipAddresses: ec2.IpAddresses.cidr('10.0.0.0/16'),
      maxAzs: 3,
      natGateways: 2, // High availability with cost optimization
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: 24,
          name: 'Private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        }
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });

    // Tag VPC subnets for EKS cluster discovery
    cdk.Tags.of(this.vpc).add('kubernetes.io/cluster/' + clusterName, 'shared');
    
    // Tag public subnets for load balancer discovery
    this.vpc.publicSubnets.forEach((subnet, index) => {
      cdk.Tags.of(subnet).add('kubernetes.io/role/elb', '1');
      cdk.Tags.of(subnet).add('Name', `Public-Subnet-${index + 1}`);
    });

    // Tag private subnets for internal load balancer discovery
    this.vpc.privateSubnets.forEach((subnet, index) => {
      cdk.Tags.of(subnet).add('kubernetes.io/role/internal-elb', '1');
      cdk.Tags.of(subnet).add('Name', `Private-Subnet-${index + 1}`);
    });

    // Create CloudWatch log group for EKS cluster
    const clusterLogGroup = new logs.LogGroup(this, 'EksClusterLogGroup', {
      logGroupName: `/aws/eks/${clusterName}/cluster`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create EKS cluster with App Mesh support
    this.cluster = new eks.Cluster(this, 'MicroservicesEksCluster', {
      clusterName: clusterName,
      version: eks.KubernetesVersion.V1_28,
      vpc: this.vpc,
      vpcSubnets: [{ subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS }],
      defaultCapacity: 0, // We'll add managed node groups separately
      endpointAccess: eks.EndpointAccess.PUBLIC_AND_PRIVATE,
      clusterLogging: [
        eks.ClusterLoggingTypes.API,
        eks.ClusterLoggingTypes.AUDIT,
        eks.ClusterLoggingTypes.AUTHENTICATOR,
        eks.ClusterLoggingTypes.CONTROLLER_MANAGER,
        eks.ClusterLoggingTypes.SCHEDULER,
      ],
      outputClusterName: true,
      outputConfigCommand: true,
    });

    // Create managed node group with App Mesh support
    const nodeGroup = this.cluster.addNodegroupCapacity('MicroservicesNodeGroup', {
      nodegroupName: 'microservices-nodes',
      instanceTypes: [
        ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MEDIUM),
        ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.LARGE),
      ],
      minSize: 3,
      maxSize: 6,
      desiredSize: 3,
      capacityType: eks.CapacityType.ON_DEMAND,
      diskSize: 20,
      amiType: eks.NodegroupAmiType.AL2_X86_64,
      subnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      remoteAccess: {
        ec2SshKey: undefined, // Disable SSH access for security
      },
      labels: {
        'node-type': 'microservices',
        'mesh-enabled': 'true',
      },
      taints: [],
    });

    // Add App Mesh IAM policies to node group role
    nodeGroup.role.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName('AWSAppMeshEnvoyAccess')
    );
    nodeGroup.role.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy')
    );
    nodeGroup.role.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName('AWSXRayDaemonWriteAccess')
    );

    // Create App Mesh
    this.mesh = new appmesh.Mesh(this, 'MicroservicesMesh', {
      meshName: meshName,
      egressFilter: appmesh.MeshFilterType.ALLOW_ALL, // Allow external traffic
    });

    // Create ECR repositories for microservices
    this.ecrRepositories = {
      'service-a': new ecr.Repository(this, 'ServiceARepository', {
        repositoryName: `microservices-demo-service-a-${uniqueSuffix}`,
        imageScanOnPush: true,
        lifecycleRules: [{
          maxImageCount: 10,
          description: 'Keep only 10 images',
        }],
        removalPolicy: cdk.RemovalPolicy.DESTROY,
      }),
      'service-b': new ecr.Repository(this, 'ServiceBRepository', {
        repositoryName: `microservices-demo-service-b-${uniqueSuffix}`,
        imageScanOnPush: true,
        lifecycleRules: [{
          maxImageCount: 10,
          description: 'Keep only 10 images',
        }],
        removalPolicy: cdk.RemovalPolicy.DESTROY,
      }),
      'service-c': new ecr.Repository(this, 'ServiceCRepository', {
        repositoryName: `microservices-demo-service-c-${uniqueSuffix}`,
        imageScanOnPush: true,
        lifecycleRules: [{
          maxImageCount: 10,
          description: 'Keep only 10 images',
        }],
        removalPolicy: cdk.RemovalPolicy.DESTROY,
      }),
    };

    // Create IAM role for App Mesh controller
    const appMeshControllerRole = new iam.Role(this, 'AppMeshControllerRole', {
      roleName: `app-mesh-controller-role-${uniqueSuffix}`,
      assumedBy: new iam.WebIdentityPrincipal(
        this.cluster.openIdConnectProvider.openIdConnectProviderArn,
        {
          'StringEquals': {
            [`${this.cluster.openIdConnectProvider.openIdConnectProviderIssuer}:sub`]: 
              'system:serviceaccount:appmesh-system:appmesh-controller',
            [`${this.cluster.openIdConnectProvider.openIdConnectProviderIssuer}:aud`]: 
              'sts.amazonaws.com',
          },
        }
      ),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSCloudMapFullAccess'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSAppMeshFullAccess'),
      ],
    });

    // Create IAM role for X-Ray daemon
    const xrayDaemonRole = new iam.Role(this, 'XRayDaemonRole', {
      roleName: `xray-daemon-role-${uniqueSuffix}`,
      assumedBy: new iam.WebIdentityPrincipal(
        this.cluster.openIdConnectProvider.openIdConnectProviderArn,
        {
          'StringEquals': {
            [`${this.cluster.openIdConnectProvider.openIdConnectProviderIssuer}:sub`]: 
              'system:serviceaccount:production:xray-daemon',
            [`${this.cluster.openIdConnectProvider.openIdConnectProviderIssuer}:aud`]: 
              'sts.amazonaws.com',
          },
        }
      ),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSXRayDaemonWriteAccess'),
      ],
    });

    // Create IAM role for AWS Load Balancer Controller
    const albControllerRole = new iam.Role(this, 'ALBControllerRole', {
      roleName: `aws-load-balancer-controller-role-${uniqueSuffix}`,
      assumedBy: new iam.WebIdentityPrincipal(
        this.cluster.openIdConnectProvider.openIdConnectProviderArn,
        {
          'StringEquals': {
            [`${this.cluster.openIdConnectProvider.openIdConnectProviderIssuer}:sub`]: 
              'system:serviceaccount:kube-system:aws-load-balancer-controller',
            [`${this.cluster.openIdConnectProvider.openIdConnectProviderIssuer}:aud`]: 
              'sts.amazonaws.com',
          },
        }
      ),
    });

    // Add inline policy for ALB controller with comprehensive permissions
    albControllerRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
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
      resources: ['*'],
    }));

    albControllerRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
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
        'shield:GetSubscriptionState',
        'shield:DescribeSubscription',
        'shield:CreateProtection',
        'shield:DeleteProtection',
      ],
      resources: ['*'],
    }));

    albControllerRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'elasticloadbalancing:CreateLoadBalancer',
        'elasticloadbalancing:CreateTargetGroup',
      ],
      resources: ['*'],
      conditions: {
        StringEquals: {
          'elasticloadbalancing:CreateAction': [
            'CreateTargetGroup',
            'CreateLoadBalancer',
          ],
        },
      },
    }));

    albControllerRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'elasticloadbalancing:CreateListener',
        'elasticloadbalancing:DeleteListener',
        'elasticloadbalancing:CreateRule',
        'elasticloadbalancing:DeleteRule',
      ],
      resources: ['*'],
    }));

    albControllerRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'elasticloadbalancing:AddTags',
        'elasticloadbalancing:RemoveTags',
      ],
      resources: [
        'arn:aws:elasticloadbalancing:*:*:targetgroup/*/*',
        'arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*',
        'arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*',
      ],
      conditions: {
        StringEquals: {
          'elasticloadbalancing:CreateAction': [
            'CreateTargetGroup',
            'CreateLoadBalancer',
          ],
        },
      },
    }));

    albControllerRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'elasticloadbalancing:RegisterTargets',
        'elasticloadbalancing:DeregisterTargets',
      ],
      resources: ['arn:aws:elasticloadbalancing:*:*:targetgroup/*/*'],
    }));

    albControllerRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'elasticloadbalancing:SetWebAcl',
        'elasticloadbalancing:ModifyListener',
        'elasticloadbalancing:AddListenerCertificates',
        'elasticloadbalancing:RemoveListenerCertificates',
        'elasticloadbalancing:ModifyRule',
      ],
      resources: ['*'],
    }));

    // Install essential EKS add-ons
    this.installEksAddons();

    // Create CloudWatch dashboard for monitoring
    this.createMonitoringDashboard(clusterName);

    // Add outputs for important resources
    this.addOutputs(clusterName, meshName);

    // Add tags to all resources for better management
    cdk.Tags.of(this).add('Project', 'MicroservicesServiceMesh');
    cdk.Tags.of(this).add('Environment', 'Development');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
  }

  /**
   * Install essential EKS add-ons
   */
  private installEksAddons(): void {
    // AWS VPC CNI add-on for advanced networking
    new eks.CfnAddon(this, 'VpcCniAddon', {
      clusterName: this.cluster.clusterName,
      addonName: 'vpc-cni',
      resolveConflicts: 'OVERWRITE',
      configurationValues: JSON.stringify({
        enableNetworkPolicy: 'true',
      }),
    });

    // CoreDNS add-on for service discovery
    new eks.CfnAddon(this, 'CoreDnsAddon', {
      clusterName: this.cluster.clusterName,
      addonName: 'coredns',
      resolveConflicts: 'OVERWRITE',
    });

    // kube-proxy add-on for network proxy
    new eks.CfnAddon(this, 'KubeProxyAddon', {
      clusterName: this.cluster.clusterName,
      addonName: 'kube-proxy',
      resolveConflicts: 'OVERWRITE',
    });

    // EBS CSI driver for persistent volumes
    new eks.CfnAddon(this, 'EbsCsiAddon', {
      clusterName: this.cluster.clusterName,
      addonName: 'aws-ebs-csi-driver',
      resolveConflicts: 'OVERWRITE',
    });
  }

  /**
   * Create CloudWatch dashboard for monitoring cluster and service mesh metrics
   */
  private createMonitoringDashboard(clusterName: string): void {
    const dashboard = new cloudwatch.Dashboard(this, 'MicroservicesDashboard', {
      dashboardName: `microservices-service-mesh-${clusterName}`,
      defaultInterval: cdk.Duration.minutes(5),
    });

    // EKS cluster metrics
    const clusterCpuWidget = new cloudwatch.GraphWidget({
      title: 'EKS Cluster CPU Utilization',
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/ContainerInsights',
          metricName: 'cluster_cpu_utilization',
          dimensionsMap: {
            ClusterName: clusterName,
          },
          statistic: 'Average',
        }),
      ],
      width: 12,
      height: 6,
    });

    const clusterMemoryWidget = new cloudwatch.GraphWidget({
      title: 'EKS Cluster Memory Utilization',
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/ContainerInsights',
          metricName: 'cluster_memory_utilization',
          dimensionsMap: {
            ClusterName: clusterName,
          },
          statistic: 'Average',
        }),
      ],
      width: 12,
      height: 6,
    });

    // Service mesh metrics placeholder
    const meshTrafficWidget = new cloudwatch.GraphWidget({
      title: 'Service Mesh Traffic',
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/AppMesh',
          metricName: 'TargetResponseTime',
          dimensionsMap: {
            Mesh: this.mesh.meshName,
          },
          statistic: 'Average',
        }),
      ],
      width: 12,
      height: 6,
    });

    dashboard.addWidgets(clusterCpuWidget, clusterMemoryWidget);
    dashboard.addWidgets(meshTrafficWidget);
  }

  /**
   * Add CloudFormation outputs for key resources
   */
  private addOutputs(clusterName: string, meshName: string): void {
    // Cluster outputs
    new cdk.CfnOutput(this, 'ClusterName', {
      value: this.cluster.clusterName,
      description: 'EKS Cluster Name',
      exportName: `${this.stackName}-ClusterName`,
    });

    new cdk.CfnOutput(this, 'ClusterEndpoint', {
      value: this.cluster.clusterEndpoint,
      description: 'EKS Cluster Endpoint',
      exportName: `${this.stackName}-ClusterEndpoint`,
    });

    new cdk.CfnOutput(this, 'ClusterArn', {
      value: this.cluster.clusterArn,
      description: 'EKS Cluster ARN',
      exportName: `${this.stackName}-ClusterArn`,
    });

    // App Mesh outputs
    new cdk.CfnOutput(this, 'MeshName', {
      value: this.mesh.meshName,
      description: 'App Mesh Name',
      exportName: `${this.stackName}-MeshName`,
    });

    new cdk.CfnOutput(this, 'MeshArn', {
      value: this.mesh.meshArn,
      description: 'App Mesh ARN',
      exportName: `${this.stackName}-MeshArn`,
    });

    // ECR repository outputs
    Object.entries(this.ecrRepositories).forEach(([serviceName, repository]) => {
      new cdk.CfnOutput(this, `${serviceName}RepositoryUri`, {
        value: repository.repositoryUri,
        description: `ECR Repository URI for ${serviceName}`,
        exportName: `${this.stackName}-${serviceName}-RepositoryUri`,
      });
    });

    // VPC outputs
    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID',
      exportName: `${this.stackName}-VpcId`,
    });

    // kubectl configuration command
    new cdk.CfnOutput(this, 'ConfigCommand', {
      value: `aws eks update-kubeconfig --region ${this.region} --name ${clusterName}`,
      description: 'kubectl configuration command',
    });

    // Docker login commands for ECR
    new cdk.CfnOutput(this, 'DockerLoginCommand', {
      value: `aws ecr get-login-password --region ${this.region} | docker login --username AWS --password-stdin ${this.account}.dkr.ecr.${this.region}.amazonaws.com`,
      description: 'Docker login command for ECR',
    });
  }
}

/**
 * CDK Application
 */
const app = new cdk.App();

// Get environment from context or use defaults
const account = app.node.tryGetContext('account') || process.env.CDK_DEFAULT_ACCOUNT;
const region = app.node.tryGetContext('region') || process.env.CDK_DEFAULT_REGION || 'us-east-1';

// Deploy the microservices service mesh stack
new MicroservicesEksServiceMeshStack(app, 'MicroservicesEksServiceMeshStack', {
  env: {
    account: account,
    region: region,
  },
  description: 'Infrastructure for deploying microservices on EKS with AWS App Mesh service mesh',
  tags: {
    Project: 'MicroservicesServiceMesh',
    Environment: 'Development',
    ManagedBy: 'CDK',
    Recipe: 'microservices-eks-service-mesh-aws-app-mesh',
  },
});

// Synthesize the CDK app
app.synth();