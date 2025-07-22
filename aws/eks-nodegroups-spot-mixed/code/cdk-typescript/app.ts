#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as eks from 'aws-cdk-lib/aws-eks';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';

/**
 * EKS Node Groups with Spot Instances and Mixed Instance Types Stack
 * 
 * This stack creates an EKS cluster with cost-optimized node groups using:
 * - Spot instances for fault-tolerant workloads (up to 90% cost savings)
 * - Mixed instance types for improved availability and capacity optimization
 * - On-Demand instances for critical workloads requiring guaranteed capacity
 * - Automated scaling, monitoring, and cost optimization features
 */
export class EksSpotNodeGroupsStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate a unique suffix for resource names
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // Create VPC for the EKS cluster
    const vpc = new ec2.Vpc(this, 'EksVpc', {
      maxAzs: 3,
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

    // Create IAM role for EKS cluster service
    const clusterRole = new iam.Role(this, 'EksClusterRole', {
      assumedBy: new iam.ServicePrincipal('eks.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEKSClusterPolicy'),
      ],
    });

    // Create IAM role for EKS node groups
    const nodeGroupRole = new iam.Role(this, 'EksNodeGroupRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEKSWorkerNodePolicy'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEKS_CNI_Policy'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEC2ContainerRegistryReadOnly'),
      ],
    });

    // Create EKS cluster
    const cluster = new eks.Cluster(this, 'EksCluster', {
      clusterName: `cost-optimized-eks-${uniqueSuffix}`,
      version: eks.KubernetesVersion.V1_28,
      vpc,
      role: clusterRole,
      defaultCapacity: 0, // We'll add our own node groups
      endpointAccess: eks.EndpointAccess.PUBLIC_AND_PRIVATE,
      vpcSubnets: [
        {
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
      ],
      // Enable logging for better observability
      clusterLogging: [
        eks.ClusterLoggingTypes.API,
        eks.ClusterLoggingTypes.AUDIT,
        eks.ClusterLoggingTypes.AUTHENTICATOR,
        eks.ClusterLoggingTypes.CONTROLLER_MANAGER,
        eks.ClusterLoggingTypes.SCHEDULER,
      ],
    });

    // Create Spot instance node group with mixed instance types
    const spotNodeGroup = cluster.addNodegroupCapacity('SpotNodeGroup', {
      nodegroupName: 'spot-mixed-nodegroup',
      instanceTypes: [
        ec2.InstanceType.of(ec2.InstanceClass.M5, ec2.InstanceSize.LARGE),
        ec2.InstanceType.of(ec2.InstanceClass.M5A, ec2.InstanceSize.LARGE),
        ec2.InstanceType.of(ec2.InstanceClass.C5, ec2.InstanceSize.LARGE),
        ec2.InstanceType.of(ec2.InstanceClass.C5A, ec2.InstanceSize.LARGE),
        ec2.InstanceType.of(ec2.InstanceClass.M5, ec2.InstanceSize.XLARGE),
        ec2.InstanceType.of(ec2.InstanceClass.C5, ec2.InstanceSize.XLARGE),
      ],
      capacityType: eks.CapacityType.SPOT,
      minSize: 2,
      maxSize: 10,
      desiredSize: 4,
      diskSize: 30,
      amiType: eks.NodegroupAmiType.AL2_X86_64,
      nodeRole: nodeGroupRole,
      subnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
      labels: {
        'node-type': 'spot',
        'cost-optimization': 'enabled',
      },
      tags: {
        Environment: 'production',
        NodeType: 'spot',
        CostOptimization: 'enabled',
      },
    });

    // Create On-Demand backup node group for critical workloads
    const onDemandNodeGroup = cluster.addNodegroupCapacity('OnDemandNodeGroup', {
      nodegroupName: 'ondemand-backup-nodegroup',
      instanceTypes: [
        ec2.InstanceType.of(ec2.InstanceClass.M5, ec2.InstanceSize.LARGE),
        ec2.InstanceType.of(ec2.InstanceClass.C5, ec2.InstanceSize.LARGE),
      ],
      capacityType: eks.CapacityType.ON_DEMAND,
      minSize: 1,
      maxSize: 3,
      desiredSize: 2,
      diskSize: 30,
      amiType: eks.NodegroupAmiType.AL2_X86_64,
      nodeRole: nodeGroupRole,
      subnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
      labels: {
        'node-type': 'on-demand',
        'workload-type': 'critical',
      },
      tags: {
        Environment: 'production',
        NodeType: 'on-demand',
        WorkloadType: 'critical',
      },
    });

    // Create IAM role for Cluster Autoscaler
    const clusterAutoscalerRole = new iam.Role(this, 'ClusterAutoscalerRole', {
      assumedBy: new iam.ServicePrincipal('pods.eks.amazonaws.com'),
      inlinePolicies: {
        ClusterAutoscalerPolicy: new iam.PolicyDocument({
          statements: [
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
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create service account for Cluster Autoscaler with IAM role
    const clusterAutoscalerServiceAccount = cluster.addServiceAccount('ClusterAutoscalerServiceAccount', {
      name: 'cluster-autoscaler',
      namespace: 'kube-system',
      role: clusterAutoscalerRole,
    });

    // Install AWS Node Termination Handler
    const nodeTerminationHandler = cluster.addHelmChart('NodeTerminationHandler', {
      chart: 'aws-node-termination-handler',
      repository: 'https://aws.github.io/eks-charts',
      namespace: 'kube-system',
      values: {
        enableSpotInterruptionDraining: true,
        enableRebalanceMonitoring: true,
        enableScheduledEventDraining: true,
        nodeSelector: {
          'node-type': 'spot',
        },
      },
    });

    // Install Cluster Autoscaler
    const clusterAutoscaler = cluster.addHelmChart('ClusterAutoscaler', {
      chart: 'cluster-autoscaler',
      repository: 'https://kubernetes.github.io/autoscaler',
      namespace: 'kube-system',
      values: {
        autoDiscovery: {
          clusterName: cluster.clusterName,
        },
        awsRegion: this.region,
        rbac: {
          serviceAccount: {
            create: false,
            name: clusterAutoscalerServiceAccount.serviceAccountName,
          },
        },
        extraArgs: {
          'v': 4,
          'stderrthreshold': 'info',
          'cloud-provider': 'aws',
          'skip-nodes-with-local-storage': false,
          'expander': 'least-waste',
          'node-group-auto-discovery': `asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/${cluster.clusterName}`,
        },
      },
    });

    // Create SNS topic for cost monitoring alerts
    const alertsTopic = new sns.Topic(this, 'EksAlertsTopic', {
      topicName: `eks-${cluster.clusterName}-alerts`,
      displayName: 'EKS Cost Optimization Alerts',
    });

    // Create CloudWatch log group for spot interruption monitoring
    const spotInterruptionLogGroup = new logs.LogGroup(this, 'SpotInterruptionLogGroup', {
      logGroupName: `/aws/eks/${cluster.clusterName}/spot-interruptions`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create CloudWatch alarm for high spot interruption rate
    const spotInterruptionAlarm = new cloudwatch.Alarm(this, 'SpotInterruptionAlarm', {
      alarmName: `EKS-${cluster.clusterName}-HighSpotInterruptions`,
      alarmDescription: 'High spot instance interruption rate detected',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/EKS',
        metricName: 'SpotInterruptionRate',
        dimensionsMap: {
          ClusterName: cluster.clusterName,
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 5,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Add SNS action to the alarm
    spotInterruptionAlarm.addAlarmAction(
      new cloudwatch.SnsAction(alertsTopic)
    );

    // Create Kubernetes manifests for spot workload management
    const spotWorkloadManifests = cluster.addManifest('SpotWorkloadManifests', {
      // Pod Disruption Budget for spot workloads
      apiVersion: 'policy/v1',
      kind: 'PodDisruptionBudget',
      metadata: {
        name: 'spot-workload-pdb',
        namespace: 'default',
      },
      spec: {
        minAvailable: 1,
        selector: {
          matchLabels: {
            'workload-type': 'spot-tolerant',
          },
        },
      },
    });

    // Demo application deployment for testing spot instances
    const demoApplication = cluster.addManifest('SpotDemoApplication', {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: {
        name: 'spot-demo-app',
        namespace: 'default',
      },
      spec: {
        replicas: 6,
        selector: {
          matchLabels: {
            app: 'spot-demo-app',
            'workload-type': 'spot-tolerant',
          },
        },
        template: {
          metadata: {
            labels: {
              app: 'spot-demo-app',
              'workload-type': 'spot-tolerant',
            },
          },
          spec: {
            tolerations: [
              {
                key: 'node-type',
                operator: 'Equal',
                value: 'spot',
                effect: 'NoSchedule',
              },
            ],
            nodeSelector: {
              'node-type': 'spot',
            },
            containers: [
              {
                name: 'nginx',
                image: 'nginx:latest',
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
                ports: [
                  {
                    containerPort: 80,
                  },
                ],
              },
            ],
          },
        },
      },
    });

    // Demo service for the application
    const demoService = cluster.addManifest('SpotDemoService', {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: {
        name: 'spot-demo-service',
        namespace: 'default',
      },
      spec: {
        selector: {
          app: 'spot-demo-app',
        },
        ports: [
          {
            protocol: 'TCP',
            port: 80,
            targetPort: 80,
          },
        ],
        type: 'ClusterIP',
      },
    });

    // Ensure dependencies are properly configured
    clusterAutoscaler.node.addDependency(clusterAutoscalerServiceAccount);
    demoApplication.node.addDependency(spotWorkloadManifests);
    demoService.node.addDependency(demoApplication);

    // Stack outputs for verification and integration
    new cdk.CfnOutput(this, 'ClusterName', {
      value: cluster.clusterName,
      description: 'EKS cluster name',
      exportName: `${this.stackName}-ClusterName`,
    });

    new cdk.CfnOutput(this, 'ClusterEndpoint', {
      value: cluster.clusterEndpoint,
      description: 'EKS cluster endpoint',
      exportName: `${this.stackName}-ClusterEndpoint`,
    });

    new cdk.CfnOutput(this, 'ClusterArn', {
      value: cluster.clusterArn,
      description: 'EKS cluster ARN',
      exportName: `${this.stackName}-ClusterArn`,
    });

    new cdk.CfnOutput(this, 'SpotNodeGroupName', {
      value: spotNodeGroup.nodegroupName,
      description: 'Spot instance node group name',
      exportName: `${this.stackName}-SpotNodeGroupName`,
    });

    new cdk.CfnOutput(this, 'OnDemandNodeGroupName', {
      value: onDemandNodeGroup.nodegroupName,
      description: 'On-Demand instance node group name',
      exportName: `${this.stackName}-OnDemandNodeGroupName`,
    });

    new cdk.CfnOutput(this, 'AlertsTopicArn', {
      value: alertsTopic.topicArn,
      description: 'SNS topic ARN for cost optimization alerts',
      exportName: `${this.stackName}-AlertsTopicArn`,
    });

    new cdk.CfnOutput(this, 'KubectlCommand', {
      value: `aws eks update-kubeconfig --region ${this.region} --name ${cluster.clusterName}`,
      description: 'Command to configure kubectl',
      exportName: `${this.stackName}-KubectlCommand`,
    });

    new cdk.CfnOutput(this, 'VpcId', {
      value: vpc.vpcId,
      description: 'VPC ID for the EKS cluster',
      exportName: `${this.stackName}-VpcId`,
    });
  }
}

// CDK App
const app = new cdk.App();

// Stack configuration
new EksSpotNodeGroupsStack(app, 'EksSpotNodeGroupsStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'EKS cluster with cost-optimized node groups using Spot instances and mixed instance types',
  tags: {
    Project: 'EKS-Cost-Optimization',
    Environment: 'production',
    ManagedBy: 'CDK',
  },
});

app.synth();