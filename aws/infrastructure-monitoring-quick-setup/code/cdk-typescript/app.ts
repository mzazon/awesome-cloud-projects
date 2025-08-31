#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Props for the Infrastructure Monitoring Stack
 */
interface InfrastructureMonitoringStackProps extends cdk.StackProps {
  /**
   * Environment prefix for resource naming
   * @default 'infra-monitoring'
   */
  readonly environmentPrefix?: string;
  
  /**
   * CloudWatch log retention in days
   * @default 30
   */
  readonly logRetentionDays?: number;
  
  /**
   * CPU utilization threshold for alarms (percentage)
   * @default 80
   */
  readonly cpuThreshold?: number;
  
  /**
   * Disk usage threshold for alarms (percentage)
   * @default 85
   */
  readonly diskThreshold?: number;
}

/**
 * CDK Stack for Infrastructure Monitoring Setup with Systems Manager
 * 
 * This stack implements the infrastructure monitoring solution described in the recipe,
 * providing comprehensive monitoring, compliance, and management capabilities through
 * AWS Systems Manager and CloudWatch integration.
 */
export class InfrastructureMonitoringStack extends cdk.Stack {
  /**
   * The IAM role for Systems Manager operations
   */
  public readonly ssmServiceRole: iam.Role;
  
  /**
   * The CloudWatch dashboard for monitoring
   */
  public readonly monitoringDashboard: cloudwatch.Dashboard;
  
  /**
   * The CloudWatch Agent configuration parameter
   */
  public readonly cloudWatchAgentConfig: ssm.StringParameter;

  constructor(scope: Construct, id: string, props: InfrastructureMonitoringStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const environmentPrefix = props.environmentPrefix || 'infra-monitoring';
    const logRetentionDays = props.logRetentionDays || 30;
    const cpuThreshold = props.cpuThreshold || 80;
    const diskThreshold = props.diskThreshold || 85;

    // Generate a random suffix for unique resource naming
    const randomSuffix = this.generateRandomSuffix();
    const resourcePrefix = `${environmentPrefix}-${randomSuffix}`;

    // Create IAM Service Role for Systems Manager
    this.ssmServiceRole = this.createSSMServiceRole(resourcePrefix);

    // Create CloudWatch Agent Configuration
    this.cloudWatchAgentConfig = this.createCloudWatchAgentConfig(resourcePrefix);

    // Create Infrastructure Monitoring Dashboard
    this.monitoringDashboard = this.createMonitoringDashboard(resourcePrefix);

    // Create CloudWatch Alarms for Critical Metrics
    this.createCloudWatchAlarms(resourcePrefix, cpuThreshold, diskThreshold);

    // Set Up Compliance Monitoring
    this.setupComplianceMonitoring(resourcePrefix);

    // Configure Log Collection and Retention
    this.configureLogCollection(resourcePrefix, logRetentionDays);

    // Add stack outputs
    this.createStackOutputs();
  }

  /**
   * Creates the IAM service role for Systems Manager operations
   */
  private createSSMServiceRole(resourcePrefix: string): iam.Role {
    const role = new iam.Role(this, 'SSMServiceRole', {
      roleName: `SSMServiceRole-${resourcePrefix}`,
      description: 'IAM role for Systems Manager to manage EC2 instances and configure monitoring',
      assumedBy: new iam.ServicePrincipal('ssm.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy'),
      ],
    });

    // Add custom policy for additional Systems Manager permissions
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'ssm:CreateAssociation',
        'ssm:DeleteAssociation',
        'ssm:DescribeAssociations',
        'ssm:ListAssociations',
        'ssm:UpdateAssociation',
        'ssm:GetParameter',
        'ssm:PutParameter',
        'ssm:DeleteParameter',
        'ssm:DescribeParameters',
      ],
      resources: ['*'],
    }));

    // Add CloudWatch permissions
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'cloudwatch:PutMetricData',
        'cloudwatch:GetMetricStatistics',
        'cloudwatch:ListMetrics',
        'logs:CreateLogGroup',
        'logs:CreateLogStream',
        'logs:PutLogEvents',
        'logs:DescribeLogStreams',
      ],
      resources: ['*'],
    }));

    cdk.Tags.of(role).add('Purpose', 'SystemsManagerMonitoring');
    cdk.Tags.of(role).add('Component', 'IAMRole');

    return role;
  }

  /**
   * Creates the CloudWatch Agent configuration parameter
   */
  private createCloudWatchAgentConfig(resourcePrefix: string): ssm.StringParameter {
    const agentConfig = {
      metrics: {
        namespace: 'CWAgent',
        metrics_collected: {
          cpu: {
            measurement: ['cpu_usage_idle', 'cpu_usage_iowait'],
            metrics_collection_interval: 60,
          },
          disk: {
            measurement: ['used_percent'],
            metrics_collection_interval: 60,
            resources: ['*'],
          },
          mem: {
            measurement: ['mem_used_percent'],
            metrics_collection_interval: 60,
          },
        },
      },
    };

    const parameter = new ssm.StringParameter(this, 'CloudWatchAgentConfig', {
      parameterName: `AmazonCloudWatch-Agent-Config-${resourcePrefix}`,
      description: 'CloudWatch Agent configuration for detailed system metrics collection',
      stringValue: JSON.stringify(agentConfig, null, 2),
      tier: ssm.ParameterTier.STANDARD,
    });

    cdk.Tags.of(parameter).add('Purpose', 'CloudWatchAgentConfiguration');
    cdk.Tags.of(parameter).add('Component', 'SSMParameter');

    return parameter;
  }

  /**
   * Creates the comprehensive monitoring dashboard
   */
  private createMonitoringDashboard(resourcePrefix: string): cloudwatch.Dashboard {
    const dashboard = new cloudwatch.Dashboard(this, 'InfrastructureDashboard', {
      dashboardName: `Infrastructure-Monitoring-${resourcePrefix}`,
    });

    // EC2 Instance Performance Widget
    const ec2MetricsWidget = new cloudwatch.GraphWidget({
      title: 'EC2 Instance Performance',
      width: 12,
      height: 6,
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/EC2',
          metricName: 'CPUUtilization',
          statistic: 'Average',
          period: cdk.Duration.minutes(5),
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/EC2',
          metricName: 'NetworkIn',
          statistic: 'Average',
          period: cdk.Duration.minutes(5),
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/EC2',
          metricName: 'NetworkOut',
          statistic: 'Average',
          period: cdk.Duration.minutes(5),
        }),
      ],
    });

    // Systems Manager Operations Widget
    const ssmMetricsWidget = new cloudwatch.GraphWidget({
      title: 'Systems Manager Operations',
      width: 12,
      height: 6,
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/SSM-RunCommand',
          metricName: 'CommandsSucceeded',
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/SSM-RunCommand',
          metricName: 'CommandsFailed',
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        }),
      ],
    });

    // CloudWatch Agent Metrics Widget
    const cwAgentMetricsWidget = new cloudwatch.GraphWidget({
      title: 'System Performance Metrics',
      width: 24,
      height: 6,
      left: [
        new cloudwatch.Metric({
          namespace: 'CWAgent',
          metricName: 'cpu_usage_idle',
          statistic: 'Average',
          period: cdk.Duration.minutes(5),
        }),
        new cloudwatch.Metric({
          namespace: 'CWAgent',
          metricName: 'mem_used_percent',
          statistic: 'Average',
          period: cdk.Duration.minutes(5),
        }),
        new cloudwatch.Metric({
          namespace: 'CWAgent',
          metricName: 'used_percent',
          statistic: 'Average',
          period: cdk.Duration.minutes(5),
        }),
      ],
    });

    // Add widgets to dashboard in organized layout
    dashboard.addWidgets(ec2MetricsWidget, ssmMetricsWidget);
    dashboard.addWidgets(cwAgentMetricsWidget);

    cdk.Tags.of(dashboard).add('Purpose', 'InfrastructureMonitoring');
    cdk.Tags.of(dashboard).add('Component', 'CloudWatchDashboard');

    return dashboard;
  }

  /**
   * Creates CloudWatch alarms for critical infrastructure metrics
   */
  private createCloudWatchAlarms(resourcePrefix: string, cpuThreshold: number, diskThreshold: number): void {
    // CPU Utilization Alarm
    new cloudwatch.Alarm(this, 'HighCPUUtilizationAlarm', {
      alarmName: `High-CPU-Utilization-${resourcePrefix}`,
      alarmDescription: `Alert when CPU exceeds ${cpuThreshold}%`,
      metric: new cloudwatch.Metric({
        namespace: 'AWS/EC2',
        metricName: 'CPUUtilization',
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: cpuThreshold,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Disk Usage Alarm (requires CloudWatch Agent)
    new cloudwatch.Alarm(this, 'HighDiskUsageAlarm', {
      alarmName: `High-Disk-Usage-${resourcePrefix}`,
      alarmDescription: `Alert when disk usage exceeds ${diskThreshold}%`,
      metric: new cloudwatch.Metric({
        namespace: 'CWAgent',
        metricName: 'used_percent',
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: diskThreshold,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Systems Manager Command Failure Alarm
    new cloudwatch.Alarm(this, 'SSMCommandFailureAlarm', {
      alarmName: `SSM-Command-Failures-${resourcePrefix}`,
      alarmDescription: 'Alert when Systems Manager commands fail',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/SSM-RunCommand',
        metricName: 'CommandsFailed',
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
  }

  /**
   * Sets up compliance monitoring with Systems Manager associations
   */
  private setupComplianceMonitoring(resourcePrefix: string): void {
    // Daily Inventory Collection Association
    new ssm.CfnAssociation(this, 'DailyInventoryAssociation', {
      name: 'AWS-GatherSoftwareInventory',
      associationName: `Daily-Inventory-Collection-${resourcePrefix}`,
      scheduleExpression: 'rate(1 day)',
      targets: [
        {
          key: 'tag:Environment',
          values: ['*'],
        },
      ],
      complianceSeverity: 'MEDIUM',
      maxConcurrency: '50%',
      maxErrors: '10%',
    });

    // Weekly Patch Scanning Association
    new ssm.CfnAssociation(this, 'WeeklyPatchScanAssociation', {
      name: 'AWS-RunPatchBaseline',
      associationName: `Weekly-Patch-Scanning-${resourcePrefix}`,
      scheduleExpression: 'rate(7 days)',
      targets: [
        {
          key: 'tag:Environment',
          values: ['*'],
        },
      ],
      parameters: {
        Operation: ['Scan'],
      },
      complianceSeverity: 'HIGH',
      maxConcurrency: '25%',
      maxErrors: '5%',
    });

    // Security Configuration Compliance Association
    new ssm.CfnAssociation(this, 'SecurityComplianceAssociation', {
      name: 'AWS-ConfigureAWSPackage',
      associationName: `Security-Compliance-${resourcePrefix}`,
      scheduleExpression: 'rate(1 day)',
      targets: [
        {
          key: 'tag:Environment',
          values: ['*'],
        },
      ],
      parameters: {
        action: ['Install'],
        name: ['AmazonCloudWatchAgent'],
      },
      complianceSeverity: 'HIGH',
      maxConcurrency: '10%',
      maxErrors: '0%',
    });
  }

  /**
   * Configures centralized log collection with appropriate retention policies
   */
  private configureLogCollection(resourcePrefix: string, retentionDays: number): void {
    // System logs log group
    const systemLogsGroup = new logs.LogGroup(this, 'SystemLogsGroup', {
      logGroupName: `/aws/systems-manager/infrastructure-${resourcePrefix}`,
      retention: logs.RetentionDays.THIRTY_DAYS,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Application logs log group with shorter retention
    const appLogsGroup = new logs.LogGroup(this, 'ApplicationLogsGroup', {
      logGroupName: `/aws/ec2/application-logs-${resourcePrefix}`,
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // CloudWatch Agent logs
    new logs.LogGroup(this, 'CloudWatchAgentLogsGroup', {
      logGroupName: `/aws/amazoncloudwatch-agent/${resourcePrefix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create log stream for Run Command outputs
    new logs.LogStream(this, 'RunCommandLogStream', {
      logGroup: systemLogsGroup,
      logStreamName: 'run-command-outputs',
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Add tags for cost tracking and management
    cdk.Tags.of(systemLogsGroup).add('Purpose', 'SystemsManagerLogging');
    cdk.Tags.of(appLogsGroup).add('Purpose', 'ApplicationLogging');
    cdk.Tags.of(systemLogsGroup).add('Component', 'LogGroup');
    cdk.Tags.of(appLogsGroup).add('Component', 'LogGroup');
  }

  /**
   * Creates stack outputs for important resources
   */
  private createStackOutputs(): void {
    new cdk.CfnOutput(this, 'SSMServiceRoleArn', {
      description: 'ARN of the Systems Manager service role',
      value: this.ssmServiceRole.roleArn,
      exportName: `${this.stackName}-SSMServiceRoleArn`,
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      description: 'URL to the CloudWatch monitoring dashboard',
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.monitoringDashboard.dashboardName}`,
      exportName: `${this.stackName}-DashboardURL`,
    });

    new cdk.CfnOutput(this, 'CloudWatchAgentConfigParameter', {
      description: 'Name of the CloudWatch Agent configuration parameter',
      value: this.cloudWatchAgentConfig.parameterName,
      exportName: `${this.stackName}-CWAgentConfig`,
    });

    new cdk.CfnOutput(this, 'SystemsManagerConsoleURL', {
      description: 'URL to the Systems Manager console',
      value: `https://${this.region}.console.aws.amazon.com/systems-manager/managed-instances?region=${this.region}`,
      exportName: `${this.stackName}-SSMConsoleURL`,
    });
  }

  /**
   * Generates a random suffix for unique resource naming
   */
  private generateRandomSuffix(): string {
    return Math.random().toString(36).substring(2, 8);
  }
}

/**
 * Main CDK Application
 */
class InfrastructureMonitoringApp extends cdk.App {
  constructor() {
    super();

    // Get context values or use defaults
    const environmentPrefix = this.node.tryGetContext('environmentPrefix') || 'infra-monitoring';
    const cpuThreshold = this.node.tryGetContext('cpuThreshold') || 80;
    const diskThreshold = this.node.tryGetContext('diskThreshold') || 85;
    const logRetentionDays = this.node.tryGetContext('logRetentionDays') || 30;

    // Create the main monitoring stack
    new InfrastructureMonitoringStack(this, 'InfrastructureMonitoringStack', {
      description: 'Infrastructure Monitoring Setup with Systems Manager and CloudWatch (uksb-1tupboc58)',
      environmentPrefix,
      cpuThreshold,
      diskThreshold,
      logRetentionDays,
      env: {
        account: process.env.CDK_DEFAULT_ACCOUNT,
        region: process.env.CDK_DEFAULT_REGION,
      },
      tags: {
        Project: 'InfrastructureMonitoring',
        Environment: environmentPrefix,
        ManagedBy: 'CDK',
        Recipe: 'infrastructure-monitoring-quick-setup',
      },
    });
  }
}

// Create and run the application
new InfrastructureMonitoringApp();