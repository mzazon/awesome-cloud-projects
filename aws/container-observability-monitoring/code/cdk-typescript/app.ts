#!/usr/bin/env node
/**
 * Container Observability and Performance Monitoring CDK Application
 * 
 * This CDK application implements a comprehensive container observability platform
 * combining CloudWatch Container Insights, AWS X-Ray distributed tracing, 
 * Prometheus metrics collection, and custom performance monitoring dashboards.
 * 
 * Features:
 * - EKS cluster with enhanced monitoring
 * - ECS cluster with Container Insights
 * - CloudWatch alarms and anomaly detection
 * - OpenSearch domain for log analytics
 * - Performance optimization Lambda functions
 * - Custom CloudWatch dashboards
 * - SNS notifications for alerts
 */

import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as eks from 'aws-cdk-lib/aws-eks';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as opensearch from 'aws-cdk-lib/aws-opensearchserverless';
import * as kinesisfirehose from 'aws-cdk-lib/aws-kinesisfirehose';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as xray from 'aws-cdk-lib/aws-xray';
import { KubectlV29Layer } from '@aws-cdk/lambda-layer-kubectl-v29';

/**
 * Properties for the Container Observability Stack
 */
export interface ContainerObservabilityStackProps extends cdk.StackProps {
  /**
   * Environment identifier for resource naming
   */
  readonly environmentId?: string;
  
  /**
   * EKS cluster version
   */
  readonly eksVersion?: eks.KubernetesVersion;
  
  /**
   * Instance type for EKS nodes
   */
  readonly nodeInstanceType?: ec2.InstanceType;
  
  /**
   * Enable enhanced monitoring features
   */
  readonly enableEnhancedMonitoring?: boolean;
  
  /**
   * Email address for alert notifications
   */
  readonly alertEmail?: string;
}

/**
 * CDK Stack for Container Observability and Performance Monitoring
 */
export class ContainerObservabilityStack extends cdk.Stack {
  public readonly vpc: ec2.Vpc;
  public readonly eksCluster: eks.Cluster;
  public readonly ecsCluster: ecs.Cluster;
  public readonly alertTopic: sns.Topic;
  public readonly openSearchDomain: opensearch.CfnCollection;
  public readonly performanceOptimizerFunction: lambda.Function;
  public readonly dashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: ContainerObservabilityStackProps = {}) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = cdk.Names.uniqueId(this).toLowerCase().substring(0, 8);
    const environmentId = props.environmentId || uniqueSuffix;

    // Create VPC for container infrastructure
    this.vpc = this.createVpc();

    // Create SNS topic for alerts
    this.alertTopic = this.createAlertTopic(environmentId, props.alertEmail);

    // Create CloudWatch log groups
    this.createLogGroups(environmentId);

    // Create EKS cluster with enhanced monitoring
    this.eksCluster = this.createEksCluster(environmentId, props);

    // Create ECS cluster with Container Insights
    this.ecsCluster = this.createEcsCluster(environmentId);

    // Create OpenSearch domain for log analytics
    this.openSearchDomain = this.createOpenSearchDomain(environmentId);

    // Create performance optimization Lambda function
    this.performanceOptimizerFunction = this.createPerformanceOptimizerFunction(environmentId);

    // Create CloudWatch alarms and anomaly detection
    this.createCloudWatchAlarms(environmentId);

    // Create custom CloudWatch dashboard
    this.dashboard = this.createCustomDashboard(environmentId);

    // Create X-Ray tracing configuration
    this.createXRayTracing();

    // Output important information
    this.createOutputs(environmentId);
  }

  /**
   * Create VPC for container infrastructure
   */
  private createVpc(): ec2.Vpc {
    return new ec2.Vpc(this, 'ContainerVpc', {
      maxAzs: 3,
      natGateways: 2,
      enableDnsHostnames: true,
      enableDnsSupport: true,
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
  }

  /**
   * Create SNS topic for alerts
   */
  private createAlertTopic(environmentId: string, alertEmail?: string): sns.Topic {
    const topic = new sns.Topic(this, 'AlertTopic', {
      topicName: `container-observability-alerts-${environmentId}`,
      displayName: 'Container Observability Alerts',
    });

    // Subscribe email if provided
    if (alertEmail) {
      topic.addSubscription(new sns.EmailSubscription(alertEmail));
    }

    return topic;
  }

  /**
   * Create CloudWatch log groups
   */
  private createLogGroups(environmentId: string): void {
    // EKS application logs
    new logs.LogGroup(this, 'EksApplicationLogs', {
      logGroupName: `/aws/eks/observability-eks-${environmentId}/application`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // ECS application logs  
    new logs.LogGroup(this, 'EcsApplicationLogs', {
      logGroupName: `/aws/ecs/observability-ecs-${environmentId}/application`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Container Insights logs
    new logs.LogGroup(this, 'ContainerInsightsLogs', {
      logGroupName: `/aws/containerinsights/observability-eks-${environmentId}/application`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });
  }

  /**
   * Create EKS cluster with enhanced monitoring
   */
  private createEksCluster(environmentId: string, props: ContainerObservabilityStackProps): eks.Cluster {
    // Create IAM role for EKS cluster
    const eksClusterRole = new iam.Role(this, 'EksClusterRole', {
      assumedBy: new iam.ServicePrincipal('eks.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEKSClusterPolicy'),
      ],
    });

    // Create IAM role for EKS node group
    const eksNodeRole = new iam.Role(this, 'EksNodeRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEKSWorkerNodePolicy'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEKS_CNI_Policy'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEC2ContainerRegistryReadOnly'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSXRayDaemonWriteAccess'),
      ],
    });

    // Create EKS cluster
    const cluster = new eks.Cluster(this, 'EksCluster', {
      clusterName: `observability-eks-${environmentId}`,
      version: props.eksVersion || eks.KubernetesVersion.V1_29,
      role: eksClusterRole,
      vpc: this.vpc,
      defaultCapacity: 0, // We'll add managed node group separately
      endpointAccess: eks.EndpointAccess.PUBLIC_AND_PRIVATE,
      clusterLogging: [
        eks.ClusterLoggingTypes.API,
        eks.ClusterLoggingTypes.AUDIT,
        eks.ClusterLoggingTypes.AUTHENTICATOR,
        eks.ClusterLoggingTypes.CONTROLLER_MANAGER,
        eks.ClusterLoggingTypes.SCHEDULER,
      ],
      kubectlLayer: new KubectlV29Layer(this, 'KubectlLayer'),
    });

    // Add managed node group
    cluster.addNodegroupCapacity('ObservabilityNodes', {
      instanceTypes: [props.nodeInstanceType || ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.LARGE)],
      minSize: 3,
      maxSize: 6,
      desiredSize: 3,
      diskSize: 50,
      nodeRole: eksNodeRole,
      subnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
      labels: {
        role: 'observability',
      },
      tags: {
        Environment: 'observability',
        Monitoring: 'enabled',
      },
    });

    // Create service accounts for monitoring
    cluster.addServiceAccount('CloudWatchAgentServiceAccount', {
      name: 'cloudwatch-agent',
      namespace: 'amazon-cloudwatch',
    });

    cluster.addServiceAccount('FluentBitServiceAccount', {
      name: 'fluent-bit',
      namespace: 'amazon-cloudwatch',
    });

    cluster.addServiceAccount('AdotCollectorServiceAccount', {
      name: 'adot-collector',
      namespace: 'monitoring',
    });

    // Install Container Insights using Helm
    cluster.addHelmChart('ContainerInsights', {
      chart: 'aws-cloudwatch-metrics',
      repository: 'https://aws.github.io/eks-charts',
      namespace: 'amazon-cloudwatch',
      createNamespace: true,
      values: {
        clusterName: cluster.clusterName,
        region: this.region,
        fluentBit: {
          enabled: true,
        },
        cloudWatchAgent: {
          enabled: true,
        },
      },
    });

    // Install Prometheus using Helm
    cluster.addHelmChart('Prometheus', {
      chart: 'kube-prometheus-stack',
      repository: 'https://prometheus-community.github.io/helm-charts',
      namespace: 'monitoring',
      createNamespace: true,
      values: {
        prometheus: {
          prometheusSpec: {
            retention: '30d',
            storageSpec: {
              volumeClaimTemplate: {
                spec: {
                  storageClassName: 'gp2',
                  accessModes: ['ReadWriteOnce'],
                  resources: {
                    requests: {
                      storage: '50Gi',
                    },
                  },
                },
              },
            },
          },
        },
        grafana: {
          enabled: true,
          adminPassword: 'observability123!',
          service: {
            type: 'LoadBalancer',
          },
          additionalDataSources: [
            {
              name: 'CloudWatch',
              type: 'cloudwatch',
              jsonData: {
                authType: 'arn',
                defaultRegion: this.region,
              },
            },
          ],
        },
      },
    });

    return cluster;
  }

  /**
   * Create ECS cluster with Container Insights
   */
  private createEcsCluster(environmentId: string): ecs.Cluster {
    const cluster = new ecs.Cluster(this, 'EcsCluster', {
      clusterName: `observability-ecs-${environmentId}`,
      vpc: this.vpc,
      containerInsights: true,
      capacityProviders: ['FARGATE', 'FARGATE_SPOT'],
      defaultCloudMapNamespace: {
        name: 'observability',
      },
    });

    // Create task execution role
    const taskExecutionRole = new iam.Role(this, 'EcsTaskExecutionRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonECSTaskExecutionRolePolicy'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchLogsFullAccess'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSXRayDaemonWriteAccess'),
      ],
    });

    // Create sample task definition with observability
    const taskDefinition = new ecs.FargateTaskDefinition(this, 'ObservabilityDemoTask', {
      family: 'observability-demo-task',
      cpu: 512,
      memoryLimitMiB: 1024,
      executionRole: taskExecutionRole,
      taskRole: taskExecutionRole,
    });

    // Add main application container
    const appContainer = taskDefinition.addContainer('app', {
      image: ecs.ContainerImage.fromRegistry('nginx:latest'),
      essential: true,
      portMappings: [
        {
          containerPort: 80,
          protocol: ecs.Protocol.TCP,
        },
      ],
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: 'app',
        logGroup: new logs.LogGroup(this, 'EcsTaskLogs', {
          logGroupName: `/aws/ecs/observability-ecs-${environmentId}/task`,
          retention: logs.RetentionDays.ONE_MONTH,
          removalPolicy: cdk.RemovalPolicy.DESTROY,
        }),
      }),
      environment: {
        AWS_XRAY_TRACING_NAME: 'ecs-observability-demo',
      },
    });

    // Add ADOT collector sidecar
    taskDefinition.addContainer('aws-otel-collector', {
      image: ecs.ContainerImage.fromRegistry('public.ecr.aws/aws-observability/aws-otel-collector:latest'),
      essential: false,
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: 'otel-collector',
        logGroup: new logs.LogGroup(this, 'AdotCollectorLogs', {
          logGroupName: `/aws/ecs/observability-ecs-${environmentId}/adot`,
          retention: logs.RetentionDays.ONE_MONTH,
          removalPolicy: cdk.RemovalPolicy.DESTROY,
        }),
      }),
      environment: {
        AWS_REGION: this.region,
      },
    });

    // Create ECS service
    const service = new ecs.FargateService(this, 'ObservabilityDemoService', {
      cluster,
      taskDefinition,
      serviceName: 'observability-demo-service',
      desiredCount: 2,
      assignPublicIp: true,
      enableLogging: true,
      enableExecuteCommand: true,
    });

    return cluster;
  }

  /**
   * Create OpenSearch domain for log analytics
   */
  private createOpenSearchDomain(environmentId: string): opensearch.CfnCollection {
    // Create OpenSearch Serverless collection
    const collection = new opensearch.CfnCollection(this, 'OpenSearchCollection', {
      name: `container-logs-${environmentId}`,
      description: 'Container logs collection for observability',
      type: 'TIMESERIES',
      tags: [
        {
          key: 'Environment',
          value: 'observability',
        },
        {
          key: 'Purpose',
          value: 'log-analytics',
        },
      ],
    });

    // Create S3 bucket for log backup
    const logBackupBucket = new s3.Bucket(this, 'LogBackupBucket', {
      bucketName: `container-logs-backup-${environmentId}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: 'DeleteOldLogs',
          expiration: cdk.Duration.days(90),
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(60),
            },
          ],
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create IAM role for Kinesis Data Firehose
    const firehoseRole = new iam.Role(this, 'FirehoseRole', {
      assumedBy: new iam.ServicePrincipal('firehose.amazonaws.com'),
      inlinePolicies: {
        FirehosePolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:AbortMultipartUpload',
                's3:GetBucketLocation',
                's3:GetObject',
                's3:ListBucket',
                's3:ListBucketMultipartUploads',
                's3:PutObject',
              ],
              resources: [
                logBackupBucket.bucketArn,
                `${logBackupBucket.bucketArn}/*`,
              ],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'es:DescribeElasticsearchDomain',
                'es:DescribeElasticsearchDomains',
                'es:DescribeElasticsearchDomainConfig',
                'es:ESHttpPost',
                'es:ESHttpPut',
              ],
              resources: [
                collection.attrArn,
              ],
            }),
          ],
        }),
      },
    });

    return collection;
  }

  /**
   * Create performance optimization Lambda function
   */
  private createPerformanceOptimizerFunction(environmentId: string): lambda.Function {
    const performanceOptimizerFunction = new lambda.Function(this, 'PerformanceOptimizerFunction', {
      functionName: `container-performance-optimizer-${environmentId}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'performance_optimizer.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
from datetime import datetime, timedelta

def lambda_handler(event, context):
    cloudwatch = boto3.client('cloudwatch')
    
    # Get performance metrics for the last hour
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(hours=1)
    
    cluster_name = '${this.eksCluster.clusterName}'
    
    try:
        # Get CPU utilization metrics
        cpu_metrics = cloudwatch.get_metric_statistics(
            Namespace='AWS/ContainerInsights',
            MetricName='pod_cpu_utilization',
            Dimensions=[
                {'Name': 'ClusterName', 'Value': cluster_name}
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Average', 'Maximum']
        )
        
        recommendations = []
        
        # Analyze CPU utilization
        if cpu_metrics['Datapoints']:
            avg_cpu = sum(point['Average'] for point in cpu_metrics['Datapoints']) / len(cpu_metrics['Datapoints'])
            max_cpu = max(point['Maximum'] for point in cpu_metrics['Datapoints'])
            
            if avg_cpu < 20:
                recommendations.append({
                    'type': 'DOWNSIZE_CPU',
                    'message': f'Average CPU utilization is {avg_cpu:.1f}%. Consider reducing CPU requests.',
                    'severity': 'MEDIUM'
                })
            elif max_cpu > 90:
                recommendations.append({
                    'type': 'UPSIZE_CPU',
                    'message': f'Maximum CPU utilization reached {max_cpu:.1f}%. Consider increasing CPU limits.',
                    'severity': 'HIGH'
                })
        
        # Return optimization recommendations
        return {
            'statusCode': 200,
            'body': json.dumps({
                'recommendations': recommendations,
                'timestamp': datetime.utcnow().isoformat(),
                'cluster': cluster_name
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }
      `),
      timeout: cdk.Duration.seconds(60),
      environment: {
        EKS_CLUSTER_NAME: this.eksCluster.clusterName,
        ECS_CLUSTER_NAME: this.ecsCluster.clusterName,
      },
    });

    // Grant permissions to read CloudWatch metrics
    performanceOptimizerFunction.addToRolePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'cloudwatch:GetMetricStatistics',
          'cloudwatch:ListMetrics',
        ],
        resources: ['*'],
      })
    );

    // Create EventBridge rule to trigger optimization analysis
    const optimizationRule = new events.Rule(this, 'OptimizationRule', {
      ruleName: `container-performance-analysis-${environmentId}`,
      description: 'Trigger container performance optimization analysis',
      schedule: events.Schedule.rate(cdk.Duration.hours(1)),
    });

    optimizationRule.addTarget(new targets.LambdaFunction(performanceOptimizerFunction));

    return performanceOptimizerFunction;
  }

  /**
   * Create CloudWatch alarms and anomaly detection
   */
  private createCloudWatchAlarms(environmentId: string): void {
    // EKS High CPU Utilization Alarm
    const eksHighCpuAlarm = new cloudwatch.Alarm(this, 'EksHighCpuAlarm', {
      alarmName: `EKS-High-CPU-Utilization-${environmentId}`,
      alarmDescription: 'High CPU utilization in EKS cluster',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ContainerInsights',
        metricName: 'pod_cpu_utilization',
        dimensionsMap: {
          ClusterName: this.eksCluster.clusterName,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 80,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
    });

    eksHighCpuAlarm.addAlarmAction(new cloudwatch.SnsAction(this.alertTopic));
    eksHighCpuAlarm.addOkAction(new cloudwatch.SnsAction(this.alertTopic));

    // EKS High Memory Utilization Alarm
    const eksHighMemoryAlarm = new cloudwatch.Alarm(this, 'EksHighMemoryAlarm', {
      alarmName: `EKS-High-Memory-Utilization-${environmentId}`,
      alarmDescription: 'High memory utilization in EKS cluster',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ContainerInsights',
        metricName: 'pod_memory_utilization',
        dimensionsMap: {
          ClusterName: this.eksCluster.clusterName,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 80,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
    });

    eksHighMemoryAlarm.addAlarmAction(new cloudwatch.SnsAction(this.alertTopic));

    // ECS Service Unhealthy Tasks Alarm
    const ecsUnhealthyTasksAlarm = new cloudwatch.Alarm(this, 'EcsUnhealthyTasksAlarm', {
      alarmName: `ECS-Service-Unhealthy-Tasks-${environmentId}`,
      alarmDescription: 'Unhealthy tasks in ECS service',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ECS',
        metricName: 'RunningTaskCount',
        dimensionsMap: {
          ClusterName: this.ecsCluster.clusterName,
          ServiceName: 'observability-demo-service',
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
    });

    ecsUnhealthyTasksAlarm.addAlarmAction(new cloudwatch.SnsAction(this.alertTopic));

    // Create anomaly detectors
    new cloudwatch.CfnAnomalyDetector(this, 'EksCpuAnomalyDetector', {
      namespace: 'AWS/ContainerInsights',
      metricName: 'pod_cpu_utilization',
      stat: 'Average',
      dimensions: [
        {
          name: 'ClusterName',
          value: this.eksCluster.clusterName,
        },
      ],
    });

    new cloudwatch.CfnAnomalyDetector(this, 'EksMemoryAnomalyDetector', {
      namespace: 'AWS/ContainerInsights',
      metricName: 'pod_memory_utilization',
      stat: 'Average',
      dimensions: [
        {
          name: 'ClusterName',
          value: this.eksCluster.clusterName,
        },
      ],
    });
  }

  /**
   * Create custom CloudWatch dashboard
   */
  private createCustomDashboard(environmentId: string): cloudwatch.Dashboard {
    const dashboard = new cloudwatch.Dashboard(this, 'ObservabilityDashboard', {
      dashboardName: `Container-Observability-${environmentId}`,
      defaultInterval: cdk.Duration.minutes(5),
    });

    // EKS Pod Resource Utilization widget
    const eksPodResourceWidget = new cloudwatch.GraphWidget({
      title: 'EKS Pod Resource Utilization',
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/ContainerInsights',
          metricName: 'pod_cpu_utilization',
          dimensionsMap: {
            ClusterName: this.eksCluster.clusterName,
          },
          label: 'CPU Utilization',
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/ContainerInsights',
          metricName: 'pod_memory_utilization',
          dimensionsMap: {
            ClusterName: this.eksCluster.clusterName,
          },
          label: 'Memory Utilization',
        }),
      ],
      width: 12,
      height: 6,
      leftYAxis: {
        min: 0,
        max: 100,
      },
    });

    // ECS Service Resource Utilization widget
    const ecsServiceResourceWidget = new cloudwatch.GraphWidget({
      title: 'ECS Service Resource Utilization',
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/ECS',
          metricName: 'CPUUtilization',
          dimensionsMap: {
            ClusterName: this.ecsCluster.clusterName,
            ServiceName: 'observability-demo-service',
          },
          label: 'CPU Utilization',
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/ECS',
          metricName: 'MemoryUtilization',
          dimensionsMap: {
            ClusterName: this.ecsCluster.clusterName,
            ServiceName: 'observability-demo-service',
          },
          label: 'Memory Utilization',
        }),
      ],
      width: 12,
      height: 6,
    });

    // EKS Network I/O widget
    const eksNetworkWidget = new cloudwatch.GraphWidget({
      title: 'EKS Network I/O',
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/ContainerInsights',
          metricName: 'pod_network_rx_bytes',
          dimensionsMap: {
            ClusterName: this.eksCluster.clusterName,
          },
          label: 'Network RX Bytes',
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/ContainerInsights',
          metricName: 'pod_network_tx_bytes',
          dimensionsMap: {
            ClusterName: this.eksCluster.clusterName,
          },
          label: 'Network TX Bytes',
        }),
      ],
      width: 12,
      height: 6,
    });

    // ECS Task Counts widget
    const ecsTaskCountWidget = new cloudwatch.GraphWidget({
      title: 'ECS Task Counts',
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/ECS',
          metricName: 'RunningTaskCount',
          dimensionsMap: {
            ClusterName: this.ecsCluster.clusterName,
            ServiceName: 'observability-demo-service',
          },
          label: 'Running Tasks',
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/ECS',
          metricName: 'PendingTaskCount',
          dimensionsMap: {
            ClusterName: this.ecsCluster.clusterName,
            ServiceName: 'observability-demo-service',
          },
          label: 'Pending Tasks',
        }),
      ],
      width: 12,
      height: 6,
    });

    // Add widgets to dashboard
    dashboard.addWidgets(
      eksPodResourceWidget,
      ecsServiceResourceWidget,
      eksNetworkWidget,
      ecsTaskCountWidget
    );

    return dashboard;
  }

  /**
   * Create X-Ray tracing configuration
   */
  private createXRayTracing(): void {
    // X-Ray tracing is enabled through environment variables and IAM permissions
    // in the EKS and ECS configurations above
    
    // Create X-Ray sampling rule for container applications
    new xray.CfnSamplingRule(this, 'ContainerSamplingRule', {
      samplingRule: {
        ruleName: 'ContainerObservabilitySampling',
        priority: 10000,
        fixedRate: 0.1,
        reservoirSize: 1,
        serviceName: '*',
        serviceType: '*',
        host: '*',
        httpMethod: '*',
        urlPath: '*',
        version: 1,
      },
    });
  }

  /**
   * Create CloudFormation outputs
   */
  private createOutputs(environmentId: string): void {
    new cdk.CfnOutput(this, 'EksClusterName', {
      value: this.eksCluster.clusterName,
      description: 'EKS Cluster Name',
      exportName: `${this.stackName}-EksClusterName`,
    });

    new cdk.CfnOutput(this, 'EcsClusterName', {
      value: this.ecsCluster.clusterName,
      description: 'ECS Cluster Name',
      exportName: `${this.stackName}-EcsClusterName`,
    });

    new cdk.CfnOutput(this, 'AlertTopicArn', {
      value: this.alertTopic.topicArn,
      description: 'SNS Topic ARN for Alerts',
      exportName: `${this.stackName}-AlertTopicArn`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      description: 'CloudWatch Dashboard URL',
      exportName: `${this.stackName}-DashboardUrl`,
    });

    new cdk.CfnOutput(this, 'PerformanceOptimizerFunctionName', {
      value: this.performanceOptimizerFunction.functionName,
      description: 'Performance Optimizer Lambda Function Name',
      exportName: `${this.stackName}-PerformanceOptimizerFunctionName`,
    });

    new cdk.CfnOutput(this, 'EksClusterConfigCommand', {
      value: `aws eks update-kubeconfig --region ${this.region} --name ${this.eksCluster.clusterName}`,
      description: 'Command to configure kubectl for EKS cluster',
      exportName: `${this.stackName}-EksClusterConfigCommand`,
    });
  }
}

/**
 * CDK App
 */
const app = new cdk.App();

// Get configuration from context or environment
const environmentId = app.node.tryGetContext('environmentId') || process.env.ENVIRONMENT_ID;
const alertEmail = app.node.tryGetContext('alertEmail') || process.env.ALERT_EMAIL;
const enableEnhancedMonitoring = app.node.tryGetContext('enableEnhancedMonitoring') !== 'false';

new ContainerObservabilityStack(app, 'ContainerObservabilityStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Comprehensive Container Observability and Performance Monitoring Stack',
  environmentId,
  alertEmail,
  enableEnhancedMonitoring,
  
  // Stack-level tags
  tags: {
    Project: 'ContainerObservability',
    Environment: environmentId || 'dev',
    ManagedBy: 'CDK',
    Purpose: 'Observability',
  },
});