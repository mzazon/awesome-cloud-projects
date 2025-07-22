#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import {
  aws_eks as eks,
  aws_ec2 as ec2,
  aws_iam as iam,
  aws_s3 as s3,
  aws_kinesis as kinesis,
  aws_emrcontainers as emr,
  aws_logs as logs,
  Duration,
  RemovalPolicy,
  Stack,
  StackProps,
  CfnOutput,
  Tags
} from 'aws-cdk-lib';

/**
 * Properties for the EMR Flink Analytics Stack
 */
interface EmrFlinkAnalyticsStackProps extends StackProps {
  readonly clusterName?: string;
  readonly emrNamespace?: string;
  readonly bucketName?: string;
  readonly tradingStreamName?: string;
  readonly marketStreamName?: string;
}

/**
 * CDK Stack for Real-Time Streaming Analytics with EMR on EKS and Apache Flink
 * 
 * This stack creates:
 * - EKS cluster with EMR-optimized configuration
 * - IAM roles for EMR on EKS service and job execution
 * - EMR virtual cluster
 * - S3 bucket for checkpoints and results
 * - Kinesis data streams for real-time data ingestion
 * - CloudWatch log groups for monitoring
 */
export class EmrFlinkAnalyticsStack extends Stack {
  public readonly cluster: eks.Cluster;
  public readonly virtualCluster: emr.CfnVirtualCluster;
  public readonly checkpointBucket: s3.Bucket;
  public readonly tradingStream: kinesis.Stream;
  public readonly marketStream: kinesis.Stream;

  constructor(scope: Construct, id: string, props: EmrFlinkAnalyticsStackProps = {}) {
    super(scope, id, props);

    // Generate unique suffix for resources
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();
    
    // Configuration variables
    const clusterName = props.clusterName || `emr-flink-analytics-${uniqueSuffix}`;
    const emrNamespace = props.emrNamespace || 'emr-flink';
    const bucketName = props.bucketName || `emr-flink-analytics-${uniqueSuffix}`;
    const tradingStreamName = props.tradingStreamName || `trading-events-${uniqueSuffix}`;
    const marketStreamName = props.marketStreamName || `market-data-${uniqueSuffix}`;

    // Create VPC for EKS cluster
    const vpc = new ec2.Vpc(this, 'EmrFlinkVpc', {
      maxAzs: 3,
      natGateways: 3,
      subnetConfiguration: [
        {
          name: 'public',
          subnetType: ec2.SubnetType.PUBLIC,
          cidrMask: 24,
        },
        {
          name: 'private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
          cidrMask: 24,
        },
      ],
    });

    // Create IAM role for EMR on EKS service
    const emrServiceRole = new iam.Role(this, 'EmrContainersServiceRole', {
      roleName: `EMRContainersServiceRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('emr-containers.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEMRContainersServiceRolePolicy'),
      ],
    });

    // Create EKS cluster with EMR-optimized configuration
    this.cluster = new eks.Cluster(this, 'EmrFlinkCluster', {
      clusterName: clusterName,
      version: eks.KubernetesVersion.V1_28,
      vpc: vpc,
      defaultCapacity: 0, // We'll add managed node groups separately
      endpointAccess: eks.EndpointAccess.PUBLIC_AND_PRIVATE,
      clusterLogging: [
        eks.ClusterLoggingTypes.API,
        eks.ClusterLoggingTypes.AUDIT,
        eks.ClusterLoggingTypes.AUTHENTICATOR,
        eks.ClusterLoggingTypes.CONTROLLER_MANAGER,
        eks.ClusterLoggingTypes.SCHEDULER,
      ],
    });

    // Add managed node group for EMR Flink workers
    const nodeGroup = this.cluster.addNodegroupCapacity('EmrFlinkWorkers', {
      nodegroupName: 'emr-flink-workers',
      instanceTypes: [ec2.InstanceType.of(ec2.InstanceClass.M5, ec2.InstanceSize.XLARGE)],
      minSize: 2,
      maxSize: 10,
      desiredSize: 4,
      diskSize: 100,
      subnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      tags: {
        Environment: 'analytics',
        Project: 'flink-streaming',
      },
    });

    // Create IAM role for Flink job execution with IRSA
    const flinkJobExecutionRole = new iam.Role(this, 'EmrFlinkJobExecutionRole', {
      roleName: `EMRFlinkJobExecutionRole-${uniqueSuffix}`,
      assumedBy: new iam.WebIdentityPrincipal(
        this.cluster.openIdConnectProvider.openIdConnectProviderArn,
        {
          StringLike: {
            [`${this.cluster.openIdConnectProvider.openIdConnectProviderIssuer}:sub`]: 
              `system:serviceaccount:${emrNamespace}:*`,
          },
        }
      ),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonS3FullAccess'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonKinesisFullAccess'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchFullAccess'),
      ],
    });

    // Create Kubernetes namespace for EMR
    const emrNamespaceManifest = this.cluster.addManifest('EmrNamespace', {
      apiVersion: 'v1',
      kind: 'Namespace',
      metadata: {
        name: emrNamespace,
        labels: {
          'emr-containers': 'enabled',
        },
      },
    });

    // Create service account for Flink operator
    const flinkServiceAccount = this.cluster.addServiceAccount('FlinkOperatorServiceAccount', {
      name: 'emr-containers-sa-flink-operator',
      namespace: emrNamespace,
      annotations: {
        'eks.amazonaws.com/role-arn': flinkJobExecutionRole.roleArn,
      },
    });
    flinkServiceAccount.node.addDependency(emrNamespaceManifest);

    // Enable EMR on EKS access to the namespace
    this.cluster.awsAuth.addRoleMapping(emrServiceRole, {
      groups: ['system:masters'],
    });

    // Create EMR virtual cluster
    this.virtualCluster = new emr.CfnVirtualCluster(this, 'FlinkAnalyticsVirtualCluster', {
      name: 'flink-analytics-cluster',
      containerProvider: {
        id: this.cluster.clusterName,
        type: 'EKS',
        info: {
          eksInfo: {
            namespace: emrNamespace,
          },
        },
      },
      tags: [
        {
          key: 'Environment',
          value: 'analytics',
        },
        {
          key: 'Project',
          value: 'flink-streaming',
        },
      ],
    });
    this.virtualCluster.node.addDependency(emrNamespaceManifest);

    // Create S3 bucket for checkpoints and results
    this.checkpointBucket = new s3.Bucket(this, 'FlinkCheckpointBucket', {
      bucketName: bucketName,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: RemovalPolicy.DESTROY, // For demo purposes - use RETAIN in production
      autoDeleteObjects: true, // For demo purposes - remove in production
      lifecycleRules: [
        {
          id: 'FlinkCheckpointLifecycle',
          enabled: true,
          prefix: 'checkpoints/',
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: Duration.days(90),
            },
          ],
        },
      ],
    });

    // Create Kinesis data streams for real-time data ingestion
    this.tradingStream = new kinesis.Stream(this, 'TradingEventsStream', {
      streamName: tradingStreamName,
      shardCount: 4,
      encryption: kinesis.StreamEncryption.MANAGED,
      retentionPeriod: Duration.days(7),
    });

    this.marketStream = new kinesis.Stream(this, 'MarketDataStream', {
      streamName: marketStreamName,
      shardCount: 2,
      encryption: kinesis.StreamEncryption.MANAGED,
      retentionPeriod: Duration.days(7),
    });

    // Create CloudWatch log group for EMR containers
    const emrLogGroup = new logs.LogGroup(this, 'EmrContainersLogGroup', {
      logGroupName: '/aws/emr-containers/flink',
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    // Install Flink Kubernetes operator using Helm
    const flinkOperatorChart = this.cluster.addHelmChart('FlinkKubernetesOperator', {
      chart: 'flink-kubernetes-operator',
      repository: 'https://downloads.apache.org/flink/flink-kubernetes-operator-1.7.0/',
      namespace: emrNamespace,
      release: 'flink-kubernetes-operator',
      version: '1.7.0',
      values: {
        image: {
          repository: 'public.ecr.aws/emr-on-eks/flink/flink-kubernetes-operator',
          tag: '1.7.0-emr-7.0.0',
        },
        serviceAccount: {
          create: false,
          name: 'emr-containers-sa-flink-operator',
        },
      },
      wait: true,
      timeout: Duration.minutes(15),
    });
    flinkOperatorChart.node.addDependency(flinkServiceAccount);

    // Add monitoring with Prometheus (optional)
    const prometheusChart = this.cluster.addHelmChart('PrometheusStack', {
      chart: 'kube-prometheus-stack',
      repository: 'https://prometheus-community.github.io/helm-charts',
      namespace: 'monitoring',
      createNamespace: true,
      release: 'prometheus',
      values: {
        prometheus: {
          prometheusSpec: {
            serviceMonitorSelectorNilUsesHelmValues: false,
            podMonitorSelectorNilUsesHelmValues: false,
          },
        },
        grafana: {
          adminPassword: 'flink-analytics',
          service: {
            type: 'LoadBalancer',
          },
        },
      },
      wait: true,
      timeout: Duration.minutes(15),
    });

    // Apply tags to all resources
    Tags.of(this).add('Project', 'EmrFlinkAnalytics');
    Tags.of(this).add('Environment', 'Development');
    Tags.of(this).add('ManagedBy', 'CDK');

    // Outputs
    new CfnOutput(this, 'ClusterName', {
      value: this.cluster.clusterName,
      description: 'EKS Cluster Name',
    });

    new CfnOutput(this, 'VirtualClusterId', {
      value: this.virtualCluster.attrId,
      description: 'EMR Virtual Cluster ID',
    });

    new CfnOutput(this, 'CheckpointBucketName', {
      value: this.checkpointBucket.bucketName,
      description: 'S3 Bucket for Flink checkpoints',
    });

    new CfnOutput(this, 'TradingStreamName', {
      value: this.tradingStream.streamName,
      description: 'Kinesis Stream for trading events',
    });

    new CfnOutput(this, 'MarketStreamName', {
      value: this.marketStream.streamName,
      description: 'Kinesis Stream for market data',
    });

    new CfnOutput(this, 'FlinkJobExecutionRoleArn', {
      value: flinkJobExecutionRole.roleArn,
      description: 'IAM Role ARN for Flink job execution',
    });

    new CfnOutput(this, 'ClusterEndpoint', {
      value: this.cluster.clusterEndpoint,
      description: 'EKS Cluster Endpoint',
    });

    new CfnOutput(this, 'KubectlConfigCommand', {
      value: `aws eks update-kubeconfig --name ${this.cluster.clusterName} --region ${this.region}`,
      description: 'Command to configure kubectl',
    });
  }
}

// CDK App
const app = new cdk.App();

// Create the main stack
new EmrFlinkAnalyticsStack(app, 'EmrFlinkAnalyticsStack', {
  description: 'Real-Time Streaming Analytics with EMR on EKS and Apache Flink',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

app.synth();