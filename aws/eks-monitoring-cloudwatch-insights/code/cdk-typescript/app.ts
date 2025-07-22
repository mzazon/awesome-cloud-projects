#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as eks from 'aws-cdk-lib/aws-eks';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as logs from 'aws-cdk-lib/aws-logs';
import { KubectlV29Layer } from '@aws-cdk/lambda-layer-kubectl-v29';

/**
 * CDK Stack for EKS CloudWatch Container Insights Monitoring
 * 
 * This stack creates:
 * - EKS cluster with Container Insights enabled
 * - CloudWatch alarms for CPU, memory, and failed pods
 * - SNS topic for alert notifications
 * - Necessary IAM roles and service accounts for monitoring
 */
export class EksCloudWatchContainerInsightsStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Get stack parameters from context or environment variables
    const clusterName = this.node.tryGetContext('clusterName') || process.env.CLUSTER_NAME || 'eks-monitoring-cluster';
    const alertEmail = this.node.tryGetContext('alertEmail') || process.env.ALERT_EMAIL;
    const vpcId = this.node.tryGetContext('vpcId');
    const createNewCluster = this.node.tryGetContext('createNewCluster') !== 'false';

    // Validate required parameters
    if (!alertEmail) {
      throw new Error('Alert email is required. Set ALERT_EMAIL environment variable or pass alertEmail in CDK context.');
    }

    // Create or import VPC
    let vpc: ec2.IVpc;
    if (vpcId) {
      // Import existing VPC
      vpc = ec2.Vpc.fromLookup(this, 'ImportedVpc', {
        vpcId: vpcId
      });
    } else {
      // Create new VPC for EKS cluster
      vpc = new ec2.Vpc(this, 'EksVpc', {
        maxAzs: 3,
        natGateways: 1,
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

      // Tag VPC for EKS cluster discovery
      cdk.Tags.of(vpc).add(`kubernetes.io/cluster/${clusterName}`, 'shared');
    }

    // Create SNS topic for monitoring alerts
    const alertTopic = new sns.Topic(this, 'EksMonitoringAlerts', {
      topicName: `eks-monitoring-alerts-${clusterName}`,
      displayName: 'EKS Monitoring Alerts',
    });

    // Subscribe email to SNS topic
    alertTopic.addSubscription(new snsSubscriptions.EmailSubscription(alertEmail));

    // Create EKS cluster or import existing one
    let cluster: eks.ICluster;
    
    if (createNewCluster) {
      // Create new EKS cluster with Container Insights enabled
      cluster = new eks.Cluster(this, 'EksCluster', {
        clusterName: clusterName,
        version: eks.KubernetesVersion.V1_29,
        vpc: vpc,
        vpcSubnets: [{ subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS }],
        defaultCapacity: 2,
        defaultCapacityInstance: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MEDIUM),
        kubectlLayer: new KubectlV29Layer(this, 'KubectlLayer'),
        clusterLogging: [
          eks.ClusterLoggingTypes.API,
          eks.ClusterLoggingTypes.AUDIT,
          eks.ClusterLoggingTypes.AUTHENTICATOR,
          eks.ClusterLoggingTypes.CONTROLLER_MANAGER,
          eks.ClusterLoggingTypes.SCHEDULER,
        ],
        outputClusterName: true,
        outputConfigCommand: true,
        endpointAccess: eks.EndpointAccess.PUBLIC_AND_PRIVATE,
      });

      // Enable Container Insights on the cluster
      cluster.addManifest('ContainerInsights', {
        apiVersion: 'v1',
        kind: 'ConfigMap',
        metadata: {
          name: 'cluster-info',
          namespace: 'amazon-cloudwatch',
        },
        data: {
          'cluster.name': clusterName,
          'logs.region': this.region,
        },
      });
    } else {
      // Import existing EKS cluster
      cluster = eks.Cluster.fromClusterAttributes(this, 'ImportedEksCluster', {
        clusterName: clusterName,
        kubectlRoleArn: this.node.tryGetContext('kubectlRoleArn'),
        vpc: vpc,
      });
    }

    // Create IAM role for CloudWatch agent with Container Insights permissions
    const cloudwatchAgentRole = new iam.Role(this, 'CloudWatchAgentRole', {
      roleName: `CloudWatchAgentServerRole-${clusterName}`,
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy'),
      ],
      inlinePolicies: {
        ContainerInsightsPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:PutLogEvents',
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:DescribeLogStreams',
                'logs:DescribeLogGroups',
                'cloudwatch:PutMetricData',
                'ec2:DescribeVolumes',
                'ec2:DescribeTags',
                'eks:DescribeCluster'
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create service account for CloudWatch agent with IRSA
    const cloudwatchServiceAccount = cluster.addServiceAccount('CloudWatchAgentServiceAccount', {
      name: 'cloudwatch-agent',
      namespace: 'amazon-cloudwatch',
    });

    // Attach CloudWatch permissions to the service account
    cloudwatchServiceAccount.role.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy')
    );

    // Create CloudWatch namespace
    const cloudwatchNamespace = cluster.addManifest('CloudWatchNamespace', {
      apiVersion: 'v1',
      kind: 'Namespace',
      metadata: {
        name: 'amazon-cloudwatch',
        labels: {
          name: 'amazon-cloudwatch',
        },
      },
    });

    // Create ConfigMap for CloudWatch agent configuration
    const cloudwatchConfigMap = cluster.addManifest('CloudWatchConfigMap', {
      apiVersion: 'v1',
      kind: 'ConfigMap',
      metadata: {
        name: 'cwagentconfig',
        namespace: 'amazon-cloudwatch',
      },
      data: {
        'cwagentconfig.json': JSON.stringify({
          logs: {
            metrics_collected: {
              kubernetes: {
                cluster_name: clusterName,
                metrics_collection_interval: 60,
              },
            },
            force_flush_interval: 5,
          },
        }),
      },
    });

    // Deploy CloudWatch agent DaemonSet
    const cloudwatchDaemonSet = cluster.addManifest('CloudWatchDaemonSet', {
      apiVersion: 'apps/v1',
      kind: 'DaemonSet',
      metadata: {
        name: 'cloudwatch-agent',
        namespace: 'amazon-cloudwatch',
      },
      spec: {
        selector: {
          matchLabels: {
            name: 'cloudwatch-agent',
          },
        },
        template: {
          metadata: {
            labels: {
              name: 'cloudwatch-agent',
            },
          },
          spec: {
            containers: [
              {
                name: 'cloudwatch-agent',
                image: 'amazon/cloudwatch-agent:1.300026.2b361',
                env: [
                  {
                    name: 'AWS_REGION',
                    value: this.region,
                  },
                  {
                    name: 'CLUSTER_NAME',
                    value: clusterName,
                  },
                ],
                resources: {
                  limits: {
                    cpu: '200m',
                    memory: '200Mi',
                  },
                  requests: {
                    cpu: '200m',
                    memory: '200Mi',
                  },
                },
                volumeMounts: [
                  {
                    name: 'cwagentconfig',
                    mountPath: '/etc/cwagentconfig',
                  },
                  {
                    name: 'rootfs',
                    mountPath: '/rootfs',
                    readOnly: true,
                  },
                  {
                    name: 'dockersock',
                    mountPath: '/var/run/docker.sock',
                    readOnly: true,
                  },
                  {
                    name: 'varlibdocker',
                    mountPath: '/var/lib/docker',
                    readOnly: true,
                  },
                  {
                    name: 'sys',
                    mountPath: '/sys',
                    readOnly: true,
                  },
                  {
                    name: 'devdisk',
                    mountPath: '/dev/disk',
                    readOnly: true,
                  },
                ],
              },
            ],
            volumes: [
              {
                name: 'cwagentconfig',
                configMap: {
                  name: 'cwagentconfig',
                },
              },
              {
                name: 'rootfs',
                hostPath: {
                  path: '/',
                },
              },
              {
                name: 'dockersock',
                hostPath: {
                  path: '/var/run/docker.sock',
                },
              },
              {
                name: 'varlibdocker',
                hostPath: {
                  path: '/var/lib/docker',
                },
              },
              {
                name: 'sys',
                hostPath: {
                  path: '/sys',
                },
              },
              {
                name: 'devdisk',
                hostPath: {
                  path: '/dev/disk/',
                },
              },
            ],
            terminationGracePeriodSeconds: 60,
            serviceAccountName: 'cloudwatch-agent',
          },
        },
      },
    });

    // Deploy Fluent Bit for log collection
    const fluentBitDaemonSet = cluster.addManifest('FluentBitDaemonSet', {
      apiVersion: 'apps/v1',
      kind: 'DaemonSet',
      metadata: {
        name: 'fluent-bit',
        namespace: 'amazon-cloudwatch',
        labels: {
          'k8s-app': 'fluent-bit',
        },
      },
      spec: {
        selector: {
          matchLabels: {
            'k8s-app': 'fluent-bit',
          },
        },
        template: {
          metadata: {
            labels: {
              'k8s-app': 'fluent-bit',
            },
          },
          spec: {
            containers: [
              {
                name: 'fluent-bit',
                image: 'amazon/aws-for-fluent-bit:stable',
                env: [
                  {
                    name: 'AWS_REGION',
                    value: this.region,
                  },
                  {
                    name: 'CLUSTER_NAME',
                    value: clusterName,
                  },
                  {
                    name: 'HTTP_SERVER',
                    value: 'On',
                  },
                  {
                    name: 'HTTP_PORT',
                    value: '2020',
                  },
                  {
                    name: 'READ_FROM_HEAD',
                    value: 'Off',
                  },
                  {
                    name: 'READ_FROM_TAIL',
                    value: 'On',
                  },
                ],
                resources: {
                  limits: {
                    memory: '200Mi',
                  },
                  requests: {
                    cpu: '10m',
                    memory: '200Mi',
                  },
                },
                volumeMounts: [
                  {
                    name: 'varlog',
                    mountPath: '/var/log',
                  },
                  {
                    name: 'varlibdockercontainers',
                    mountPath: '/var/lib/docker/containers',
                    readOnly: true,
                  },
                ],
              },
            ],
            terminationGracePeriodSeconds: 10,
            volumes: [
              {
                name: 'varlog',
                hostPath: {
                  path: '/var/log',
                },
              },
              {
                name: 'varlibdockercontainers',
                hostPath: {
                  path: '/var/lib/docker/containers',
                },
              },
            ],
            serviceAccountName: 'cloudwatch-agent',
          },
        },
      },
    });

    // Ensure proper deployment order
    cloudwatchConfigMap.node.addDependency(cloudwatchNamespace);
    cloudwatchDaemonSet.node.addDependency(cloudwatchConfigMap);
    fluentBitDaemonSet.node.addDependency(cloudwatchNamespace);

    // Create CloudWatch alarms for monitoring
    // High CPU utilization alarm
    const cpuAlarm = new cloudwatch.Alarm(this, 'HighCpuAlarm', {
      alarmName: `EKS-${clusterName}-HighCPU`,
      alarmDescription: 'EKS cluster high CPU utilization',
      metric: new cloudwatch.Metric({
        namespace: 'ContainerInsights',
        metricName: 'node_cpu_utilization',
        dimensionsMap: {
          ClusterName: clusterName,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 80,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // High memory utilization alarm
    const memoryAlarm = new cloudwatch.Alarm(this, 'HighMemoryAlarm', {
      alarmName: `EKS-${clusterName}-HighMemory`,
      alarmDescription: 'EKS cluster high memory utilization',
      metric: new cloudwatch.Metric({
        namespace: 'ContainerInsights',
        metricName: 'node_memory_utilization',
        dimensionsMap: {
          ClusterName: clusterName,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 85,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Failed pods alarm
    const failedPodsAlarm = new cloudwatch.Alarm(this, 'FailedPodsAlarm', {
      alarmName: `EKS-${clusterName}-FailedPods`,
      alarmDescription: 'EKS cluster has failed pods',
      metric: new cloudwatch.Metric({
        namespace: 'ContainerInsights',
        metricName: 'cluster_failed_node_count',
        dimensionsMap: {
          ClusterName: clusterName,
        },
        statistic: 'Maximum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Add SNS topic as alarm action for all alarms
    cpuAlarm.addAlarmAction(new cloudwatch.SnsAction(alertTopic));
    memoryAlarm.addAlarmAction(new cloudwatch.SnsAction(alertTopic));
    failedPodesAlarm.addAlarmAction(new cloudwatch.SnsAction(alertTopic));

    // Create CloudWatch log groups for application and platform logs
    const applicationLogGroup = new logs.LogGroup(this, 'ApplicationLogGroup', {
      logGroupName: `/aws/containerinsights/${clusterName}/application`,
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    const platformLogGroup = new logs.LogGroup(this, 'PlatformLogGroup', {
      logGroupName: `/aws/containerinsights/${clusterName}/platform`,
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Stack outputs
    new cdk.CfnOutput(this, 'ClusterName', {
      value: cluster.clusterName,
      description: 'EKS Cluster Name',
    });

    new cdk.CfnOutput(this, 'ClusterEndpoint', {
      value: cluster.clusterEndpoint,
      description: 'EKS Cluster Endpoint',
    });

    new cdk.CfnOutput(this, 'SnsTopicArn', {
      value: alertTopic.topicArn,
      description: 'SNS Topic ARN for monitoring alerts',
    });

    new cdk.CfnOutput(this, 'ApplicationLogGroupName', {
      value: applicationLogGroup.logGroupName,
      description: 'CloudWatch Log Group for application logs',
    });

    new cdk.CfnOutput(this, 'PlatformLogGroupName', {
      value: platformLogGroup.logGroupName,
      description: 'CloudWatch Log Group for platform logs',
    });

    // Kubectl commands output for manual verification
    new cdk.CfnOutput(this, 'KubectlCommands', {
      value: [
        `aws eks update-kubeconfig --region ${this.region} --name ${cluster.clusterName}`,
        'kubectl get pods -n amazon-cloudwatch',
        'kubectl get nodes',
      ].join(' && '),
      description: 'Commands to configure kubectl and verify deployment',
    });

    // CloudWatch Container Insights dashboard URL
    new cdk.CfnOutput(this, 'ContainerInsightsDashboard', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#container-insights:performance/EKS:Cluster?~(query~(~'*7b*22region*22*3a*22${this.region}*22*2c*22clusterName*22*3a*22${cluster.clusterName}*22*7d))`,
      description: 'CloudWatch Container Insights Dashboard URL',
    });
  }
}

// Create the CDK app
const app = new cdk.App();

// Create the stack
new EksCloudWatchContainerInsightsStack(app, 'EksCloudWatchContainerInsightsStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-west-2',
  },
  description: 'EKS CloudWatch Container Insights monitoring infrastructure',
  tags: {
    Project: 'eks-cloudwatch-container-insights',
    Environment: process.env.ENVIRONMENT || 'development',
    Recipe: 'eks-cloudwatch-container-insights',
  },
});

// Synthesize the CloudFormation template
app.synth();