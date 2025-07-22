#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as eks from 'aws-cdk-lib/aws-eks';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as appmesh from 'aws-cdk-lib/aws-appmesh';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import { Construct } from 'constructs';

/**
 * Props for the EKS App Mesh Stack
 */
interface EksAppMeshStackProps extends cdk.StackProps {
  /**
   * The name prefix for all resources
   * @default 'demo-mesh'
   */
  readonly namePrefix?: string;
  
  /**
   * The Kubernetes version for the EKS cluster
   * @default '1.28'
   */
  readonly kubernetesVersion?: eks.KubernetesVersion;
  
  /**
   * The instance type for EKS worker nodes
   * @default 'm5.large'
   */
  readonly nodeInstanceType?: ec2.InstanceType;
  
  /**
   * The desired capacity for the EKS node group
   * @default 3
   */
  readonly nodeDesiredCapacity?: number;
  
  /**
   * The minimum capacity for the EKS node group
   * @default 1
   */
  readonly nodeMinCapacity?: number;
  
  /**
   * The maximum capacity for the EKS node group
   * @default 4
   */
  readonly nodeMaxCapacity?: number;
}

/**
 * CDK Stack for deploying microservices on EKS with AWS App Mesh service mesh
 * 
 * This stack creates:
 * - VPC with public and private subnets
 * - EKS cluster with managed node group
 * - ECR repositories for microservices
 * - App Mesh configuration
 * - IAM roles and policies for App Mesh controller
 * - CloudWatch log groups for observability
 */
export class EksAppMeshStack extends cdk.Stack {
  public readonly cluster: eks.Cluster;
  public readonly mesh: appmesh.Mesh;
  public readonly ecrRepositories: { [key: string]: ecr.Repository };
  public readonly vpc: ec2.Vpc;

  constructor(scope: Construct, id: string, props: EksAppMeshStackProps = {}) {
    super(scope, id, props);

    // Generate random suffix for unique resource names
    const randomSuffix = this.generateRandomSuffix();
    const namePrefix = props.namePrefix || 'demo-mesh';
    const uniquePrefix = `${namePrefix}-${randomSuffix}`;

    // Create VPC with public and private subnets for EKS
    this.vpc = new ec2.Vpc(this, 'EksVpc', {
      vpcName: `${uniquePrefix}-vpc`,
      maxAzs: 3,
      natGateways: 1, // Cost optimization - use single NAT gateway
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'PublicSubnet',
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: 24,
          name: 'PrivateSubnet',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });

    // Tag VPC subnets for EKS discovery
    cdk.Tags.of(this.vpc).add('kubernetes.io/cluster/' + uniquePrefix, 'shared');
    
    // Tag public subnets for external load balancers
    this.vpc.publicSubnets.forEach((subnet, index) => {
      cdk.Tags.of(subnet).add('kubernetes.io/role/elb', '1');
      cdk.Tags.of(subnet).add('Name', `${uniquePrefix}-public-subnet-${index + 1}`);
    });
    
    // Tag private subnets for internal load balancers
    this.vpc.privateSubnets.forEach((subnet, index) => {
      cdk.Tags.of(subnet).add('kubernetes.io/role/internal-elb', '1');
      cdk.Tags.of(subnet).add('Name', `${uniquePrefix}-private-subnet-${index + 1}`);
    });

    // Create CloudWatch log group for EKS cluster
    const eksLogGroup = new logs.LogGroup(this, 'EksLogGroup', {
      logGroupName: `/aws/eks/${uniquePrefix}/cluster`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create EKS cluster with App Mesh support
    this.cluster = new eks.Cluster(this, 'EksCluster', {
      clusterName: uniquePrefix,
      version: props.kubernetesVersion || eks.KubernetesVersion.V1_28,
      vpc: this.vpc,
      vpcSubnets: [{ subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS }],
      defaultCapacity: 0, // We'll add managed node group separately
      clusterLogging: [
        eks.ClusterLoggingTypes.API,
        eks.ClusterLoggingTypes.AUTHENTICATOR,
        eks.ClusterLoggingTypes.SCHEDULER,
        eks.ClusterLoggingTypes.CONTROLLER_MANAGER,
      ],
      endpointAccess: eks.EndpointAccess.PUBLIC_AND_PRIVATE,
      outputClusterName: true,
      outputConfigCommand: true,
      albController: {
        version: eks.AlbControllerVersion.V2_6_2,
      },
    });

    // Create managed node group with mixed instance types and spot instances
    const nodeGroup = this.cluster.addNodegroupCapacity('ManagedNodeGroup', {
      nodegroupName: 'standard-workers',
      instanceTypes: [
        props.nodeInstanceType || ec2.InstanceType.of(ec2.InstanceClass.M5, ec2.InstanceSize.LARGE),
        ec2.InstanceType.of(ec2.InstanceClass.M5A, ec2.InstanceSize.LARGE),
        ec2.InstanceType.of(ec2.InstanceClass.M5D, ec2.InstanceSize.LARGE),
      ],
      capacityType: eks.CapacityType.SPOT, // Use spot instances for cost optimization
      desiredSize: props.nodeDesiredCapacity || 3,
      minSize: props.nodeMinCapacity || 1,
      maxSize: props.nodeMaxCapacity || 4,
      amiType: eks.NodegroupAmiType.AL2_X86_64,
      diskSize: 20, // GB
      subnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      labels: {
        'node-type': 'standard-worker',
        'capacity-type': 'spot',
      },
      taints: [],
    });

    // Create ECR repositories for microservices
    this.ecrRepositories = this.createEcrRepositories(uniquePrefix);

    // Create App Mesh
    this.mesh = new appmesh.Mesh(this, 'ServiceMesh', {
      meshName: uniquePrefix,
      egressFilter: appmesh.MeshFilterType.ALLOW_ALL,
    });

    // Create IAM role for App Mesh controller
    const appMeshControllerRole = this.createAppMeshControllerRole();

    // Install App Mesh controller using Helm
    this.installAppMeshController(appMeshControllerRole);

    // Create demo namespace and configure App Mesh injection
    this.createDemoNamespace(uniquePrefix);

    // Output important values
    this.createOutputs(uniquePrefix, randomSuffix);

    // Apply tags to all resources
    this.applyCommonTags(uniquePrefix);
  }

  /**
   * Generate a random suffix for unique resource naming
   */
  private generateRandomSuffix(): string {
    // Generate a 6-character random string using timestamp and random
    const timestamp = Date.now().toString(36);
    const random = Math.random().toString(36).substring(2, 5);
    return (timestamp + random).substring(0, 6).toLowerCase();
  }

  /**
   * Create ECR repositories for the microservices
   */
  private createEcrRepositories(namePrefix: string): { [key: string]: ecr.Repository } {
    const repositories: { [key: string]: ecr.Repository } = {};
    const services = ['frontend', 'backend', 'database'];

    services.forEach(service => {
      repositories[service] = new ecr.Repository(this, `${service}Repository`, {
        repositoryName: `${namePrefix}/${service}`,
        imageScanOnPush: true,
        imageTagMutability: ecr.TagMutability.MUTABLE,
        lifecycleRules: [
          {
            description: 'Keep last 10 images',
            maxImageCount: 10,
            rulePriority: 1,
            tagStatus: ecr.TagStatus.ANY,
          },
        ],
        removalPolicy: cdk.RemovalPolicy.DESTROY,
      });

      // Grant pull access to EKS worker nodes
      repositories[service].grantPull(this.cluster.defaultNodegroup?.role || nodeGroup.role);
    });

    return repositories;
  }

  /**
   * Create IAM role for App Mesh controller
   */
  private createAppMeshControllerRole(): iam.Role {
    const role = new iam.Role(this, 'AppMeshControllerRole', {
      roleName: `AppMeshControllerRole-${this.stackName}`,
      assumedBy: new iam.ServicePrincipal('pods.eks.amazonaws.com'),
      description: 'IAM role for App Mesh controller service account',
    });

    // Attach required policies for App Mesh controller
    role.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName('AWSAppMeshFullAccess')
    );
    role.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName('AWSCloudMapFullAccess')
    );

    // Add OIDC trust relationship for the service account
    const condition = new cdk.CfnJson(this, 'AppMeshControllerCondition', {
      value: {
        [`${this.cluster.clusterOpenIdConnectIssuer}:sub`]: 'system:serviceaccount:appmesh-system:appmesh-controller',
        [`${this.cluster.clusterOpenIdConnectIssuer}:aud`]: 'sts.amazonaws.com',
      },
    });

    role.assumeRolePolicy?.addStatements(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        principals: [
          new iam.FederatedPrincipal(
            this.cluster.openIdConnectProvider.openIdConnectProviderArn,
            {
              StringEquals: condition,
            },
            'sts:AssumeRoleWithWebIdentity'
          ),
        ],
      })
    );

    return role;
  }

  /**
   * Install App Mesh controller using Helm chart
   */
  private installAppMeshController(serviceAccountRole: iam.Role): void {
    // Add EKS Helm repository
    const appMeshControllerChart = this.cluster.addHelmChart('AppMeshController', {
      chart: 'appmesh-controller',
      repository: 'https://aws.github.io/eks-charts',
      namespace: 'appmesh-system',
      createNamespace: true,
      values: {
        region: this.region,
        serviceAccount: {
          create: false,
          name: 'appmesh-controller',
          annotations: {
            'eks.amazonaws.com/role-arn': serviceAccountRole.roleArn,
          },
        },
        replicaCount: 1,
        image: {
          tag: 'v1.12.6',
        },
        resources: {
          requests: {
            memory: '64Mi',
            cpu: '25m',
          },
          limits: {
            memory: '128Mi',
            cpu: '50m',
          },
        },
        env: {
          ENABLE_LOGGING: 'true',
          LOG_LEVEL: 'info',
        },
      },
      wait: true,
      timeout: cdk.Duration.minutes(10),
    });

    // Create service account for App Mesh controller
    const appMeshServiceAccount = this.cluster.addServiceAccount('AppMeshControllerServiceAccount', {
      name: 'appmesh-controller',
      namespace: 'appmesh-system',
      annotations: {
        'eks.amazonaws.com/role-arn': serviceAccountRole.roleArn,
      },
    });

    // Apply App Mesh CRDs
    const appMeshCrds = this.cluster.addManifest('AppMeshCRDs', {
      apiVersion: 'v1',
      kind: 'ConfigMap',
      metadata: {
        name: 'appmesh-crds-installer',
        namespace: 'appmesh-system',
      },
      data: {
        'install-crds.sh': `#!/bin/bash
          kubectl apply -k "https://github.com/aws/eks-charts/stable/appmesh-controller/crds?ref=master"
        `,
      },
    });

    // Ensure proper dependency order
    appMeshControllerChart.node.addDependency(appMeshServiceAccount);
    appMeshControllerChart.node.addDependency(appMeshCrds);
  }

  /**
   * Create demo namespace and configure for App Mesh injection
   */
  private createDemoNamespace(meshName: string): void {
    // Create demo namespace
    const demoNamespace = this.cluster.addManifest('DemoNamespace', {
      apiVersion: 'v1',
      kind: 'Namespace',
      metadata: {
        name: 'demo',
        labels: {
          name: 'demo',
          mesh: meshName,
          'appmesh.k8s.aws/sidecarInjectorWebhook': 'enabled',
        },
      },
    });

    // Create App Mesh mesh resource in Kubernetes
    const meshResource = this.cluster.addManifest('AppMeshResource', {
      apiVersion: 'appmesh.k8s.aws/v1beta2',
      kind: 'Mesh',
      metadata: {
        name: meshName,
        namespace: 'demo',
      },
      spec: {
        namespaceSelector: {
          matchLabels: {
            mesh: meshName,
          },
        },
        egressFilter: {
          type: 'ALLOW_ALL',
        },
      },
    });

    // X-Ray daemon for distributed tracing
    const xrayDaemon = this.cluster.addManifest('XRayDaemon', {
      apiVersion: 'apps/v1',
      kind: 'DaemonSet',
      metadata: {
        name: 'xray-daemon',
        namespace: 'demo',
      },
      spec: {
        selector: {
          matchLabels: {
            app: 'xray-daemon',
          },
        },
        template: {
          metadata: {
            labels: {
              app: 'xray-daemon',
            },
          },
          spec: {
            containers: [
              {
                name: 'xray-daemon',
                image: 'amazon/aws-xray-daemon:latest',
                ports: [
                  {
                    containerPort: 2000,
                    protocol: 'UDP',
                  },
                ],
                resources: {
                  requests: {
                    memory: '32Mi',
                    cpu: '25m',
                  },
                  limits: {
                    memory: '64Mi',
                    cpu: '50m',
                  },
                },
              },
            ],
          },
        },
      },
    });

    // X-Ray service
    const xrayService = this.cluster.addManifest('XRayService', {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: {
        name: 'xray-service',
        namespace: 'demo',
      },
      spec: {
        selector: {
          app: 'xray-daemon',
        },
        ports: [
          {
            port: 2000,
            protocol: 'UDP',
          },
        ],
        type: 'ClusterIP',
      },
    });

    // Ensure proper dependency order
    meshResource.node.addDependency(demoNamespace);
    xrayDaemon.node.addDependency(demoNamespace);
    xrayService.node.addDependency(xrayDaemon);
  }

  /**
   * Create CloudFormation outputs for important values
   */
  private createOutputs(namePrefix: string, randomSuffix: string): void {
    new cdk.CfnOutput(this, 'ClusterName', {
      description: 'Name of the EKS cluster',
      value: this.cluster.clusterName,
      exportName: `${this.stackName}-ClusterName`,
    });

    new cdk.CfnOutput(this, 'ClusterEndpoint', {
      description: 'Endpoint URL of the EKS cluster',
      value: this.cluster.clusterEndpoint,
      exportName: `${this.stackName}-ClusterEndpoint`,
    });

    new cdk.CfnOutput(this, 'ClusterArn', {
      description: 'ARN of the EKS cluster',
      value: this.cluster.clusterArn,
      exportName: `${this.stackName}-ClusterArn`,
    });

    new cdk.CfnOutput(this, 'MeshName', {
      description: 'Name of the App Mesh',
      value: this.mesh.meshName,
      exportName: `${this.stackName}-MeshName`,
    });

    new cdk.CfnOutput(this, 'MeshArn', {
      description: 'ARN of the App Mesh',
      value: this.mesh.meshArn,
      exportName: `${this.stackName}-MeshArn`,
    });

    new cdk.CfnOutput(this, 'VpcId', {
      description: 'ID of the VPC',
      value: this.vpc.vpcId,
      exportName: `${this.stackName}-VpcId`,
    });

    // Output ECR repository URIs
    Object.entries(this.ecrRepositories).forEach(([service, repo]) => {
      new cdk.CfnOutput(this, `${service}RepositoryUri`, {
        description: `ECR repository URI for ${service} service`,
        value: repo.repositoryUri,
        exportName: `${this.stackName}-${service}RepositoryUri`,
      });
    });

    new cdk.CfnOutput(this, 'RandomSuffix', {
      description: 'Random suffix used for resource naming',
      value: randomSuffix,
      exportName: `${this.stackName}-RandomSuffix`,
    });

    new cdk.CfnOutput(this, 'KubectlCommand', {
      description: 'Command to configure kubectl',
      value: `aws eks update-kubeconfig --region ${this.region} --name ${this.cluster.clusterName}`,
    });

    new cdk.CfnOutput(this, 'ECRLoginCommand', {
      description: 'Command to login to ECR',
      value: `aws ecr get-login-password --region ${this.region} | docker login --username AWS --password-stdin ${this.account}.dkr.ecr.${this.region}.amazonaws.com`,
    });
  }

  /**
   * Apply common tags to all resources in the stack
   */
  private applyCommonTags(namePrefix: string): void {
    const commonTags = {
      Project: 'microservices-eks-app-mesh',
      Environment: 'demo',
      ManagedBy: 'CDK',
      Owner: 'aws-recipe',
      CostCenter: 'engineering',
      'kubernetes.io/cluster/' + namePrefix: 'owned',
    };

    Object.entries(commonTags).forEach(([key, value]) => {
      cdk.Tags.of(this).add(key, value);
    });
  }
}

/**
 * CDK App definition
 */
const app = new cdk.App();

// Get context values or use defaults
const namePrefix = app.node.tryGetContext('namePrefix') || 'demo-mesh';
const kubernetesVersion = app.node.tryGetContext('kubernetesVersion') || '1.28';
const nodeInstanceType = app.node.tryGetContext('nodeInstanceType') || 'm5.large';
const nodeDesiredCapacity = Number(app.node.tryGetContext('nodeDesiredCapacity')) || 3;
const nodeMinCapacity = Number(app.node.tryGetContext('nodeMinCapacity')) || 1;
const nodeMaxCapacity = Number(app.node.tryGetContext('nodeMaxCapacity')) || 4;

// Create the stack
new EksAppMeshStack(app, 'EksAppMeshStack', {
  namePrefix,
  kubernetesVersion: eks.KubernetesVersion.of(kubernetesVersion),
  nodeInstanceType: ec2.InstanceType.of(
    ec2.InstanceClass.M5,
    ec2.InstanceSize.LARGE
  ),
  nodeDesiredCapacity,
  nodeMinCapacity,
  nodeMaxCapacity,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
  },
  description: 'CDK stack for deploying microservices on EKS with AWS App Mesh service mesh - Advanced container orchestration with service mesh capabilities',
  tags: {
    Project: 'microservices-eks-app-mesh',
    Environment: 'demo',
    ManagedBy: 'CDK',
  },
});

// Synthesize the app
app.synth();