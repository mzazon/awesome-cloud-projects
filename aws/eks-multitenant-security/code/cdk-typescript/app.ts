#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as eks from 'aws-cdk-lib/aws-eks';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * Stack for EKS Multi-Tenant Security with Namespaces
 */
export class EksMultiTenantSecurityStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Configuration parameters
    const clusterName = 'multi-tenant-cluster';
    const tenantAName = 'tenant-alpha';
    const tenantBName = 'tenant-beta';

    // Create VPC for the EKS cluster
    const vpc = new ec2.Vpc(this, 'EksVpc', {
      maxAzs: 3,
      natGateways: 1,
      ipAddresses: ec2.IpAddresses.cidr('10.0.0.0/16'),
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
        },
      ],
    });

    // Create CloudWatch log group for EKS cluster logs
    const logGroup = new logs.LogGroup(this, 'EksClusterLogGroup', {
      logGroupName: `/aws/eks/${clusterName}/cluster`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create EKS cluster service role
    const clusterRole = new iam.Role(this, 'EksClusterRole', {
      assumedBy: new iam.ServicePrincipal('eks.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEKSClusterPolicy'),
      ],
      description: 'EKS cluster service role for multi-tenant security',
    });

    // Create EKS node group role
    const nodeRole = new iam.Role(this, 'EksNodeRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEKSWorkerNodePolicy'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEKS_CNI_Policy'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEC2ContainerRegistryReadOnly'),
      ],
      description: 'EKS node group role for multi-tenant security',
    });

    // Create EKS cluster with security-focused configuration
    const cluster = new eks.Cluster(this, 'EksCluster', {
      clusterName: clusterName,
      version: eks.KubernetesVersion.V1_28,
      vpc: vpc,
      role: clusterRole,
      defaultCapacity: 0, // We'll create a custom node group
      clusterLogging: [
        eks.ClusterLoggingTypes.API,
        eks.ClusterLoggingTypes.AUDIT,
        eks.ClusterLoggingTypes.AUTHENTICATOR,
        eks.ClusterLoggingTypes.CONTROLLER_MANAGER,
        eks.ClusterLoggingTypes.SCHEDULER,
      ],
      endpointAccess: eks.EndpointAccess.PRIVATE_AND_PUBLIC,
      outputClusterName: true,
      outputConfigCommand: true,
      prune: false,
    });

    // Create managed node group with security optimizations
    const nodeGroup = cluster.addNodegroupCapacity('EksNodeGroup', {
      instanceTypes: [new ec2.InstanceType('m5.large')],
      minSize: 2,
      maxSize: 4,
      desiredSize: 3,
      diskSize: 20,
      nodeRole: nodeRole,
      amiType: eks.NodegroupAmiType.AL2_X86_64,
      capacityType: eks.CapacityType.ON_DEMAND,
      subnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
      labels: {
        'node-security': 'multi-tenant',
        'environment': 'production',
      },
      taints: [
        {
          key: 'multi-tenant',
          value: 'true',
          effect: eks.TaintEffect.NO_SCHEDULE,
        },
      ],
    });

    // Create IAM roles for tenant access
    const tenantATrustPolicy = new iam.PolicyDocument({
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          principals: [new iam.AccountRootPrincipal()],
          actions: ['sts:AssumeRole'],
        }),
      ],
    });

    const tenantBTrustPolicy = new iam.PolicyDocument({
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          principals: [new iam.AccountRootPrincipal()],
          actions: ['sts:AssumeRole'],
        }),
      ],
    });

    const tenantARole = new iam.Role(this, 'TenantARole', {
      roleName: `${tenantAName}-eks-role`,
      assumeRolePolicy: tenantATrustPolicy,
      description: 'IAM role for Tenant A with EKS access',
    });

    const tenantBRole = new iam.Role(this, 'TenantBRole', {
      roleName: `${tenantBName}-eks-role`,
      assumeRolePolicy: tenantBTrustPolicy,
      description: 'IAM role for Tenant B with EKS access',
    });

    // Create EKS access entries for tenant roles
    const tenantAAccessEntry = new eks.AccessEntry(this, 'TenantAAccessEntry', {
      cluster: cluster,
      principal: tenantARole.roleArn,
      accessEntryName: `${tenantAName}-access-entry`,
      accessEntryType: eks.AccessEntryType.STANDARD,
      username: `${tenantAName}-user`,
    });

    const tenantBAccessEntry = new eks.AccessEntry(this, 'TenantBAccessEntry', {
      cluster: cluster,
      principal: tenantBRole.roleArn,
      accessEntryName: `${tenantBName}-access-entry`,
      accessEntryType: eks.AccessEntryType.STANDARD,
      username: `${tenantBName}-user`,
    });

    // Create Kubernetes namespaces with labels for tenant isolation
    const tenantANamespace = cluster.addManifest('TenantANamespace', {
      apiVersion: 'v1',
      kind: 'Namespace',
      metadata: {
        name: tenantAName,
        labels: {
          'tenant': 'alpha',
          'isolation': 'enabled',
          'environment': 'production',
        },
      },
    });

    const tenantBNamespace = cluster.addManifest('TenantBNamespace', {
      apiVersion: 'v1',
      kind: 'Namespace',
      metadata: {
        name: tenantBName,
        labels: {
          'tenant': 'beta',
          'isolation': 'enabled',
          'environment': 'production',
        },
      },
    });

    // Create RBAC roles for tenant A
    const tenantARole = cluster.addManifest('TenantARole', {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'Role',
      metadata: {
        namespace: tenantAName,
        name: `${tenantAName}-role`,
      },
      rules: [
        {
          apiGroups: [''],
          resources: ['pods', 'services', 'configmaps', 'secrets', 'persistentvolumeclaims'],
          verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete'],
        },
        {
          apiGroups: ['apps'],
          resources: ['deployments', 'replicasets', 'daemonsets', 'statefulsets'],
          verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete'],
        },
        {
          apiGroups: ['networking.k8s.io'],
          resources: ['ingresses', 'networkpolicies'],
          verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete'],
        },
      ],
    });

    const tenantARoleBinding = cluster.addManifest('TenantARoleBinding', {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'RoleBinding',
      metadata: {
        name: `${tenantAName}-binding`,
        namespace: tenantAName,
      },
      subjects: [
        {
          kind: 'User',
          name: `${tenantAName}-user`,
          apiGroup: 'rbac.authorization.k8s.io',
        },
      ],
      roleRef: {
        kind: 'Role',
        name: `${tenantAName}-role`,
        apiGroup: 'rbac.authorization.k8s.io',
      },
    });

    // Create RBAC roles for tenant B
    const tenantBRole = cluster.addManifest('TenantBRole', {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'Role',
      metadata: {
        namespace: tenantBName,
        name: `${tenantBName}-role`,
      },
      rules: [
        {
          apiGroups: [''],
          resources: ['pods', 'services', 'configmaps', 'secrets', 'persistentvolumeclaims'],
          verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete'],
        },
        {
          apiGroups: ['apps'],
          resources: ['deployments', 'replicasets', 'daemonsets', 'statefulsets'],
          verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete'],
        },
        {
          apiGroups: ['networking.k8s.io'],
          resources: ['ingresses', 'networkpolicies'],
          verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete'],
        },
      ],
    });

    const tenantBRoleBinding = cluster.addManifest('TenantBRoleBinding', {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'RoleBinding',
      metadata: {
        name: `${tenantBName}-binding`,
        namespace: tenantBName,
      },
      subjects: [
        {
          kind: 'User',
          name: `${tenantBName}-user`,
          apiGroup: 'rbac.authorization.k8s.io',
        },
      ],
      roleRef: {
        kind: 'Role',
        name: `${tenantBName}-role`,
        apiGroup: 'rbac.authorization.k8s.io',
      },
    });

    // Create network policies for tenant isolation
    const tenantANetworkPolicy = cluster.addManifest('TenantANetworkPolicy', {
      apiVersion: 'networking.k8s.io/v1',
      kind: 'NetworkPolicy',
      metadata: {
        name: `${tenantAName}-isolation`,
        namespace: tenantAName,
      },
      spec: {
        podSelector: {},
        policyTypes: ['Ingress', 'Egress'],
        ingress: [
          {
            from: [
              {
                namespaceSelector: {
                  matchLabels: {
                    tenant: 'alpha',
                  },
                },
              },
            ],
          },
          {
            from: [
              {
                namespaceSelector: {
                  matchLabels: {
                    name: 'kube-system',
                  },
                },
              },
            ],
          },
        ],
        egress: [
          {
            to: [
              {
                namespaceSelector: {
                  matchLabels: {
                    tenant: 'alpha',
                  },
                },
              },
            ],
          },
          {
            to: [
              {
                namespaceSelector: {
                  matchLabels: {
                    name: 'kube-system',
                  },
                },
              },
            ],
          },
          {
            to: [],
            ports: [
              {
                protocol: 'TCP',
                port: 53,
              },
              {
                protocol: 'UDP',
                port: 53,
              },
            ],
          },
        ],
      },
    });

    const tenantBNetworkPolicy = cluster.addManifest('TenantBNetworkPolicy', {
      apiVersion: 'networking.k8s.io/v1',
      kind: 'NetworkPolicy',
      metadata: {
        name: `${tenantBName}-isolation`,
        namespace: tenantBName,
      },
      spec: {
        podSelector: {},
        policyTypes: ['Ingress', 'Egress'],
        ingress: [
          {
            from: [
              {
                namespaceSelector: {
                  matchLabels: {
                    tenant: 'beta',
                  },
                },
              },
            ],
          },
          {
            from: [
              {
                namespaceSelector: {
                  matchLabels: {
                    name: 'kube-system',
                  },
                },
              },
            ],
          },
        ],
        egress: [
          {
            to: [
              {
                namespaceSelector: {
                  matchLabels: {
                    tenant: 'beta',
                  },
                },
              },
            ],
          },
          {
            to: [
              {
                namespaceSelector: {
                  matchLabels: {
                    name: 'kube-system',
                  },
                },
              },
            ],
          },
          {
            to: [],
            ports: [
              {
                protocol: 'TCP',
                port: 53,
              },
              {
                protocol: 'UDP',
                port: 53,
              },
            ],
          },
        ],
      },
    });

    // Create resource quotas for tenant A
    const tenantAResourceQuota = cluster.addManifest('TenantAResourceQuota', {
      apiVersion: 'v1',
      kind: 'ResourceQuota',
      metadata: {
        name: `${tenantAName}-quota`,
        namespace: tenantAName,
      },
      spec: {
        hard: {
          'requests.cpu': '2',
          'requests.memory': '4Gi',
          'limits.cpu': '4',
          'limits.memory': '8Gi',
          'pods': '10',
          'services': '5',
          'secrets': '10',
          'configmaps': '10',
          'persistentvolumeclaims': '4',
        },
      },
    });

    const tenantALimitRange = cluster.addManifest('TenantALimitRange', {
      apiVersion: 'v1',
      kind: 'LimitRange',
      metadata: {
        name: `${tenantAName}-limits`,
        namespace: tenantAName,
      },
      spec: {
        limits: [
          {
            default: {
              cpu: '200m',
              memory: '256Mi',
            },
            defaultRequest: {
              cpu: '100m',
              memory: '128Mi',
            },
            type: 'Container',
          },
        ],
      },
    });

    // Create resource quotas for tenant B
    const tenantBResourceQuota = cluster.addManifest('TenantBResourceQuota', {
      apiVersion: 'v1',
      kind: 'ResourceQuota',
      metadata: {
        name: `${tenantBName}-quota`,
        namespace: tenantBName,
      },
      spec: {
        hard: {
          'requests.cpu': '2',
          'requests.memory': '4Gi',
          'limits.cpu': '4',
          'limits.memory': '8Gi',
          'pods': '10',
          'services': '5',
          'secrets': '10',
          'configmaps': '10',
          'persistentvolumeclaims': '4',
        },
      },
    });

    const tenantBLimitRange = cluster.addManifest('TenantBLimitRange', {
      apiVersion: 'v1',
      kind: 'LimitRange',
      metadata: {
        name: `${tenantBName}-limits`,
        namespace: tenantBName,
      },
      spec: {
        limits: [
          {
            default: {
              cpu: '200m',
              memory: '256Mi',
            },
            defaultRequest: {
              cpu: '100m',
              memory: '128Mi',
            },
            type: 'Container',
          },
        ],
      },
    });

    // Create sample applications for testing tenant isolation
    const tenantADeployment = cluster.addManifest('TenantADeployment', {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: {
        name: `${tenantAName}-app`,
        namespace: tenantAName,
      },
      spec: {
        replicas: 2,
        selector: {
          matchLabels: {
            app: `${tenantAName}-app`,
          },
        },
        template: {
          metadata: {
            labels: {
              app: `${tenantAName}-app`,
            },
          },
          spec: {
            containers: [
              {
                name: 'app',
                image: 'nginx:1.20',
                ports: [
                  {
                    containerPort: 80,
                  },
                ],
                resources: {
                  requests: {
                    cpu: '100m',
                    memory: '128Mi',
                  },
                  limits: {
                    cpu: '200m',
                    memory: '256Mi',
                  },
                },
              },
            ],
          },
        },
      },
    });

    const tenantAService = cluster.addManifest('TenantAService', {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: {
        name: `${tenantAName}-service`,
        namespace: tenantAName,
      },
      spec: {
        selector: {
          app: `${tenantAName}-app`,
        },
        ports: [
          {
            port: 80,
            targetPort: 80,
          },
        ],
      },
    });

    const tenantBDeployment = cluster.addManifest('TenantBDeployment', {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: {
        name: `${tenantBName}-app`,
        namespace: tenantBName,
      },
      spec: {
        replicas: 2,
        selector: {
          matchLabels: {
            app: `${tenantBName}-app`,
          },
        },
        template: {
          metadata: {
            labels: {
              app: `${tenantBName}-app`,
            },
          },
          spec: {
            containers: [
              {
                name: 'app',
                image: 'httpd:2.4',
                ports: [
                  {
                    containerPort: 80,
                  },
                ],
                resources: {
                  requests: {
                    cpu: '100m',
                    memory: '128Mi',
                  },
                  limits: {
                    cpu: '200m',
                    memory: '256Mi',
                  },
                },
              },
            ],
          },
        },
      },
    });

    const tenantBService = cluster.addManifest('TenantBService', {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: {
        name: `${tenantBName}-service`,
        namespace: tenantBName,
      },
      spec: {
        selector: {
          app: `${tenantBName}-app`,
        },
        ports: [
          {
            port: 80,
            targetPort: 80,
          },
        ],
      },
    });

    // Ensure proper dependency ordering
    tenantARole.node.addDependency(tenantANamespace);
    tenantARoleBinding.node.addDependency(tenantARole);
    tenantANetworkPolicy.node.addDependency(tenantANamespace);
    tenantAResourceQuota.node.addDependency(tenantANamespace);
    tenantALimitRange.node.addDependency(tenantANamespace);
    tenantADeployment.node.addDependency(tenantAResourceQuota, tenantALimitRange);
    tenantAService.node.addDependency(tenantADeployment);

    tenantBRole.node.addDependency(tenantBNamespace);
    tenantBRoleBinding.node.addDependency(tenantBRole);
    tenantBNetworkPolicy.node.addDependency(tenantBNamespace);
    tenantBResourceQuota.node.addDependency(tenantBNamespace);
    tenantBLimitRange.node.addDependency(tenantBNamespace);
    tenantBDeployment.node.addDependency(tenantBResourceQuota, tenantBLimitRange);
    tenantBService.node.addDependency(tenantBDeployment);

    // CloudFormation outputs
    new cdk.CfnOutput(this, 'EksClusterName', {
      value: cluster.clusterName,
      description: 'Name of the EKS cluster',
    });

    new cdk.CfnOutput(this, 'EksClusterArn', {
      value: cluster.clusterArn,
      description: 'ARN of the EKS cluster',
    });

    new cdk.CfnOutput(this, 'EksClusterEndpoint', {
      value: cluster.clusterEndpoint,
      description: 'Endpoint of the EKS cluster',
    });

    new cdk.CfnOutput(this, 'TenantARole', {
      value: tenantARole.roleArn,
      description: 'ARN of the IAM role for Tenant A',
    });

    new cdk.CfnOutput(this, 'TenantBRole', {
      value: tenantBRole.roleArn,
      description: 'ARN of the IAM role for Tenant B',
    });

    new cdk.CfnOutput(this, 'VpcId', {
      value: vpc.vpcId,
      description: 'VPC ID where the EKS cluster is deployed',
    });

    new cdk.CfnOutput(this, 'KubectlConfigCommand', {
      value: `aws eks update-kubeconfig --region ${this.region} --name ${cluster.clusterName}`,
      description: 'Command to configure kubectl for the EKS cluster',
    });
  }
}

// CDK App
const app = new cdk.App();

new EksMultiTenantSecurityStack(app, 'EksMultiTenantSecurityStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'EKS Multi-Tenant Cluster Security with Namespace Isolation',
  tags: {
    Project: 'EKS-MultiTenant-Security',
    Environment: 'Production',
    Security: 'Enabled',
  },
});