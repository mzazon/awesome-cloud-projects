import * as cdk from 'aws-cdk-lib';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatch_actions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * Properties for the MonitoringStack
 */
export interface MonitoringStackProps extends cdk.StackProps {
  /** Project name for resource naming */
  projectName: string;
  /** Primary region Transit Gateway ID */
  primaryTransitGatewayId: string;
  /** Secondary region Transit Gateway ID */
  secondaryTransitGatewayId: string;
  /** Primary region name */
  primaryRegion: string;
  /** Secondary region name */
  secondaryRegion: string;
}

/**
 * Monitoring Stack for Multi-Region Transit Gateway
 * 
 * This stack creates comprehensive monitoring and alerting for the multi-region
 * Transit Gateway architecture, including:
 * - CloudWatch dashboards for both regions
 * - Metrics for data transfer, packet drops, and attachment status
 * - Alarms for critical network issues
 * - SNS notifications for operational alerts
 * - Log groups for Transit Gateway Flow Logs (optional)
 * 
 * The monitoring provides visibility into network performance, costs,
 * and potential issues across the multi-region deployment.
 */
export class MonitoringStack extends cdk.Stack {
  /** CloudWatch dashboard for multi-region monitoring */
  public readonly dashboard: cloudwatch.Dashboard;
  
  /** SNS topic for operational alerts */
  public readonly alertTopic: sns.Topic;

  constructor(scope: Construct, id: string, props: MonitoringStackProps) {
    super(scope, id, props);

    // Create SNS topic for operational alerts
    this.alertTopic = new sns.Topic(this, 'AlertTopic', {
      topicName: `${props.projectName}-tgw-alerts`,
      displayName: 'Multi-Region Transit Gateway Alerts',
      description: 'Notifications for Transit Gateway operational issues'
    });

    // Optionally add email subscription (configure via environment variable)
    const alertEmail = process.env.ALERT_EMAIL;
    if (alertEmail) {
      this.alertTopic.addSubscription(
        new subscriptions.EmailSubscription(alertEmail)
      );
    }

    // Create CloudWatch dashboard
    this.dashboard = new cloudwatch.Dashboard(this, 'Dashboard', {
      dashboardName: `${props.projectName}-tgw-dashboard`,
      defaultInterval: cdk.Duration.hours(24)
    });

    // Add primary region Transit Gateway metrics
    this.addTransitGatewayMetrics(props.primaryTransitGatewayId, props.primaryRegion, 'Primary');
    
    // Add secondary region Transit Gateway metrics
    this.addTransitGatewayMetrics(props.secondaryTransitGatewayId, props.secondaryRegion, 'Secondary');

    // Add cross-region data transfer metrics
    this.addCrossRegionMetrics(props);

    // Add cost monitoring widgets
    this.addCostMonitoringWidgets(props);

    // Create alarms for critical metrics
    this.createAlarms(props);

    // Create log group for Transit Gateway Flow Logs (optional)
    const flowLogsGroup = new logs.LogGroup(this, 'FlowLogsGroup', {
      logGroupName: `/aws/transitgateway/${props.projectName}/flowlogs`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Create CloudFormation outputs
    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${props.primaryRegion}.console.aws.amazon.com/cloudwatch/home?region=${props.primaryRegion}#dashboards:name=${this.dashboard.dashboardName}`,
      description: 'CloudWatch Dashboard URL for Transit Gateway monitoring'
    });

    new cdk.CfnOutput(this, 'AlertTopicArn', {
      value: this.alertTopic.topicArn,
      description: 'SNS Topic ARN for Transit Gateway alerts'
    });

    new cdk.CfnOutput(this, 'FlowLogsGroupName', {
      value: flowLogsGroup.logGroupName,
      description: 'CloudWatch Log Group for Transit Gateway Flow Logs'
    });

    // Add tags for resource management
    cdk.Tags.of(this).add('Component', 'monitoring');
  }

  /**
   * Add Transit Gateway metrics widgets to the dashboard
   */
  private addTransitGatewayMetrics(transitGatewayId: string, region: string, regionName: string): void {
    // Data transfer metrics
    const dataTransferWidget = new cloudwatch.GraphWidget({
      title: `${regionName} Region - Data Transfer`,
      region: region,
      width: 12,
      height: 6,
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/TransitGateway',
          metricName: 'BytesIn',
          dimensionsMap: {
            TransitGateway: transitGatewayId
          },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
          region: region,
          label: 'Bytes In'
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/TransitGateway',
          metricName: 'BytesOut',
          dimensionsMap: {
            TransitGateway: transitGatewayId
          },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
          region: region,
          label: 'Bytes Out'
        })
      ]
    });

    // Packet metrics
    const packetWidget = new cloudwatch.GraphWidget({
      title: `${regionName} Region - Packet Metrics`,
      region: region,
      width: 12,
      height: 6,
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/TransitGateway',
          metricName: 'PacketsIn',
          dimensionsMap: {
            TransitGateway: transitGatewayId
          },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
          region: region,
          label: 'Packets In'
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/TransitGateway',
          metricName: 'PacketsOut',
          dimensionsMap: {
            TransitGateway: transitGatewayId
          },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
          region: region,
          label: 'Packets Out'
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/TransitGateway',
          metricName: 'PacketDropCount',
          dimensionsMap: {
            TransitGateway: transitGatewayId
          },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
          region: region,
          label: 'Packet Drops'
        })
      ]
    });

    this.dashboard.addWidgets(dataTransferWidget, packetWidget);
  }

  /**
   * Add cross-region specific metrics
   */
  private addCrossRegionMetrics(props: MonitoringStackProps): void {
    // Cross-region bandwidth comparison
    const crossRegionWidget = new cloudwatch.GraphWidget({
      title: 'Cross-Region Data Transfer Comparison',
      width: 24,
      height: 6,
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/TransitGateway',
          metricName: 'BytesOut',
          dimensionsMap: {
            TransitGateway: props.primaryTransitGatewayId
          },
          statistic: 'Sum',
          period: cdk.Duration.hours(1),
          region: props.primaryRegion,
          label: `${props.primaryRegion} Bytes Out`
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/TransitGateway',
          metricName: 'BytesOut',
          dimensionsMap: {
            TransitGateway: props.secondaryTransitGatewayId
          },
          statistic: 'Sum',
          period: cdk.Duration.hours(1),
          region: props.secondaryRegion,
          label: `${props.secondaryRegion} Bytes Out`
        })
      ]
    });

    this.dashboard.addWidgets(crossRegionWidget);
  }

  /**
   * Add cost monitoring widgets
   */
  private addCostMonitoringWidgets(props: MonitoringStackProps): void {
    // Text widget with cost information
    const costInfoWidget = new cloudwatch.TextWidget({
      markdown: `
# Transit Gateway Cost Information

## Primary Costs to Monitor:
- **Attachment Fees**: $0.05/hour per VPC attachment
- **Data Processing**: $0.02 per GB processed
- **Cross-Region Data Transfer**: $0.02 per GB between regions

## Cost Optimization Tips:
- Monitor data transfer patterns using the metrics above
- Consider VPC endpoints for AWS services to reduce data transfer
- Use Transit Gateway route tables to control traffic flow
- Review attachment utilization regularly

## Current Configuration:
- **Primary Region**: ${props.primaryRegion}
- **Secondary Region**: ${props.secondaryRegion}
- **Estimated Monthly Cost**: $300-500 (depending on usage)
`,
      width: 24,
      height: 8
    });

    this.dashboard.addWidgets(costInfoWidget);
  }

  /**
   * Create CloudWatch alarms for critical metrics
   */
  private createAlarms(props: MonitoringStackProps): void {
    // High packet drop alarm for primary region
    const primaryPacketDropAlarm = new cloudwatch.Alarm(this, 'PrimaryPacketDropAlarm', {
      alarmName: `${props.projectName}-primary-packet-drops`,
      alarmDescription: 'High packet drop count in primary Transit Gateway',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/TransitGateway',
        metricName: 'PacketDropCount',
        dimensionsMap: {
          TransitGateway: props.primaryTransitGatewayId
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
        region: props.primaryRegion
      }),
      threshold: 1000,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    primaryPacketDropAlarm.addAlarmAction(
      new cloudwatch_actions.SnsAction(this.alertTopic)
    );

    // High packet drop alarm for secondary region
    const secondaryPacketDropAlarm = new cloudwatch.Alarm(this, 'SecondaryPacketDropAlarm', {
      alarmName: `${props.projectName}-secondary-packet-drops`,
      alarmDescription: 'High packet drop count in secondary Transit Gateway',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/TransitGateway',
        metricName: 'PacketDropCount',
        dimensionsMap: {
          TransitGateway: props.secondaryTransitGatewayId
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
        region: props.secondaryRegion
      }),
      threshold: 1000,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    secondaryPacketDropAlarm.addAlarmAction(
      new cloudwatch_actions.SnsAction(this.alertTopic)
    );

    // High data transfer alarm (cost monitoring)
    const highDataTransferAlarm = new cloudwatch.Alarm(this, 'HighDataTransferAlarm', {
      alarmName: `${props.projectName}-high-data-transfer`,
      alarmDescription: 'High data transfer indicating potential cost issues',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/TransitGateway',
        metricName: 'BytesOut',
        dimensionsMap: {
          TransitGateway: props.primaryTransitGatewayId
        },
        statistic: 'Sum',
        period: cdk.Duration.hours(1),
        region: props.primaryRegion
      }),
      threshold: 100 * 1024 * 1024 * 1024, // 100 GB per hour
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    highDataTransferAlarm.addAlarmAction(
      new cloudwatch_actions.SnsAction(this.alertTopic)
    );
  }
}

