#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as eks from 'aws-cdk-lib/aws-eks';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';

/**
 * Stack for Hybrid Kubernetes Monitoring with EKS Hybrid Nodes
 * 
 * This stack creates:
 * - VPC with public and private subnets for EKS cluster
 * - EKS cluster with hybrid node support enabled
 * - Fargate profile for cloud workloads
 * - CloudWatch Observability add-on for monitoring
 * - IAM roles and service accounts for monitoring
 * - CloudWatch dashboards and alarms
 * - Custom metrics collection Lambda function
 */
export class HybridKubernetesMonitoringStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = cdk.Names.uniqueId(this).toLowerCase().substring(0, 6);
    const clusterName = `hybrid-monitoring-cluster-${uniqueSuffix}`;
    const cloudwatchNamespace = 'EKS/HybridMonitoring';

    // Create VPC for EKS cluster with both public and private subnets
    const vpc = new ec2.Vpc(this, 'HybridMonitoringVPC', {
      maxAzs: 2,
      cidr: '10.0.0.0/16',
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
      natGateways: 1,
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });

    // Tag VPC and subnets for EKS discovery
    cdk.Tags.of(vpc).add('Name', `hybrid-monitoring-vpc-${uniqueSuffix}`);
    cdk.Tags.of(vpc.publicSubnets[0]).add('kubernetes.io/role/elb', '1');
    cdk.Tags.of(vpc.publicSubnets[1]).add('kubernetes.io/role/elb', '1');
    cdk.Tags.of(vpc.privateSubnets[0]).add('kubernetes.io/role/internal-elb', '1');
    cdk.Tags.of(vpc.privateSubnets[1]).add('kubernetes.io/role/internal-elb', '1');

    // Create IAM service role for EKS cluster
    const eksClusterRole = new iam.Role(this, 'EKSClusterServiceRole', {
      roleName: `EKSClusterServiceRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('eks.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEKSClusterPolicy'),
      ],
      description: 'Service role for EKS cluster with hybrid node support',
    });

    // Create CloudWatch log group for EKS cluster
    const clusterLogGroup = new logs.LogGroup(this, 'EKSClusterLogGroup', {
      logGroupName: `/aws/eks/${clusterName}/cluster`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create EKS cluster with hybrid node support
    const cluster = new eks.Cluster(this, 'HybridEKSCluster', {
      clusterName: clusterName,
      version: eks.KubernetesVersion.V1_31,
      role: eksClusterRole,
      vpc: vpc,
      vpcSubnets: [{ subnetType: ec2.SubnetType.PUBLIC }],
      defaultCapacity: 0, // We'll use Fargate and hybrid nodes instead
      endpointAccess: eks.EndpointAccess.PUBLIC_AND_PRIVATE,
      authenticationMode: eks.AuthenticationMode.API_AND_CONFIG_MAP,
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

    // Add tags to the cluster
    cdk.Tags.of(cluster).add('Environment', 'Production');
    cdk.Tags.of(cluster).add('Component', 'HybridMonitoring');

    // Create IAM role for Fargate execution
    const fargateExecutionRole = new iam.Role(this, 'EKSFargateExecutionRole', {
      roleName: `EKSFargateExecutionRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('eks-fargate-pods.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEKSFargatePodExecutionRolePolicy'),
      ],
      description: 'Execution role for Fargate pods in EKS cluster',
    });

    // Create Fargate profile for cloud workloads
    const fargateProfile = new eks.FargateProfile(this, 'CloudWorkloadsFargateProfile', {
      cluster: cluster,
      fargateProfileName: 'cloud-workloads',
      podExecutionRole: fargateExecutionRole,
      subnetSelection: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      selectors: [
        {
          namespace: 'cloud-apps',
        },
        {
          namespace: 'kube-system',
          labels: {
            'app.kubernetes.io/name': 'aws-load-balancer-controller',
          },
        },
      ],
    });

    // Add tags to Fargate profile
    cdk.Tags.of(fargateProfile).add('Environment', 'Production');
    cdk.Tags.of(fargateProfile).add('Component', 'CloudWorkloads');

    // Create IAM role for CloudWatch Observability add-on
    const cloudwatchObservabilityRole = new iam.Role(this, 'CloudWatchObservabilityRole', {
      roleName: `CloudWatchObservabilityRole-${uniqueSuffix}`,
      assumedBy: new iam.WebIdentityPrincipal(
        cluster.openIdConnectProvider.openIdConnectProviderArn,
        {
          'StringEquals': {
            [`${cluster.openIdConnectProvider.openIdConnectProviderIssuer}:sub`]: 'system:serviceaccount:amazon-cloudwatch:cloudwatch-agent',
            [`${cluster.openIdConnectProvider.openIdConnectProviderIssuer}:aud`]: 'sts.amazonaws.com',
          },
        }
      ),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy'),
      ],
      description: 'IAM role for CloudWatch Observability add-on',
    });

    // Install CloudWatch Observability add-on
    const cloudwatchAddon = new eks.CfnAddon(this, 'CloudWatchObservabilityAddon', {
      clusterName: cluster.clusterName,
      addonName: 'amazon-cloudwatch-observability',
      addonVersion: 'v2.1.0-eksbuild.1',
      serviceAccountRoleArn: cloudwatchObservabilityRole.roleArn,
      configurationValues: JSON.stringify({
        containerInsights: {
          enabled: true,
        },
      }),
    });

    // Ensure add-on is created after cluster and Fargate profile
    cloudwatchAddon.node.addDependency(cluster);
    cloudwatchAddon.node.addDependency(fargateProfile);

    // Create IAM role for custom metrics collection
    const hybridMetricsRole = new iam.Role(this, 'HybridMetricsRole', {
      roleName: `HybridMetricsRole-${uniqueSuffix}`,
      assumedBy: new iam.WebIdentityPrincipal(
        cluster.openIdConnectProvider.openIdConnectProviderArn,
        {
          'StringEquals': {
            [`${cluster.openIdConnectProvider.openIdConnectProviderIssuer}:sub`]: 'system:serviceaccount:cloud-apps:hybrid-metrics-sa',
            [`${cluster.openIdConnectProvider.openIdConnectProviderIssuer}:aud`]: 'sts.amazonaws.com',
          },
        }
      ),
      inlinePolicies: {
        CustomMetricsPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudwatch:PutMetricData',
                'cloudwatch:GetMetricStatistics',
                'cloudwatch:ListMetrics',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
      description: 'IAM role for custom metrics collection from hybrid nodes',
    });

    // Create Lambda function for custom metrics collection
    const metricsCollectorFunction = new lambda.Function(this, 'MetricsCollectorFunction', {
      functionName: `hybrid-metrics-collector-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.minutes(5),
      memorySize: 512,
      environment: {
        CLUSTER_NAME: cluster.clusterName,
        CLOUDWATCH_NAMESPACE: cloudwatchNamespace,
        AWS_REGION: this.region,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Lambda function to collect custom metrics from EKS hybrid cluster
    """
    
    cloudwatch = boto3.client('cloudwatch')
    cluster_name = os.environ['CLUSTER_NAME']
    namespace = os.environ['CLOUDWATCH_NAMESPACE']
    
    try:
        # Simulate custom metrics collection
        # In a real implementation, this would connect to the EKS cluster
        # and collect actual metrics from hybrid nodes
        
        metrics = [
            {
                'MetricName': 'HybridNodeCount',
                'Value': 2,  # Placeholder value
                'Unit': 'Count',
                'Dimensions': [
                    {
                        'Name': 'ClusterName',
                        'Value': cluster_name
                    }
                ]
            },
            {
                'MetricName': 'FargatePodCount',
                'Value': 3,  # Placeholder value
                'Unit': 'Count',
                'Dimensions': [
                    {
                        'Name': 'ClusterName',
                        'Value': cluster_name
                    }
                ]
            },
            {
                'MetricName': 'TotalPodCount',
                'Value': 5,  # Placeholder value
                'Unit': 'Count',
                'Dimensions': [
                    {
                        'Name': 'ClusterName',
                        'Value': cluster_name
                    }
                ]
            }
        ]
        
        # Put metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace=namespace,
            MetricData=metrics
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Successfully published {len(metrics)} metrics to CloudWatch')
        }
        
    except Exception as e:
        print(f'Error publishing metrics: {str(e)}')
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error publishing metrics: {str(e)}')
        }
      `),
    });

    // Grant CloudWatch permissions to the Lambda function
    metricsCollectorFunction.addToRolePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'cloudwatch:PutMetricData',
          'cloudwatch:GetMetricStatistics',
          'cloudwatch:ListMetrics',
        ],
        resources: ['*'],
      })
    );

    // Create EventBridge rule to trigger metrics collection every 5 minutes
    const metricsCollectionRule = new events.Rule(this, 'MetricsCollectionRule', {
      ruleName: `hybrid-metrics-collection-${uniqueSuffix}`,
      schedule: events.Schedule.rate(cdk.Duration.minutes(5)),
      description: 'Trigger custom metrics collection for hybrid EKS cluster',
    });

    // Add Lambda function as target for the EventBridge rule
    metricsCollectionRule.addTarget(new targets.LambdaFunction(metricsCollectorFunction));

    // Create CloudWatch dashboard for hybrid monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'HybridMonitoringDashboard', {
      dashboardName: `EKS-Hybrid-Monitoring-${clusterName}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Hybrid Cluster Capacity',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/EKS',
                metricName: 'cluster_node_count',
                dimensionsMap: {
                  ClusterName: cluster.clusterName,
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
              new cloudwatch.Metric({
                namespace: cloudwatchNamespace,
                metricName: 'HybridNodeCount',
                dimensionsMap: {
                  ClusterName: cluster.clusterName,
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
              new cloudwatch.Metric({
                namespace: cloudwatchNamespace,
                metricName: 'FargatePodCount',
                dimensionsMap: {
                  ClusterName: cluster.clusterName,
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Pod Resource Utilization',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/ContainerInsights',
                metricName: 'pod_cpu_utilization',
                dimensionsMap: {
                  ClusterName: cluster.clusterName,
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/ContainerInsights',
                metricName: 'pod_memory_utilization',
                dimensionsMap: {
                  ClusterName: cluster.clusterName,
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
      ],
    });

    // Create CloudWatch alarms for monitoring
    const highCpuAlarm = new cloudwatch.Alarm(this, 'HighCPUAlarm', {
      alarmName: `EKS-Hybrid-HighCPU-${cluster.clusterName}`,
      alarmDescription: 'High CPU utilization in hybrid cluster',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ContainerInsights',
        metricName: 'pod_cpu_utilization',
        dimensionsMap: {
          ClusterName: cluster.clusterName,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 80,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    const highMemoryAlarm = new cloudwatch.Alarm(this, 'HighMemoryAlarm', {
      alarmName: `EKS-Hybrid-HighMemory-${cluster.clusterName}`,
      alarmDescription: 'High memory utilization in hybrid cluster',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ContainerInsights',
        metricName: 'pod_memory_utilization',
        dimensionsMap: {
          ClusterName: cluster.clusterName,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 80,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    const lowNodeCountAlarm = new cloudwatch.Alarm(this, 'LowNodeCountAlarm', {
      alarmName: `EKS-Hybrid-LowNodeCount-${cluster.clusterName}`,
      alarmDescription: 'Low hybrid node count',
      metric: new cloudwatch.Metric({
        namespace: cloudwatchNamespace,
        metricName: 'HybridNodeCount',
        dimensionsMap: {
          ClusterName: cluster.clusterName,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.BREACHING,
    });

    // Output important information
    new cdk.CfnOutput(this, 'ClusterName', {
      value: cluster.clusterName,
      description: 'Name of the EKS cluster',
      exportName: `${this.stackName}-ClusterName`,
    });

    new cdk.CfnOutput(this, 'ClusterEndpoint', {
      value: cluster.clusterEndpoint,
      description: 'Endpoint for the EKS cluster',
      exportName: `${this.stackName}-ClusterEndpoint`,
    });

    new cdk.CfnOutput(this, 'ClusterArn', {
      value: cluster.clusterArn,
      description: 'ARN of the EKS cluster',
      exportName: `${this.stackName}-ClusterArn`,
    });

    new cdk.CfnOutput(this, 'FargateProfileName', {
      value: fargateProfile.fargateProfileName,
      description: 'Name of the Fargate profile for cloud workloads',
      exportName: `${this.stackName}-FargateProfileName`,
    });

    new cdk.CfnOutput(this, 'VpcId', {
      value: vpc.vpcId,
      description: 'ID of the VPC created for the cluster',
      exportName: `${this.stackName}-VpcId`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'URL to access the CloudWatch dashboard',
      exportName: `${this.stackName}-DashboardUrl`,
    });

    new cdk.CfnOutput(this, 'KubectlConfig', {
      value: `aws eks update-kubeconfig --region ${this.region} --name ${cluster.clusterName}`,
      description: 'Command to configure kubectl',
      exportName: `${this.stackName}-KubectlConfig`,
    });

    new cdk.CfnOutput(this, 'MetricsCollectorFunctionName', {
      value: metricsCollectorFunction.functionName,
      description: 'Name of the Lambda function for custom metrics collection',
      exportName: `${this.stackName}-MetricsCollectorFunction`,
    });
  }
}

// Create the CDK application
const app = new cdk.App();

// Create the stack with environment configuration
new HybridKubernetesMonitoringStack(app, 'HybridKubernetesMonitoringStack', {
  description: 'Stack for Hybrid Kubernetes Monitoring with EKS Hybrid Nodes',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'HybridKubernetesMonitoring',
    Environment: 'Production',
    Owner: 'CloudOps',
    CostCenter: 'Infrastructure',
  },
});

// Synthesize the app
app.synth();