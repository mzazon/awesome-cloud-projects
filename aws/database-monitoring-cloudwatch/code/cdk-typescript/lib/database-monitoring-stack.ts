import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

/**
 * Interface for DatabaseMonitoringStack properties
 */
export interface DatabaseMonitoringStackProps extends cdk.StackProps {
  alertEmail: string;
  environment?: string;
  databaseInstanceClass?: string;
  databaseAllocatedStorage?: number;
  databaseName?: string;
  databaseUsername?: string;
  monitoringInterval?: number;
  performanceInsightsRetentionPeriod?: number;
  cpuAlarmThreshold?: number;
  connectionsAlarmThreshold?: number;
  freeStorageSpaceThreshold?: number;
}

/**
 * CDK Stack for Database Monitoring with CloudWatch
 * 
 * This stack creates a comprehensive database monitoring solution including:
 * - VPC with public and private subnets across multiple AZs
 * - RDS MySQL instance with enhanced monitoring and Performance Insights
 * - CloudWatch dashboard for real-time database metrics visualization
 * - CloudWatch alarms for proactive monitoring of critical metrics
 * - SNS topic for email notifications when alarms are triggered
 * - IAM role for enhanced monitoring permissions
 */
export class DatabaseMonitoringStack extends cdk.Stack {
  public readonly database: rds.DatabaseInstance;
  public readonly dashboard: cloudwatch.Dashboard;
  public readonly alertsTopic: sns.Topic;
  
  constructor(scope: Construct, id: string, props: DatabaseMonitoringStackProps) {
    super(scope, id, props);

    // Configuration with defaults
    const config = {
      environment: props.environment || 'development',
      databaseInstanceClass: props.databaseInstanceClass || 'db.t3.micro',
      databaseAllocatedStorage: props.databaseAllocatedStorage || 20,
      databaseName: props.databaseName || 'monitoringdemo',
      databaseUsername: props.databaseUsername || 'admin',
      monitoringInterval: props.monitoringInterval || 60,
      performanceInsightsRetentionPeriod: props.performanceInsightsRetentionPeriod || 7,
      cpuAlarmThreshold: props.cpuAlarmThreshold || 80,
      connectionsAlarmThreshold: props.connectionsAlarmThreshold || 50,
      freeStorageSpaceThreshold: props.freeStorageSpaceThreshold || 2147483648, // 2GB in bytes
    };

    // Helper functions for conditional logic
    const enableEnhancedMonitoring = config.monitoringInterval > 0;
    const enablePerformanceInsights = config.databaseInstanceClass !== 'db.t3.micro';
    const isProduction = config.environment === 'production';

    // =========================================================================
    // VPC and Networking
    // =========================================================================
    
    // Create VPC with public and private subnets across 2 AZs
    const vpc = new ec2.Vpc(this, 'DatabaseVPC', {
      maxAzs: 2,
      cidr: '10.0.0.0/16',
      natGateways: 0, // No NAT gateways needed for this demo
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Database',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });

    // Security group for RDS instance
    const databaseSecurityGroup = new ec2.SecurityGroup(this, 'DatabaseSecurityGroup', {
      vpc,
      description: 'Security group for database monitoring demo',
      allowAllOutbound: false,
    });

    // Allow MySQL access from within VPC
    databaseSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(vpc.vpcCidrBlock),
      ec2.Port.tcp(3306),
      'MySQL access from VPC'
    );

    // =========================================================================
    // IAM Role for Enhanced Monitoring
    // =========================================================================
    
    let enhancedMonitoringRole: iam.Role | undefined;
    
    if (enableEnhancedMonitoring) {
      enhancedMonitoringRole = new iam.Role(this, 'EnhancedMonitoringRole', {
        assumedBy: new iam.ServicePrincipal('monitoring.rds.amazonaws.com'),
        managedPolicies: [
          iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonRDSEnhancedMonitoringRole'),
        ],
        description: 'IAM role for RDS Enhanced Monitoring',
      });

      // Add tags to the role
      cdk.Tags.of(enhancedMonitoringRole).add('Name', `${this.stackName}-enhanced-monitoring-role`);
      cdk.Tags.of(enhancedMonitoringRole).add('Purpose', 'RDS Enhanced Monitoring');
    }

    // =========================================================================
    // Database Password Management
    // =========================================================================
    
    // Generate a secure password for the database
    const databaseCredentials = rds.Credentials.fromGeneratedSecret(config.databaseUsername, {
      description: `Master credentials for ${this.stackName} database`,
      secretName: `${this.stackName}/database/credentials`,
    });

    // =========================================================================
    // RDS Database Instance
    // =========================================================================
    
    this.database = new rds.DatabaseInstance(this, 'DatabaseInstance', {
      // Database engine configuration
      engine: rds.DatabaseInstanceEngine.mysql({
        version: rds.MysqlEngineVersion.VER_8_0_35,
      }),
      instanceType: ec2.InstanceType.of(
        ec2.InstanceClass.BURSTABLE3,
        config.databaseInstanceClass.split('.')[2] as ec2.InstanceSize
      ),
      
      // Database configuration
      databaseName: config.databaseName,
      credentials: databaseCredentials,
      
      // Storage configuration
      allocatedStorage: config.databaseAllocatedStorage,
      storageType: rds.StorageType.GP3,
      storageEncrypted: true,
      
      // Network configuration
      vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
      securityGroups: [databaseSecurityGroup],
      
      // Backup configuration
      backupRetention: cdk.Duration.days(7),
      preferredBackupWindow: '03:00-04:00',
      preferredMaintenanceWindow: 'sun:04:00-sun:05:00',
      
      // Monitoring configuration
      monitoringInterval: enableEnhancedMonitoring ? cdk.Duration.seconds(config.monitoringInterval) : undefined,
      monitoringRole: enhancedMonitoringRole,
      enablePerformanceInsights: enablePerformanceInsights,
      performanceInsightRetention: enablePerformanceInsights 
        ? (config.performanceInsightsRetentionPeriod === 7 
           ? rds.PerformanceInsightRetention.DEFAULT 
           : rds.PerformanceInsightRetention.LONG_TERM)
        : undefined,
      
      // Production-specific configuration
      multiAz: isProduction,
      deletionProtection: isProduction,
      
      // Deletion policy for demo purposes
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Add tags to the database
    cdk.Tags.of(this.database).add('Name', `${this.stackName}-database`);
    cdk.Tags.of(this.database).add('Purpose', 'Database Monitoring Demo');
    cdk.Tags.of(this.database).add('Engine', 'MySQL');

    // =========================================================================
    // SNS Topic and Subscription for Alerts
    // =========================================================================
    
    this.alertsTopic = new sns.Topic(this, 'DatabaseAlertsTopic', {
      displayName: 'Database Monitoring Alerts',
      topicName: `${this.stackName}-database-alerts`,
    });

    // Add email subscription
    this.alertsTopic.addSubscription(
      new snsSubscriptions.EmailSubscription(props.alertEmail)
    );

    // Add tags to the SNS topic
    cdk.Tags.of(this.alertsTopic).add('Name', `${this.stackName}-database-alerts`);
    cdk.Tags.of(this.alertsTopic).add('Purpose', 'Database Monitoring Notifications');

    // =========================================================================
    // CloudWatch Alarms
    // =========================================================================
    
    // CPU Utilization Alarm
    const cpuAlarm = new cloudwatch.Alarm(this, 'CPUUtilizationAlarm', {
      alarmName: `${this.stackName}-HighCPU`,
      alarmDescription: `High CPU utilization on ${this.database.instanceIdentifier}`,
      metric: this.database.metricCPUUtilization({
        period: cdk.Duration.minutes(5),
        statistic: cloudwatch.Statistic.AVERAGE,
      }),
      threshold: config.cpuAlarmThreshold,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    cpuAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.alertsTopic));
    cpuAlarm.addOkAction(new cloudwatchActions.SnsAction(this.alertsTopic));

    // Database Connections Alarm
    const connectionsAlarm = new cloudwatch.Alarm(this, 'DatabaseConnectionsAlarm', {
      alarmName: `${this.stackName}-HighConnections`,
      alarmDescription: `High database connections on ${this.database.instanceIdentifier}`,
      metric: this.database.metricDatabaseConnections({
        period: cdk.Duration.minutes(5),
        statistic: cloudwatch.Statistic.AVERAGE,
      }),
      threshold: config.connectionsAlarmThreshold,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    connectionsAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.alertsTopic));
    connectionsAlarm.addOkAction(new cloudwatchActions.SnsAction(this.alertsTopic));

    // Free Storage Space Alarm
    const storageAlarm = new cloudwatch.Alarm(this, 'FreeStorageSpaceAlarm', {
      alarmName: `${this.stackName}-LowStorage`,
      alarmDescription: `Low free storage space on ${this.database.instanceIdentifier}`,
      metric: this.database.metricFreeStorageSpace({
        period: cdk.Duration.minutes(5),
        statistic: cloudwatch.Statistic.AVERAGE,
      }),
      threshold: config.freeStorageSpaceThreshold,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    storageAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.alertsTopic));
    storageAlarm.addOkAction(new cloudwatchActions.SnsAction(this.alertsTopic));

    // Additional production alarms
    if (isProduction) {
      // Read Latency Alarm
      const readLatencyAlarm = new cloudwatch.Alarm(this, 'ReadLatencyAlarm', {
        alarmName: `${this.stackName}-HighReadLatency`,
        alarmDescription: `High read latency on ${this.database.instanceIdentifier}`,
        metric: this.database.metricReadLatency({
          period: cdk.Duration.minutes(5),
          statistic: cloudwatch.Statistic.AVERAGE,
        }),
        threshold: 0.2,
        evaluationPeriods: 3,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      });

      readLatencyAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.alertsTopic));

      // Write Latency Alarm
      const writeLatencyAlarm = new cloudwatch.Alarm(this, 'WriteLatencyAlarm', {
        alarmName: `${this.stackName}-HighWriteLatency`,
        alarmDescription: `High write latency on ${this.database.instanceIdentifier}`,
        metric: this.database.metricWriteLatency({
          period: cdk.Duration.minutes(5),
          statistic: cloudwatch.Statistic.AVERAGE,
        }),
        threshold: 0.2,
        evaluationPeriods: 3,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      });

      writeLatencyAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.alertsTopic));
    }

    // =========================================================================
    // CloudWatch Dashboard
    // =========================================================================
    
    this.dashboard = new cloudwatch.Dashboard(this, 'DatabaseMonitoringDashboard', {
      dashboardName: `${this.stackName}-DatabaseMonitoring`,
      defaultInterval: cdk.Duration.hours(1),
    });

    // Performance Overview Widget
    const performanceOverviewWidget = new cloudwatch.GraphWidget({
      title: 'Database Performance Overview',
      width: 12,
      height: 6,
      left: [
        this.database.metricCPUUtilization(),
        this.database.metricDatabaseConnections(),
        this.database.metricFreeableMemory(),
      ],
      leftAnnotations: [
        {
          label: 'CPU Alarm Threshold',
          value: config.cpuAlarmThreshold,
        },
      ],
    });

    // Storage and Latency Widget
    const storageLatencyWidget = new cloudwatch.GraphWidget({
      title: 'Storage and Latency Metrics',
      width: 12,
      height: 6,
      left: [
        this.database.metricFreeStorageSpace(),
        this.database.metricReadLatency(),
        this.database.metricWriteLatency(),
      ],
    });

    // I/O Operations Widget
    const ioOperationsWidget = new cloudwatch.GraphWidget({
      title: 'I/O Operations Per Second',
      width: 12,
      height: 6,
      left: [
        this.database.metricReadIOPS(),
        this.database.metricWriteIOPS(),
      ],
    });

    // I/O Throughput Widget
    const ioThroughputWidget = new cloudwatch.GraphWidget({
      title: 'I/O Throughput (Bytes/Second)',
      width: 12,
      height: 6,
      left: [
        this.database.metricReadThroughput(),
        this.database.metricWriteThroughput(),
      ],
    });

    // Additional Database Metrics Widget
    const additionalMetricsWidget = new cloudwatch.GraphWidget({
      title: 'Additional Database Metrics',
      width: 24,
      height: 6,
      left: [
        // Create custom metrics for additional RDS metrics
        new cloudwatch.Metric({
          namespace: 'AWS/RDS',
          metricName: 'BinLogDiskUsage',
          dimensionsMap: {
            DBInstanceIdentifier: this.database.instanceIdentifier,
          },
          statistic: cloudwatch.Statistic.AVERAGE,
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/RDS',
          metricName: 'SwapUsage',
          dimensionsMap: {
            DBInstanceIdentifier: this.database.instanceIdentifier,
          },
          statistic: cloudwatch.Statistic.AVERAGE,
        }),
      ],
    });

    // Add widgets to dashboard
    this.dashboard.addWidgets(
      performanceOverviewWidget,
      storageLatencyWidget
    );
    this.dashboard.addWidgets(
      ioOperationsWidget,
      ioThroughputWidget
    );
    this.dashboard.addWidgets(
      additionalMetricsWidget
    );

    // =========================================================================
    // Outputs
    // =========================================================================

    // Database Information
    new cdk.CfnOutput(this, 'DatabaseInstanceIdentifier', {
      description: 'RDS Database Instance Identifier',
      value: this.database.instanceIdentifier,
      exportName: `${this.stackName}-DatabaseInstanceId`,
    });

    new cdk.CfnOutput(this, 'DatabaseEndpoint', {
      description: 'RDS Database Instance Endpoint',
      value: this.database.instanceEndpoint.hostname,
      exportName: `${this.stackName}-DatabaseEndpoint`,
    });

    new cdk.CfnOutput(this, 'DatabasePort', {
      description: 'RDS Database Instance Port',
      value: this.database.instanceEndpoint.port.toString(),
      exportName: `${this.stackName}-DatabasePort`,
    });

    // Monitoring Information
    new cdk.CfnOutput(this, 'SNSTopicArn', {
      description: 'SNS Topic ARN for database alerts',
      value: this.alertsTopic.topicArn,
      exportName: `${this.stackName}-SNSTopicArn`,
    });

    new cdk.CfnOutput(this, 'CloudWatchDashboardURL', {
      description: 'URL to the CloudWatch Dashboard',
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.stackName}-DatabaseMonitoring`,
    });

    // Enhanced Monitoring Information
    if (enhancedMonitoringRole) {
      new cdk.CfnOutput(this, 'EnhancedMonitoringRoleArn', {
        description: 'IAM Role ARN for Enhanced Monitoring',
        value: enhancedMonitoringRole.roleArn,
        exportName: `${this.stackName}-EnhancedMonitoringRoleArn`,
      });
    }

    // Performance Insights Information
    new cdk.CfnOutput(this, 'PerformanceInsightsEnabled', {
      description: 'Whether Performance Insights is enabled',
      value: enablePerformanceInsights ? 'Enabled' : 'Disabled',
    });

    // Security Information
    new cdk.CfnOutput(this, 'DatabaseSecurityGroupId', {
      description: 'Security Group ID for the database',
      value: databaseSecurityGroup.securityGroupId,
      exportName: `${this.stackName}-DatabaseSecurityGroupId`,
    });

    new cdk.CfnOutput(this, 'VPCId', {
      description: 'VPC ID where database is deployed',
      value: vpc.vpcId,
      exportName: `${this.stackName}-VPCId`,
    });

    // Cost Information
    new cdk.CfnOutput(this, 'EstimatedMonthlyCost', {
      description: 'Estimated monthly cost for this solution',
      value: `Database: ${config.databaseInstanceClass} ~$15-25/month, Enhanced Monitoring: ~$2.50/month (if enabled), Performance Insights: Free for 7 days retention, CloudWatch: $0.30 per alarm + dashboard costs`,
    });

    // Next Steps
    new cdk.CfnOutput(this, 'PostDeploymentSteps', {
      description: 'Next steps after deployment',
      value: '1. Confirm SNS email subscription in your inbox, 2. Access CloudWatch Dashboard using the provided URL, 3. Connect to database using provided endpoint and credentials, 4. Generate sample workload to test monitoring and alerts, 5. Review and adjust alarm thresholds based on your workload',
    });
  }
}