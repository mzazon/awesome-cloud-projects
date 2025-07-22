#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as redshift from 'aws-cdk-lib/aws-redshift';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';

/**
 * Interface for stack configuration properties
 */
interface RedshiftWlmStackProps extends cdk.StackProps {
  /** Cluster identifier for the Redshift cluster */
  clusterIdentifier?: string;
  /** Email address for WLM monitoring alerts */
  alertEmail?: string;
  /** Instance type for the Redshift cluster */
  nodeType?: string;
  /** Number of compute nodes in the cluster */
  numberOfNodes?: number;
  /** VPC CIDR block for the cluster network */
  vpcCidr?: string;
}

/**
 * CDK Stack Redshift Analytics Workload Isolation
 * 
 * This stack creates:
 * - VPC with public and private subnets for secure cluster deployment
 * - Redshift cluster with manual WLM configuration for multi-tenant workload isolation
 * - Parameter group with custom WLM settings and query monitoring rules
 * - IAM roles and security groups with least privilege access
 * - CloudWatch monitoring and alerting for WLM performance metrics
 * - SNS topic for automated notifications of workload management issues
 */
class RedshiftWorkloadManagementStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: RedshiftWlmStackProps = {}) {
    super(scope, id, props);

    // Stack configuration with sensible defaults
    const clusterIdentifier = props.clusterIdentifier || `analytics-wlm-cluster-${this.generateRandomSuffix()}`;
    const alertEmail = props.alertEmail || 'admin@example.com';
    const nodeType = props.nodeType || 'dc2.large';
    const numberOfNodes = props.numberOfNodes || 2;
    const vpcCidr = props.vpcCidr || '10.0.0.0/16';

    // Create VPC for secure Redshift cluster deployment
    // Public subnets for NAT gateways, private subnets for cluster
    const vpc = new ec2.Vpc(this, 'RedshiftVPC', {
      cidr: vpcCidr,
      maxAzs: 2,
      natGateways: 1,
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
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });

    // Create subnet group for Redshift cluster placement
    const subnetGroup = new redshift.ClusterSubnetGroup(this, 'RedshiftSubnetGroup', {
      description: 'Subnet group for analytics workload isolation cluster',
      vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Security group for Redshift cluster with restricted access
    const redshiftSecurityGroup = new ec2.SecurityGroup(this, 'RedshiftSecurityGroup', {
      vpc,
      description: 'Security group for Redshift workload management cluster',
      allowAllOutbound: true,
    });

    // Allow inbound connections on Redshift port from VPC CIDR
    redshiftSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(vpc.vpcCidrBlock),
      ec2.Port.tcp(5439),
      'Allow Redshift connections from VPC'
    );

    // Generate secure random password for cluster admin
    const adminPassword = new secretsmanager.Secret(this, 'RedshiftAdminPassword', {
      description: 'Admin password for Redshift workload management cluster',
      generateSecretString: {
        secretStringTemplate: JSON.stringify({ username: 'admin' }),
        generateStringKey: 'password',
        excludeCharacters: '"@/\\\'',
        passwordLength: 32,
        includeSpace: false,
      },
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // IAM role for Redshift cluster with necessary permissions
    const redshiftRole = new iam.Role(this, 'RedshiftClusterRole', {
      assumedBy: new iam.ServicePrincipal('redshift.amazonaws.com'),
      description: 'IAM role for Redshift workload management cluster',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonS3ReadOnlyAccess'),
      ],
    });

    // Create parameter group with custom WLM configuration for workload isolation
    const wlmConfiguration = this.createWlmConfiguration();
    const parameterGroup = new redshift.ParameterGroup(this, 'WlmParameterGroup', {
      family: 'redshift-1.0',
      description: 'Parameter group for analytics workload isolation with custom WLM',
      parameters: {
        'wlm_json_configuration': wlmConfiguration,
        'enable_user_activity_logging': 'true',
        'log_statement': 'ddl',
        'log_min_duration_statement': '1000',
      },
    });

    // Create Redshift cluster with workload management configuration
    const cluster = new redshift.Cluster(this, 'RedshiftCluster', {
      clusterName: clusterIdentifier,
      masterUser: {
        masterUsername: 'admin',
        masterPassword: adminPassword.secretValueFromJson('password'),
      },
      vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
      securityGroups: [redshiftSecurityGroup],
      nodeType: redshift.NodeType.of(nodeType),
      numberOfNodes,
      subnetGroup,
      parameterGroup,
      roles: [redshiftRole],
      defaultDatabaseName: 'analytics',
      publiclyAccessible: false,
      encrypted: true,
      loggingProperties: {
        loggingEnabled: true,
        s3KeyPrefix: 'redshift-logs/',
      },
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create SNS topic for WLM monitoring alerts
    const alertTopic = new sns.Topic(this, 'WlmAlertTopic', {
      displayName: 'Redshift WLM Monitoring Alerts',
      topicName: `redshift-wlm-alerts-${this.generateRandomSuffix()}`,
    });

    // Subscribe email address to receive alerts
    alertTopic.addSubscription(new snsSubscriptions.EmailSubscription(alertEmail));

    // CloudWatch alarm for high queue wait times
    const queueLengthAlarm = new cloudwatch.Alarm(this, 'HighQueueWaitTimeAlarm', {
      alarmName: `RedshiftWLM-HighQueueWaitTime-${clusterIdentifier}`,
      alarmDescription: 'Alert when WLM queue wait time is high indicating resource contention',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Redshift',
        metricName: 'QueueLength',
        dimensionsMap: {
          ClusterIdentifier: cluster.clusterName,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 5,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    queueLengthAlarm.addAlarmAction(new cloudwatchActions.SnsAction(alertTopic));

    // CloudWatch alarm for high CPU utilization
    const cpuUtilizationAlarm = new cloudwatch.Alarm(this, 'HighCpuUtilizationAlarm', {
      alarmName: `RedshiftWLM-HighCPUUtilization-${clusterIdentifier}`,
      alarmDescription: 'Alert when cluster CPU utilization indicates resource saturation',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Redshift',
        metricName: 'CPUUtilization',
        dimensionsMap: {
          ClusterIdentifier: cluster.clusterName,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 85,
      evaluationPeriods: 3,
    });

    cpuUtilizationAlarm.addAlarmAction(new cloudwatchActions.SnsAction(alertTopic));

    // CloudWatch alarm for low query completion rate
    const queryCompletionAlarm = new cloudwatch.Alarm(this, 'LowQueryCompletionRateAlarm', {
      alarmName: `RedshiftWLM-LowQueryCompletionRate-${clusterIdentifier}`,
      alarmDescription: 'Alert when query completion rate drops indicating system performance issues',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Redshift',
        metricName: 'QueriesCompletedPerSecond',
        dimensionsMap: {
          ClusterIdentifier: cluster.clusterName,
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(15),
      }),
      threshold: 10,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 2,
    });

    queryCompletionAlarm.addAlarmAction(new cloudwatchActions.SnsAction(alertTopic));

    // Create CloudWatch dashboard for WLM monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'WlmDashboard', {
      dashboardName: `RedshiftWLM-${this.generateRandomSuffix()}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Redshift WLM Performance Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/Redshift',
                metricName: 'QueueLength',
                dimensionsMap: {
                  ClusterIdentifier: cluster.clusterName,
                },
                statistic: 'Average',
              }),
            ],
            right: [
              new cloudwatch.Metric({
                namespace: 'AWS/Redshift',
                metricName: 'QueriesCompletedPerSecond',
                dimensionsMap: {
                  ClusterIdentifier: cluster.clusterName,
                },
                statistic: 'Average',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/Redshift',
                metricName: 'CPUUtilization',
                dimensionsMap: {
                  ClusterIdentifier: cluster.clusterName,
                },
                statistic: 'Average',
              }),
            ],
            period: cdk.Duration.minutes(5),
            width: 12,
            height: 6,
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Cluster Health and Connections',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/Redshift',
                metricName: 'DatabaseConnections',
                dimensionsMap: {
                  ClusterIdentifier: cluster.clusterName,
                },
                statistic: 'Average',
              }),
            ],
            right: [
              new cloudwatch.Metric({
                namespace: 'AWS/Redshift',
                metricName: 'HealthStatus',
                dimensionsMap: {
                  ClusterIdentifier: cluster.clusterName,
                },
                statistic: 'Average',
              }),
            ],
            period: cdk.Duration.minutes(5),
            width: 12,
            height: 6,
          }),
        ],
      ],
    });

    // Stack outputs for integration and verification
    new cdk.CfnOutput(this, 'ClusterIdentifier', {
      value: cluster.clusterName,
      description: 'Identifier of the Redshift cluster',
      exportName: `${this.stackName}-ClusterIdentifier`,
    });

    new cdk.CfnOutput(this, 'ClusterEndpoint', {
      value: cluster.clusterEndpoint.hostname,
      description: 'Endpoint hostname for connecting to the Redshift cluster',
      exportName: `${this.stackName}-ClusterEndpoint`,
    });

    new cdk.CfnOutput(this, 'ClusterPort', {
      value: cluster.clusterEndpoint.port.toString(),
      description: 'Port number for connecting to the Redshift cluster',
      exportName: `${this.stackName}-ClusterPort`,
    });

    new cdk.CfnOutput(this, 'ParameterGroupName', {
      value: parameterGroup.parameterGroupName!,
      description: 'Name of the parameter group with WLM configuration',
      exportName: `${this.stackName}-ParameterGroupName`,
    });

    new cdk.CfnOutput(this, 'AlertTopicArn', {
      value: alertTopic.topicArn,
      description: 'ARN of the SNS topic for WLM monitoring alerts',
      exportName: `${this.stackName}-AlertTopicArn`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'URL to the CloudWatch dashboard for WLM monitoring',
      exportName: `${this.stackName}-DashboardUrl`,
    });

    new cdk.CfnOutput(this, 'AdminPasswordSecret', {
      value: adminPassword.secretArn,
      description: 'ARN of the secret containing the cluster admin password',
      exportName: `${this.stackName}-AdminPasswordSecret`,
    });

    new cdk.CfnOutput(this, 'SetupUsersCommand', {
      value: `psql -h ${cluster.clusterEndpoint.hostname} -p ${cluster.clusterEndpoint.port} -U admin -d analytics -c "CREATE GROUP \\"bi-dashboard-group\\"; CREATE GROUP \\"data-science-group\\"; CREATE GROUP \\"etl-process-group\\"; CREATE USER dashboard_user1 PASSWORD 'BiUser123!@#' IN GROUP \\"bi-dashboard-group\\"; CREATE USER analytics_user1 PASSWORD 'DsUser123!@#' IN GROUP \\"data-science-group\\"; CREATE USER etl_user1 PASSWORD 'EtlUser123!@#' IN GROUP \\"etl-process-group\\";"`,
      description: 'Command to set up user groups and users for workload isolation (run after cluster is ready)',
      exportName: `${this.stackName}-SetupUsersCommand`,
    });

    // Add tags for cost allocation and resource management
    cdk.Tags.of(this).add('Project', 'AnalyticsWorkloadIsolation');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('Purpose', 'RedshiftWLM');
    cdk.Tags.of(this).add('CostCenter', 'Analytics');
  }

  /**
   * Creates the WLM JSON configuration with queue definitions and query monitoring rules
   * 
   * This configuration implements a 4-queue system for workload isolation:
   * - Queue 1 (BI Dashboard): High concurrency (15), moderate memory (25%), fast timeout
   * - Queue 2 (Data Science): Low concurrency (3), high memory (40%), long timeout  
   * - Queue 3 (ETL): Balanced resources (5 concurrency, 25% memory), medium timeout
   * - Queue 4 (Default): Minimal resources for ad-hoc queries
   * 
   * Each queue includes query monitoring rules to prevent resource abuse and ensure SLA compliance
   */
  private createWlmConfiguration(): string {
    const wlmConfig = [
      {
        user_group: 'bi-dashboard-group',
        query_group: 'dashboard',
        query_concurrency: 15,
        memory_percent_to_use: 25,
        max_execution_time: 120000, // 2 minutes in milliseconds
        query_group_wild_card: 0,
        rules: [
          {
            rule_name: 'dashboard_timeout_rule',
            predicate: 'query_execution_time > 120',
            action: 'abort',
          },
          {
            rule_name: 'dashboard_cpu_rule',
            predicate: 'query_cpu_time > 30',
            action: 'log',
          },
        ],
      },
      {
        user_group: 'data-science-group',
        query_group: 'analytics',
        query_concurrency: 3,
        memory_percent_to_use: 40,
        max_execution_time: 7200000, // 2 hours in milliseconds
        query_group_wild_card: 0,
        rules: [
          {
            rule_name: 'analytics_memory_rule',
            predicate: 'query_temp_blocks_to_disk > 100000',
            action: 'log',
          },
          {
            rule_name: 'analytics_nested_loop_rule',
            predicate: 'nested_loop_join_row_count > 1000000',
            action: 'hop',
          },
        ],
      },
      {
        user_group: 'etl-process-group',
        query_group: 'etl',
        query_concurrency: 5,
        memory_percent_to_use: 25,
        max_execution_time: 3600000, // 1 hour in milliseconds
        query_group_wild_card: 0,
        rules: [
          {
            rule_name: 'etl_timeout_rule',
            predicate: 'query_execution_time > 3600',
            action: 'abort',
          },
          {
            rule_name: 'etl_scan_rule',
            predicate: 'scan_row_count > 1000000000',
            action: 'log',
          },
        ],
      },
      {
        query_concurrency: 2,
        memory_percent_to_use: 10,
        max_execution_time: 1800000, // 30 minutes in milliseconds
        query_group_wild_card: 1,
        rules: [
          {
            rule_name: 'default_timeout_rule',
            predicate: 'query_execution_time > 1800',
            action: 'abort',
          },
        ],
      },
    ];

    return JSON.stringify(wlmConfig);
  }

  /**
   * Generates a random suffix for unique resource naming
   */
  private generateRandomSuffix(): string {
    return Math.random().toString(36).substring(2, 8);
  }
}

// CDK application entry point
const app = new cdk.App();

// Create the main stack with configurable properties
new RedshiftWorkloadManagementStack(app, 'RedshiftWorkloadManagementStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Analytics Workload Isolation with Redshift Workload Management - CDK TypeScript implementation',
  
  // Stack configuration - customize these values as needed
  clusterIdentifier: process.env.CLUSTER_IDENTIFIER,
  alertEmail: process.env.ALERT_EMAIL || 'admin@example.com',
  nodeType: process.env.NODE_TYPE || 'dc2.large',
  numberOfNodes: process.env.NUMBER_OF_NODES ? parseInt(process.env.NUMBER_OF_NODES) : 2,
  vpcCidr: process.env.VPC_CIDR || '10.0.0.0/16',
  
  // Standard stack properties
  tags: {
    Project: 'AnalyticsWorkloadIsolation',
    Environment: 'Demo',
    Repository: 'aws-recipes',
    Recipe: 'analytics-workload-isolation-redshift-workload-management',
  },
});

app.synth();