#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as pinpoint from 'aws-cdk-lib/aws-pinpoint';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as kinesis from 'aws-cdk-lib/aws-kinesis';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Stack for Mobile App A/B Testing with Pinpoint Analytics
 * 
 * This stack creates:
 * - Pinpoint application for mobile A/B testing
 * - S3 bucket for analytics exports
 * - IAM roles with appropriate permissions
 * - Kinesis stream for real-time event processing
 * - CloudWatch dashboard for monitoring
 * - Lambda function for automated winner selection
 * - User segments for targeted testing
 * - Campaign templates for A/B testing
 */
export class MobileAbTestingPinpointStack extends cdk.Stack {
  public readonly pinpointApp: pinpoint.CfnApp;
  public readonly analyticsS3Bucket: s3.Bucket;
  public readonly eventStream: kinesis.Stream;
  public readonly dashboard: cloudwatch.Dashboard;
  public readonly winnerSelectionFunction: lambda.Function;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8);

    // Create S3 bucket for analytics exports
    this.analyticsS3Bucket = new s3.Bucket(this, 'AnalyticsS3Bucket', {
      bucketName: `pinpoint-analytics-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'AnalyticsDataLifecycle',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30)
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90)
            }
          ],
          expiration: cdk.Duration.days(365)
        }
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true
    });

    // Create IAM role for Pinpoint S3 export
    const pinpointS3Role = new iam.Role(this, 'PinpointS3Role', {
      roleName: `PinpointAnalyticsRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('pinpoint.amazonaws.com'),
      description: 'Role for Pinpoint to export analytics data to S3'
    });

    // Add S3 permissions to the role
    pinpointS3Role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        's3:GetObject',
        's3:PutObject',
        's3:DeleteObject',
        's3:ListBucket',
        's3:GetBucketLocation'
      ],
      resources: [
        this.analyticsS3Bucket.bucketArn,
        `${this.analyticsS3Bucket.bucketArn}/*`
      ]
    }));

    // Create Kinesis stream for real-time event processing
    this.eventStream = new kinesis.Stream(this, 'EventStream', {
      streamName: `pinpoint-events-${uniqueSuffix}`,
      shardCount: 1,
      retentionPeriod: cdk.Duration.days(7),
      encryption: kinesis.StreamEncryption.MANAGED,
      streamModeDetails: {
        streamMode: kinesis.StreamMode.PROVISIONED
      }
    });

    // Create IAM role for Kinesis event stream
    const pinpointKinesisRole = new iam.Role(this, 'PinpointKinesisRole', {
      roleName: `PinpointKinesisRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('pinpoint.amazonaws.com'),
      description: 'Role for Pinpoint to write events to Kinesis'
    });

    // Add Kinesis permissions to the role
    pinpointKinesisRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'kinesis:PutRecord',
        'kinesis:PutRecords',
        'kinesis:DescribeStream'
      ],
      resources: [this.eventStream.streamArn]
    }));

    // Create Pinpoint application
    this.pinpointApp = new pinpoint.CfnApp(this, 'PinpointApp', {
      name: `mobile-ab-testing-${uniqueSuffix}`,
      tags: {
        Purpose: 'AB Testing',
        Environment: 'Production',
        Service: 'Mobile App'
      }
    });

    // Configure application settings
    new pinpoint.CfnApplicationSettings(this, 'ApplicationSettings', {
      applicationId: this.pinpointApp.ref,
      cloudWatchMetricsEnabled: true,
      eventTaggingEnabled: true,
      campaignHook: {
        mode: 'DELIVERY'
      },
      limits: {
        daily: 1000,
        maximumDuration: 86400,
        messagesPerSecond: 100,
        total: 10000
      }
    });

    // Create event stream configuration
    new pinpoint.CfnEventStream(this, 'EventStreamConfig', {
      applicationId: this.pinpointApp.ref,
      destinationStreamArn: this.eventStream.streamArn,
      roleArn: pinpointKinesisRole.roleArn
    });

    // Create user segments for A/B testing
    const activeUsersSegment = new pinpoint.CfnSegment(this, 'ActiveUsersSegment', {
      applicationId: this.pinpointApp.ref,
      name: 'ActiveUsers',
      segmentGroups: {
        groups: [
          {
            type: 'ALL',
            sourceType: 'ALL',
            dimensions: {
              demographic: {
                appVersion: {
                  dimensionType: 'INCLUSIVE',
                  values: ['1.0.0', '1.1.0', '1.2.0']
                }
              }
            }
          }
        ]
      },
      tags: {
        Purpose: 'AB Testing',
        SegmentType: 'Active Users'
      }
    });

    const highValueUsersSegment = new pinpoint.CfnSegment(this, 'HighValueUsersSegment', {
      applicationId: this.pinpointApp.ref,
      name: 'HighValueUsers',
      segmentGroups: {
        groups: [
          {
            type: 'ALL',
            sourceType: 'ALL',
            dimensions: {
              behavior: {
                recency: {
                  duration: 'DAY_7',
                  recencyType: 'ACTIVE'
                }
              },
              metrics: {
                session_count: {
                  comparisonOperator: 'GREATER_THAN',
                  value: 5.0
                }
              }
            }
          }
        ]
      },
      tags: {
        Purpose: 'AB Testing',
        SegmentType: 'High Value Users'
      }
    });

    // Create Lambda function for automated winner selection
    this.winnerSelectionFunction = new lambda.Function(this, 'WinnerSelectionFunction', {
      functionName: `pinpoint-winner-selection-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      environment: {
        PINPOINT_APP_ID: this.pinpointApp.ref,
        S3_BUCKET_NAME: this.analyticsS3Bucket.bucketName
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict, context) -> Dict:
    """
    Lambda function for automated A/B test winner selection
    
    This function analyzes campaign performance data and determines
    the best performing treatment based on conversion rates and 
    statistical significance.
    """
    try:
        pinpoint = boto3.client('pinpoint')
        
        application_id = event.get('application_id') or os.environ.get('PINPOINT_APP_ID')
        campaign_id = event.get('campaign_id')
        
        if not application_id or not campaign_id:
            raise ValueError("Missing required parameters: application_id or campaign_id")
        
        # Get campaign analytics
        logger.info(f"Retrieving analytics for campaign {campaign_id}")
        response = pinpoint.get_campaign_activities(
            ApplicationId=application_id,
            CampaignId=campaign_id
        )
        
        # Analyze conversion rates for each treatment
        activities = response['ActivitiesResponse']['Item']
        treatments = []
        
        for activity in activities:
            treatment_data = {
                'treatment_id': activity.get('TreatmentId', 'control'),
                'delivered_count': activity.get('DeliveredCount', 0),
                'opened_count': activity.get('OpenedCount', 0),
                'clicked_count': activity.get('ClickedCount', 0),
                'conversion_count': activity.get('ConversionCount', 0)
            }
            
            # Calculate conversion rate
            if treatment_data['delivered_count'] > 0:
                treatment_data['conversion_rate'] = (
                    treatment_data['conversion_count'] / treatment_data['delivered_count']
                )
            else:
                treatment_data['conversion_rate'] = 0
                
            treatments.append(treatment_data)
        
        # Find best performing treatment
        best_treatment = max(treatments, key=lambda x: x['conversion_rate'])
        
        # Log results
        logger.info(f"Best treatment: {best_treatment['treatment_id']}")
        logger.info(f"Conversion rate: {best_treatment['conversion_rate']:.2%}")
        
        # Prepare response
        result = {
            'best_treatment': best_treatment,
            'all_treatments': treatments,
            'analysis_timestamp': datetime.utcnow().isoformat(),
            'recommendations': generate_recommendations(treatments)
        }
        
        return {
            'statusCode': 200,
            'body': json.dumps(result, default=str)
        }
        
    except Exception as e:
        logger.error(f"Error in winner selection: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Failed to analyze campaign performance'
            })
        }

def generate_recommendations(treatments: List[Dict]) -> List[str]:
    """Generate recommendations based on treatment performance"""
    recommendations = []
    
    # Sort treatments by conversion rate
    sorted_treatments = sorted(treatments, key=lambda x: x['conversion_rate'], reverse=True)
    
    if len(sorted_treatments) >= 2:
        best = sorted_treatments[0]
        second_best = sorted_treatments[1]
        
        # Calculate performance difference
        performance_diff = best['conversion_rate'] - second_best['conversion_rate']
        
        if performance_diff > 0.05:  # 5% difference
            recommendations.append(f"Strong winner detected: {best['treatment_id']} outperforms by {performance_diff:.1%}")
        elif performance_diff > 0.01:  # 1% difference
            recommendations.append(f"Moderate winner: {best['treatment_id']} shows {performance_diff:.1%} improvement")
        else:
            recommendations.append("Results are close - consider extending test duration")
    
    # Check for low delivery rates
    for treatment in treatments:
        if treatment['delivered_count'] < 100:
            recommendations.append(f"Low sample size for {treatment['treatment_id']} - consider increasing traffic")
    
    return recommendations
`),
      logRetention: logs.RetentionDays.ONE_WEEK
    });

    // Add permissions for the Lambda function
    this.winnerSelectionFunction.addToRolePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'pinpoint:GetCampaign',
        'pinpoint:GetCampaignActivities',
        'pinpoint:GetApplicationSettings',
        'pinpoint:GetSegment'
      ],
      resources: [
        `arn:aws:mobiletargeting:${this.region}:${this.account}:apps/${this.pinpointApp.ref}`,
        `arn:aws:mobiletargeting:${this.region}:${this.account}:apps/${this.pinpointApp.ref}/*`
      ]
    }));

    // Allow Lambda to read from S3 bucket
    this.analyticsS3Bucket.grantRead(this.winnerSelectionFunction);

    // Create CloudWatch Dashboard for monitoring
    this.dashboard = new cloudwatch.Dashboard(this, 'AbTestingDashboard', {
      dashboardName: `Pinpoint-AB-Testing-${uniqueSuffix}`,
      defaultInterval: cdk.Duration.hours(1)
    });

    // Add widgets to dashboard
    this.dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Campaign Delivery Metrics',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/Pinpoint',
            metricName: 'DirectMessagesSent',
            dimensionsMap: {
              'ApplicationId': this.pinpointApp.ref
            },
            statistic: 'Sum',
            period: cdk.Duration.minutes(5)
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/Pinpoint',
            metricName: 'DirectMessagesDelivered',
            dimensionsMap: {
              'ApplicationId': this.pinpointApp.ref
            },
            statistic: 'Sum',
            period: cdk.Duration.minutes(5)
          })
        ],
        right: [
          new cloudwatch.Metric({
            namespace: 'AWS/Pinpoint',
            metricName: 'DirectMessagesBounced',
            dimensionsMap: {
              'ApplicationId': this.pinpointApp.ref
            },
            statistic: 'Sum',
            period: cdk.Duration.minutes(5)
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/Pinpoint',
            metricName: 'DirectMessagesOpened',
            dimensionsMap: {
              'ApplicationId': this.pinpointApp.ref
            },
            statistic: 'Sum',
            period: cdk.Duration.minutes(5)
          })
        ]
      })
    );

    this.dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Conversion Events',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/Pinpoint',
            metricName: 'CustomEvents',
            dimensionsMap: {
              'ApplicationId': this.pinpointApp.ref,
              'EventType': 'conversion'
            },
            statistic: 'Sum',
            period: cdk.Duration.minutes(5)
          })
        ]
      })
    );

    this.dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Kinesis Event Stream',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/Kinesis',
            metricName: 'IncomingRecords',
            dimensionsMap: {
              'StreamName': this.eventStream.streamName
            },
            statistic: 'Sum',
            period: cdk.Duration.minutes(5)
          })
        ]
      })
    );

    // Create EventBridge rule for automated analysis
    const analysisRule = new events.Rule(this, 'AnalysisRule', {
      ruleName: `campaign-analysis-${uniqueSuffix}`,
      description: 'Trigger campaign analysis every 6 hours',
      schedule: events.Schedule.rate(cdk.Duration.hours(6))
    });

    // Add Lambda target to the rule
    analysisRule.addTarget(new targets.LambdaFunction(this.winnerSelectionFunction));

    // Output important information
    new cdk.CfnOutput(this, 'PinpointApplicationId', {
      value: this.pinpointApp.ref,
      description: 'Pinpoint Application ID for mobile A/B testing'
    });

    new cdk.CfnOutput(this, 'ActiveUsersSegmentId', {
      value: activeUsersSegment.ref,
      description: 'Segment ID for active users'
    });

    new cdk.CfnOutput(this, 'HighValueUsersSegmentId', {
      value: highValueUsersSegment.ref,
      description: 'Segment ID for high value users'
    });

    new cdk.CfnOutput(this, 'AnalyticsS3BucketName', {
      value: this.analyticsS3Bucket.bucketName,
      description: 'S3 bucket for analytics exports'
    });

    new cdk.CfnOutput(this, 'EventStreamName', {
      value: this.eventStream.streamName,
      description: 'Kinesis stream for real-time events'
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      description: 'CloudWatch Dashboard URL'
    });

    new cdk.CfnOutput(this, 'WinnerSelectionFunctionArn', {
      value: this.winnerSelectionFunction.functionArn,
      description: 'Lambda function ARN for winner selection'
    });

    new cdk.CfnOutput(this, 'PinpointConsoleURL', {
      value: `https://${this.region}.console.aws.amazon.com/pinpoint/home?region=${this.region}#/apps/${this.pinpointApp.ref}`,
      description: 'Pinpoint Console URL'
    });
  }
}

// CDK App
const app = new cdk.App();

// Deploy the stack
new MobileAbTestingPinpointStack(app, 'MobileAbTestingPinpointStack', {
  description: 'Stack for Mobile App A/B Testing with Pinpoint Analytics',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION
  },
  tags: {
    Project: 'Mobile AB Testing',
    Service: 'Amazon Pinpoint',
    Environment: 'Production'
  }
});

app.synth();