#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as eks from 'aws-cdk-lib/aws-eks';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * Stack for EKS cluster with comprehensive auto-scaling capabilities
 * Includes HPA, Cluster Autoscaler, KEDA, and monitoring components
 */
class EKSAutoScalingStack extends cdk.Stack {
  public readonly cluster: eks.Cluster;
  public readonly vpc: ec2.Vpc;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Create VPC with public and private subnets across 3 AZs
    this.vpc = new ec2.Vpc(this, 'EKSAutoScalingVPC', {
      maxAzs: 3,
      cidr: '10.0.0.0/16',
      enableDnsHostnames: true,
      enableDnsSupport: true,
      subnetConfiguration: [
        {
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
          cidrMask: 24,
        },
        {
          name: 'Private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
          cidrMask: 24,
        },
      ],
    });

    // Create KMS key for EKS cluster encryption
    const eksKmsKey = new kms.Key(this, 'EKSClusterKMSKey', {
      description: 'KMS key for EKS cluster encryption',
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create cluster admin role
    const clusterAdminRole = new iam.Role(this, 'EKSClusterAdminRole', {
      roleName: 'EKSClusterAdminRole',
      assumedBy: new iam.AccountPrincipal(this.account),
      description: 'Admin role for EKS cluster',
    });

    // Create EKS cluster with latest version and best practices
    this.cluster = new eks.Cluster(this, 'EKSAutoScalingCluster', {
      clusterName: 'eks-autoscaling-demo',
      version: eks.KubernetesVersion.V1_28,
      vpc: this.vpc,
      vpcSubnets: [{ subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS }],
      defaultCapacity: 0, // We'll add managed node groups explicitly
      endpointAccess: eks.EndpointAccess.PUBLIC_AND_PRIVATE,
      secretsEncryptionKey: eksKmsKey,
      clusterLogging: [
        eks.ClusterLoggingTypes.API,
        eks.ClusterLoggingTypes.AUTHENTICATOR,
        eks.ClusterLoggingTypes.AUDIT,
        eks.ClusterLoggingTypes.CONTROLLER_MANAGER,
        eks.ClusterLoggingTypes.SCHEDULER,
      ],
      mastersRole: clusterAdminRole,
      outputClusterName: true,
      outputMastersRoleArn: true,
      outputConfigCommand: true,
    });

    // Enable IRSA (IAM Roles for Service Accounts)
    this.cluster.openIdConnectProvider;

    // Create IAM role for Cluster Autoscaler
    const clusterAutoscalerRole = new iam.Role(this, 'ClusterAutoscalerRole', {
      roleName: 'EKSClusterAutoscalerRole',
      assumedBy: new iam.WebIdentityPrincipal(
        this.cluster.openIdConnectProvider.openIdConnectProviderArn,
        {
          StringEquals: {
            [`${this.cluster.openIdConnectProvider.openIdConnectProviderIssuer}:sub`]: 
              'system:serviceaccount:kube-system:cluster-autoscaler',
            [`${this.cluster.openIdConnectProvider.openIdConnectProviderIssuer}:aud`]: 
              'sts.amazonaws.com',
          },
        }
      ),
      description: 'IAM role for Cluster Autoscaler service account',
    });

    // Add permissions for Cluster Autoscaler
    clusterAutoscalerRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'autoscaling:DescribeAutoScalingGroups',
          'autoscaling:DescribeAutoScalingInstances',
          'autoscaling:DescribeLaunchConfigurations',
          'autoscaling:DescribeTags',
          'autoscaling:SetDesiredCapacity',
          'autoscaling:TerminateInstanceInAutoScalingGroup',
          'ec2:DescribeLaunchTemplateVersions',
          'ec2:DescribeImages',
          'ec2:DescribeInstanceTypes',
          'ec2:DescribeRouteTables',
          'ec2:DescribeSecurityGroups',
          'ec2:DescribeSubnets',
          'ec2:DescribeVolumes',
          'ec2:DescribeVpcs',
        ],
        resources: ['*'],
      })
    );

    // Create service account for Cluster Autoscaler
    const clusterAutoscalerSA = this.cluster.addServiceAccount('ClusterAutoscalerSA', {
      name: 'cluster-autoscaler',
      namespace: 'kube-system',
      annotations: {
        'eks.amazonaws.com/role-arn': clusterAutoscalerRole.roleArn,
      },
    });

    // Create general-purpose managed node group
    const generalPurposeNodeGroup = this.cluster.addNodegroupCapacity('GeneralPurposeNodeGroup', {
      nodegroupName: 'general-purpose',
      instanceTypes: [
        ec2.InstanceType.of(ec2.InstanceClass.M5, ec2.InstanceSize.LARGE),
        ec2.InstanceType.of(ec2.InstanceClass.M5, ec2.InstanceSize.XLARGE),
      ],
      minSize: 1,
      maxSize: 10,
      desiredSize: 2,
      diskSize: 20,
      amiType: eks.NodegroupAmiType.AL2_X86_64,
      capacityType: eks.CapacityType.ON_DEMAND,
      subnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      labels: {
        'workload-type': 'general',
        'node-group': 'general-purpose',
      },
      tags: {
        'k8s.io/cluster-autoscaler/enabled': 'true',
        [`k8s.io/cluster-autoscaler/${this.cluster.clusterName}`]: 'owned',
        'Name': 'GeneralPurposeNodeGroup',
      },
    });

    // Create compute-optimized managed node group
    const computeOptimizedNodeGroup = this.cluster.addNodegroupCapacity('ComputeOptimizedNodeGroup', {
      nodegroupName: 'compute-optimized',
      instanceTypes: [
        ec2.InstanceType.of(ec2.InstanceClass.C5, ec2.InstanceSize.LARGE),
        ec2.InstanceType.of(ec2.InstanceClass.C5, ec2.InstanceSize.XLARGE),
      ],
      minSize: 0,
      maxSize: 5,
      desiredSize: 1,
      diskSize: 20,
      amiType: eks.NodegroupAmiType.AL2_X86_64,
      capacityType: eks.CapacityType.ON_DEMAND,
      subnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      labels: {
        'workload-type': 'compute',
        'node-group': 'compute-optimized',
      },
      tags: {
        'k8s.io/cluster-autoscaler/enabled': 'true',
        [`k8s.io/cluster-autoscaler/${this.cluster.clusterName}`]: 'owned',
        'Name': 'ComputeOptimizedNodeGroup',
      },
    });

    // Install AWS EBS CSI Driver addon
    this.cluster.addAddon('aws-ebs-csi-driver', {
      addonName: 'aws-ebs-csi-driver',
      addonVersion: 'v1.26.0-eksbuild.1',
      resolveConflicts: eks.ResolveConflicts.OVERWRITE,
    });

    // Install AWS VPC CNI addon
    this.cluster.addAddon('vpc-cni', {
      addonName: 'vpc-cni',
      addonVersion: 'v1.15.4-eksbuild.1',
      resolveConflicts: eks.ResolveConflicts.OVERWRITE,
    });

    // Install CoreDNS addon
    this.cluster.addAddon('coredns', {
      addonName: 'coredns',
      addonVersion: 'v1.10.1-eksbuild.6',
      resolveConflicts: eks.ResolveConflicts.OVERWRITE,
    });

    // Install kube-proxy addon
    this.cluster.addAddon('kube-proxy', {
      addonName: 'kube-proxy',
      addonVersion: 'v1.28.2-eksbuild.2',
      resolveConflicts: eks.ResolveConflicts.OVERWRITE,
    });

    // Deploy Metrics Server
    this.cluster.addManifest('MetricsServer', {
      apiVersion: 'v1',
      kind: 'ServiceAccount',
      metadata: {
        name: 'metrics-server',
        namespace: 'kube-system',
        labels: {
          'k8s-app': 'metrics-server',
        },
      },
    });

    this.cluster.addManifest('MetricsServerClusterRole', {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'ClusterRole',
      metadata: {
        name: 'system:metrics-server',
        labels: {
          'k8s-app': 'metrics-server',
        },
      },
      rules: [
        {
          apiGroups: [''],
          resources: ['nodes/metrics'],
          verbs: ['get'],
        },
        {
          apiGroups: [''],
          resources: ['pods', 'nodes'],
          verbs: ['get', 'list', 'watch'],
        },
      ],
    });

    this.cluster.addManifest('MetricsServerClusterRoleBinding', {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'ClusterRoleBinding',
      metadata: {
        name: 'system:metrics-server',
        labels: {
          'k8s-app': 'metrics-server',
        },
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: 'system:metrics-server',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: 'metrics-server',
          namespace: 'kube-system',
        },
      ],
    });

    this.cluster.addManifest('MetricsServerDeployment', {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: {
        name: 'metrics-server',
        namespace: 'kube-system',
        labels: {
          'k8s-app': 'metrics-server',
        },
      },
      spec: {
        selector: {
          matchLabels: {
            'k8s-app': 'metrics-server',
          },
        },
        template: {
          metadata: {
            labels: {
              'k8s-app': 'metrics-server',
            },
          },
          spec: {
            serviceAccountName: 'metrics-server',
            containers: [
              {
                name: 'metrics-server',
                image: 'k8s.gcr.io/metrics-server/metrics-server:v0.6.4',
                imagePullPolicy: 'IfNotPresent',
                args: [
                  '--cert-dir=/tmp',
                  '--secure-port=4443',
                  '--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname',
                  '--kubelet-use-node-status-port',
                  '--metric-resolution=15s',
                ],
                resources: {
                  requests: {
                    cpu: '100m',
                    memory: '200Mi',
                  },
                },
                ports: [
                  {
                    name: 'https',
                    containerPort: 4443,
                    protocol: 'TCP',
                  },
                ],
                readinessProbe: {
                  httpGet: {
                    path: '/readyz',
                    port: 'https',
                    scheme: 'HTTPS',
                  },
                  periodSeconds: 10,
                  failureThreshold: 3,
                  initialDelaySeconds: 20,
                },
                livenessProbe: {
                  httpGet: {
                    path: '/livez',
                    port: 'https',
                    scheme: 'HTTPS',
                  },
                  periodSeconds: 10,
                  failureThreshold: 3,
                  initialDelaySeconds: 20,
                },
                securityContext: {
                  allowPrivilegeEscalation: false,
                  readOnlyRootFilesystem: true,
                  runAsNonRoot: true,
                  runAsUser: 1000,
                  capabilities: {
                    drop: ['ALL'],
                  },
                },
                volumeMounts: [
                  {
                    name: 'tmp-dir',
                    mountPath: '/tmp',
                  },
                ],
              },
            ],
            volumes: [
              {
                name: 'tmp-dir',
                emptyDir: {},
              },
            ],
            priorityClassName: 'system-cluster-critical',
            nodeSelector: {
              'kubernetes.io/os': 'linux',
            },
          },
        },
      },
    });

    this.cluster.addManifest('MetricsServerService', {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: {
        name: 'metrics-server',
        namespace: 'kube-system',
        labels: {
          'k8s-app': 'metrics-server',
        },
      },
      spec: {
        selector: {
          'k8s-app': 'metrics-server',
        },
        ports: [
          {
            name: 'https',
            port: 443,
            protocol: 'TCP',
            targetPort: 'https',
          },
        ],
      },
    });

    this.cluster.addManifest('MetricsServerAPIService', {
      apiVersion: 'apiregistration.k8s.io/v1',
      kind: 'APIService',
      metadata: {
        name: 'v1beta1.metrics.k8s.io',
        labels: {
          'k8s-app': 'metrics-server',
        },
      },
      spec: {
        service: {
          name: 'metrics-server',
          namespace: 'kube-system',
        },
        group: 'metrics.k8s.io',
        version: 'v1beta1',
        insecureSkipTLSVerify: true,
        groupPriorityMinimum: 100,
        versionPriority: 100,
      },
    });

    // Deploy Cluster Autoscaler
    this.cluster.addManifest('ClusterAutoscalerDeployment', {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: {
        name: 'cluster-autoscaler',
        namespace: 'kube-system',
        labels: {
          app: 'cluster-autoscaler',
        },
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: {
            app: 'cluster-autoscaler',
          },
        },
        template: {
          metadata: {
            labels: {
              app: 'cluster-autoscaler',
            },
            annotations: {
              'prometheus.io/scrape': 'true',
              'prometheus.io/port': '8085',
            },
          },
          spec: {
            serviceAccountName: 'cluster-autoscaler',
            containers: [
              {
                name: 'cluster-autoscaler',
                image: 'k8s.gcr.io/autoscaling/cluster-autoscaler:v1.28.2',
                imagePullPolicy: 'Always',
                command: [
                  './cluster-autoscaler',
                  '--v=4',
                  '--stderrthreshold=info',
                  '--cloud-provider=aws',
                  '--skip-nodes-with-local-storage=false',
                  '--expander=least-waste',
                  `--node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/${this.cluster.clusterName}`,
                  '--balance-similar-node-groups',
                  '--skip-nodes-with-system-pods=false',
                  '--scale-down-delay-after-add=10m',
                  '--scale-down-unneeded-time=10m',
                  '--scale-down-delay-after-delete=10s',
                  '--scale-down-utilization-threshold=0.5',
                ],
                resources: {
                  limits: {
                    cpu: '100m',
                    memory: '300Mi',
                  },
                  requests: {
                    cpu: '100m',
                    memory: '300Mi',
                  },
                },
                env: [
                  {
                    name: 'AWS_REGION',
                    value: this.region,
                  },
                ],
                volumeMounts: [
                  {
                    name: 'ssl-certs',
                    mountPath: '/etc/ssl/certs/ca-certificates.crt',
                    readOnly: true,
                  },
                ],
              },
            ],
            volumes: [
              {
                name: 'ssl-certs',
                hostPath: {
                  path: '/etc/ssl/certs/ca-bundle.crt',
                },
              },
            ],
            priorityClassName: 'system-cluster-critical',
            nodeSelector: {
              'kubernetes.io/os': 'linux',
            },
          },
        },
      },
    });

    // Create demo-apps namespace
    this.cluster.addManifest('DemoAppsNamespace', {
      apiVersion: 'v1',
      kind: 'Namespace',
      metadata: {
        name: 'demo-apps',
        labels: {
          name: 'demo-apps',
        },
      },
    });

    // Create monitoring namespace
    this.cluster.addManifest('MonitoringNamespace', {
      apiVersion: 'v1',
      kind: 'Namespace',
      metadata: {
        name: 'monitoring',
        labels: {
          name: 'monitoring',
        },
      },
    });

    // Deploy CPU-intensive demo application
    this.cluster.addManifest('CPUDemoDeployment', {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: {
        name: 'cpu-demo',
        namespace: 'demo-apps',
        labels: {
          app: 'cpu-demo',
        },
      },
      spec: {
        replicas: 2,
        selector: {
          matchLabels: {
            app: 'cpu-demo',
          },
        },
        template: {
          metadata: {
            labels: {
              app: 'cpu-demo',
            },
          },
          spec: {
            containers: [
              {
                name: 'cpu-demo',
                image: 'k8s.gcr.io/hpa-example',
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
                    cpu: '500m',
                    memory: '256Mi',
                  },
                },
              },
            ],
            nodeSelector: {
              'workload-type': 'general',
            },
          },
        },
      },
    });

    this.cluster.addManifest('CPUDemoService', {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: {
        name: 'cpu-demo-service',
        namespace: 'demo-apps',
        labels: {
          app: 'cpu-demo',
        },
      },
      spec: {
        selector: {
          app: 'cpu-demo',
        },
        ports: [
          {
            port: 80,
            targetPort: 80,
          },
        ],
      },
    });

    this.cluster.addManifest('CPUDemoHPA', {
      apiVersion: 'autoscaling/v2',
      kind: 'HorizontalPodAutoscaler',
      metadata: {
        name: 'cpu-demo-hpa',
        namespace: 'demo-apps',
      },
      spec: {
        scaleTargetRef: {
          apiVersion: 'apps/v1',
          kind: 'Deployment',
          name: 'cpu-demo',
        },
        minReplicas: 2,
        maxReplicas: 20,
        metrics: [
          {
            type: 'Resource',
            resource: {
              name: 'cpu',
              target: {
                type: 'Utilization',
                averageUtilization: 50,
              },
            },
          },
          {
            type: 'Resource',
            resource: {
              name: 'memory',
              target: {
                type: 'Utilization',
                averageUtilization: 70,
              },
            },
          },
        ],
        behavior: {
          scaleDown: {
            stabilizationWindowSeconds: 300,
            policies: [
              {
                type: 'Percent',
                value: 50,
                periodSeconds: 60,
              },
            ],
          },
          scaleUp: {
            stabilizationWindowSeconds: 60,
            policies: [
              {
                type: 'Percent',
                value: 100,
                periodSeconds: 60,
              },
            ],
          },
        },
      },
    });

    // Deploy memory-intensive demo application
    this.cluster.addManifest('MemoryDemoDeployment', {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: {
        name: 'memory-demo',
        namespace: 'demo-apps',
        labels: {
          app: 'memory-demo',
        },
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: {
            app: 'memory-demo',
          },
        },
        template: {
          metadata: {
            labels: {
              app: 'memory-demo',
            },
          },
          spec: {
            containers: [
              {
                name: 'memory-demo',
                image: 'nginx:1.21',
                ports: [
                  {
                    containerPort: 80,
                  },
                ],
                resources: {
                  requests: {
                    cpu: '50m',
                    memory: '256Mi',
                  },
                  limits: {
                    cpu: '200m',
                    memory: '512Mi',
                  },
                },
              },
            ],
            nodeSelector: {
              'workload-type': 'general',
            },
          },
        },
      },
    });

    this.cluster.addManifest('MemoryDemoService', {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: {
        name: 'memory-demo-service',
        namespace: 'demo-apps',
        labels: {
          app: 'memory-demo',
        },
      },
      spec: {
        selector: {
          app: 'memory-demo',
        },
        ports: [
          {
            port: 80,
            targetPort: 80,
          },
        ],
      },
    });

    this.cluster.addManifest('MemoryDemoHPA', {
      apiVersion: 'autoscaling/v2',
      kind: 'HorizontalPodAutoscaler',
      metadata: {
        name: 'memory-demo-hpa',
        namespace: 'demo-apps',
      },
      spec: {
        scaleTargetRef: {
          apiVersion: 'apps/v1',
          kind: 'Deployment',
          name: 'memory-demo',
        },
        minReplicas: 1,
        maxReplicas: 10,
        metrics: [
          {
            type: 'Resource',
            resource: {
              name: 'memory',
              target: {
                type: 'Utilization',
                averageUtilization: 80,
              },
            },
          },
        ],
        behavior: {
          scaleDown: {
            stabilizationWindowSeconds: 300,
          },
          scaleUp: {
            stabilizationWindowSeconds: 30,
          },
        },
      },
    });

    // Deploy Pod Disruption Budgets
    this.cluster.addManifest('CPUDemoPDB', {
      apiVersion: 'policy/v1',
      kind: 'PodDisruptionBudget',
      metadata: {
        name: 'cpu-demo-pdb',
        namespace: 'demo-apps',
      },
      spec: {
        minAvailable: 1,
        selector: {
          matchLabels: {
            app: 'cpu-demo',
          },
        },
      },
    });

    this.cluster.addManifest('MemoryDemoPDB', {
      apiVersion: 'policy/v1',
      kind: 'PodDisruptionBudget',
      metadata: {
        name: 'memory-demo-pdb',
        namespace: 'demo-apps',
      },
      spec: {
        minAvailable: 1,
        selector: {
          matchLabels: {
            app: 'memory-demo',
          },
        },
      },
    });

    // Deploy load testing application
    this.cluster.addManifest('LoadGeneratorDeployment', {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: {
        name: 'load-generator',
        namespace: 'demo-apps',
        labels: {
          app: 'load-generator',
        },
      },
      spec: {
        replicas: 1,
        selector: {
          matchLabels: {
            app: 'load-generator',
          },
        },
        template: {
          metadata: {
            labels: {
              app: 'load-generator',
            },
          },
          spec: {
            containers: [
              {
                name: 'load-generator',
                image: 'busybox:1.35',
                command: ['/bin/sh', '-c'],
                args: [
                  `while true; do
                    echo "Starting load test...";
                    for i in $(seq 1 100); do
                      wget -q -O- http://cpu-demo-service.demo-apps.svc.cluster.local/ &
                      wget -q -O- http://memory-demo-service.demo-apps.svc.cluster.local/ &
                    done;
                    wait;
                    echo "Load test completed, sleeping for 30 seconds...";
                    sleep 30;
                  done`,
                ],
                resources: {
                  requests: {
                    cpu: '50m',
                    memory: '64Mi',
                  },
                  limits: {
                    cpu: '200m',
                    memory: '128Mi',
                  },
                },
              },
            ],
            nodeSelector: {
              'workload-type': 'general',
            },
          },
        },
      },
    });

    // Output important information
    new cdk.CfnOutput(this, 'ClusterName', {
      value: this.cluster.clusterName,
      description: 'Name of the EKS cluster',
    });

    new cdk.CfnOutput(this, 'ClusterEndpoint', {
      value: this.cluster.clusterEndpoint,
      description: 'Endpoint of the EKS cluster',
    });

    new cdk.CfnOutput(this, 'ClusterArn', {
      value: this.cluster.clusterArn,
      description: 'ARN of the EKS cluster',
    });

    new cdk.CfnOutput(this, 'ClusterSecurityGroupId', {
      value: this.cluster.clusterSecurityGroupId,
      description: 'Security group ID of the EKS cluster',
    });

    new cdk.CfnOutput(this, 'VPCId', {
      value: this.vpc.vpcId,
      description: 'VPC ID where the EKS cluster is deployed',
    });

    new cdk.CfnOutput(this, 'UpdateKubeconfigCommand', {
      value: `aws eks update-kubeconfig --region ${this.region} --name ${this.cluster.clusterName}`,
      description: 'Command to update kubeconfig for the EKS cluster',
    });

    new cdk.CfnOutput(this, 'ClusterAutoscalerRoleArn', {
      value: clusterAutoscalerRole.roleArn,
      description: 'ARN of the IAM role for Cluster Autoscaler',
    });

    new cdk.CfnOutput(this, 'MonitoringCommands', {
      value: [
        'kubectl get nodes',
        'kubectl get pods -n kube-system',
        'kubectl get hpa -n demo-apps',
        'kubectl top nodes',
        'kubectl top pods -n demo-apps',
      ].join(' && '),
      description: 'Commands to monitor the cluster and applications',
    });
  }
}

// Create CDK app
const app = new cdk.App();

// Deploy the stack
new EKSAutoScalingStack(app, 'EKSAutoScalingStack', {
  description: 'EKS cluster with comprehensive auto-scaling capabilities including HPA, Cluster Autoscaler, and monitoring',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'EKS-AutoScaling',
    Environment: 'Demo',
    ManagedBy: 'CDK',
  },
});

// Synthesize the CloudFormation template
app.synth();