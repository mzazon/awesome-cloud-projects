#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as iotsitewise from 'aws-cdk-lib/aws-iotsitewise';
import * as timestream from 'aws-cdk-lib/aws-timestream';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Props for the Industrial IoT Data Collection Stack
 */
export interface IndustrialIoTDataCollectionStackProps extends cdk.StackProps {
  /**
   * The name of the manufacturing project
   * @default 'manufacturing-plant'
   */
  readonly projectName?: string;
  
  /**
   * The name of the Timestream database
   * @default 'industrial-data'
   */
  readonly timestreamDatabaseName?: string;

  /**
   * The environment for the deployment (dev, staging, prod)
   * @default 'dev'
   */
  readonly environment?: string;

  /**
   * Enable CloudWatch monitoring and alarms
   * @default true
   */
  readonly enableCloudWatchMonitoring?: boolean;

  /**
   * Temperature threshold for alerts in Celsius
   * @default 80.0
   */
  readonly temperatureThreshold?: number;

  /**
   * Pressure threshold for alerts in PSI
   * @default 60.0
   */
  readonly pressureThreshold?: number;
}

/**
 * CDK Stack for Industrial IoT Data Collection with AWS IoT SiteWise
 * 
 * This stack creates:
 * - IoT SiteWise Asset Model for production line equipment
 * - IoT SiteWise Asset instance representing actual equipment
 * - Amazon Timestream database for time-series data storage
 * - CloudWatch alarms for equipment monitoring
 * - SNS topic for equipment alerts
 * - Lambda function for data processing (optional)
 */
export class IndustrialIoTDataCollectionStack extends cdk.Stack {
  public readonly assetModel: iotsitewise.CfnAssetModel;
  public readonly asset: iotsitewise.CfnAsset;
  public readonly timestreamDatabase: timestream.CfnDatabase;
  public readonly timestreamTable: timestream.CfnTable;
  public readonly alertTopic: sns.Topic;
  public readonly temperatureAlarm: cloudwatch.Alarm;
  public readonly pressureAlarm: cloudwatch.Alarm;
  public readonly dataProcessingLambda?: lambda.Function;

  constructor(scope: Construct, id: string, props: IndustrialIoTDataCollectionStackProps = {}) {
    super(scope, id, props);

    // Configuration with defaults
    const projectName = props.projectName || 'manufacturing-plant';
    const timestreamDatabaseName = props.timestreamDatabaseName || 'industrial-data';
    const environment = props.environment || 'dev';
    const enableCloudWatchMonitoring = props.enableCloudWatchMonitoring ?? true;
    const temperatureThreshold = props.temperatureThreshold || 80.0;
    const pressureThreshold = props.pressureThreshold || 60.0;

    // Add random suffix to ensure uniqueness
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // Create IoT SiteWise Asset Model for production line equipment
    this.assetModel = new iotsitewise.CfnAssetModel(this, 'ProductionLineAssetModel', {
      assetModelName: 'ProductionLineEquipment',
      assetModelDescription: 'Asset model for production line machinery with temperature, pressure, and efficiency metrics',
      assetModelProperties: [
        {
          name: 'Temperature',
          dataType: 'DOUBLE',
          unit: 'Celsius',
          type: {
            measurement: {}
          }
        },
        {
          name: 'Pressure',
          dataType: 'DOUBLE',
          unit: 'PSI',
          type: {
            measurement: {}
          }
        },
        {
          name: 'OperationalEfficiency',
          dataType: 'DOUBLE',
          unit: 'Percent',
          type: {
            transform: {
              expression: '(temp / 100) * (pressure / 50) * 100',
              variables: [
                {
                  name: 'temp',
                  value: {
                    propertyLogicalId: 'Temperature'
                  }
                },
                {
                  name: 'pressure',
                  value: {
                    propertyLogicalId: 'Pressure'
                  }
                }
              ]
            }
          }
        }
      ],
      tags: [
        {
          key: 'Environment',
          value: environment
        },
        {
          key: 'Project',
          value: projectName
        },
        {
          key: 'Service',
          value: 'IoT-SiteWise'
        }
      ]
    });

    // Create IoT SiteWise Asset instance representing actual equipment
    this.asset = new iotsitewise.CfnAsset(this, 'ProductionLineAsset', {
      assetName: `ProductionLine-A-Pump-001-${uniqueSuffix}`,
      assetModelId: this.assetModel.attrAssetModelId,
      assetDescription: 'Production line pump equipment asset for manufacturing facility',
      tags: [
        {
          key: 'Environment',
          value: environment
        },
        {
          key: 'Project',
          value: projectName
        },
        {
          key: 'AssetType',
          value: 'Pump'
        },
        {
          key: 'Location',
          value: 'ProductionLine-A'
        }
      ]
    });

    // Create Amazon Timestream database for time-series data storage
    this.timestreamDatabase = new timestream.CfnDatabase(this, 'IndustrialDataDatabase', {
      databaseName: `${timestreamDatabaseName}-${uniqueSuffix}`,
      tags: [
        {
          key: 'Environment',
          value: environment
        },
        {
          key: 'Project',
          value: projectName
        },
        {
          key: 'Service',
          value: 'Timestream'
        }
      ]
    });

    // Create Timestream table for equipment metrics
    this.timestreamTable = new timestream.CfnTable(this, 'EquipmentMetricsTable', {
      databaseName: this.timestreamDatabase.ref,
      tableName: 'equipment-metrics',
      retentionProperties: {
        memoryStoreRetentionPeriodInHours: 24,
        magneticStoreRetentionPeriodInDays: 365
      },
      tags: [
        {
          key: 'Environment',
          value: environment
        },
        {
          key: 'Project',
          value: projectName
        },
        {
          key: 'DataType',
          value: 'EquipmentMetrics'
        }
      ]
    });

    // Create SNS topic for equipment alerts
    this.alertTopic = new sns.Topic(this, 'EquipmentAlertsTopic', {
      topicName: `equipment-alerts-${uniqueSuffix}`,
      displayName: 'Equipment Alerts Topic',
      description: 'SNS topic for industrial equipment alerts and notifications'
    });

    // Apply tags to SNS topic
    cdk.Tags.of(this.alertTopic).add('Environment', environment);
    cdk.Tags.of(this.alertTopic).add('Project', projectName);
    cdk.Tags.of(this.alertTopic).add('Service', 'SNS');

    // Create CloudWatch monitoring and alarms if enabled
    if (enableCloudWatchMonitoring) {
      // Create CloudWatch alarm for high temperature
      this.temperatureAlarm = new cloudwatch.Alarm(this, 'HighTemperatureAlarm', {
        alarmName: `${projectName}-HighTemperature-${uniqueSuffix}`,
        alarmDescription: 'Alert when equipment temperature exceeds threshold',
        metric: new cloudwatch.Metric({
          namespace: 'AWS/IoTSiteWise',
          metricName: 'Temperature',
          dimensionsMap: {
            AssetId: this.asset.attrAssetId
          },
          statistic: 'Average',
          period: cdk.Duration.minutes(5)
        }),
        threshold: temperatureThreshold,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        evaluationPeriods: 2,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
      });

      // Add SNS action to temperature alarm
      this.temperatureAlarm.addAlarmAction(
        new cloudwatchActions.SnsAction(this.alertTopic)
      );

      // Create CloudWatch alarm for high pressure
      this.pressureAlarm = new cloudwatch.Alarm(this, 'HighPressureAlarm', {
        alarmName: `${projectName}-HighPressure-${uniqueSuffix}`,
        alarmDescription: 'Alert when equipment pressure exceeds threshold',
        metric: new cloudwatch.Metric({
          namespace: 'AWS/IoTSiteWise',
          metricName: 'Pressure',
          dimensionsMap: {
            AssetId: this.asset.attrAssetId
          },
          statistic: 'Average',
          period: cdk.Duration.minutes(5)
        }),
        threshold: pressureThreshold,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        evaluationPeriods: 2,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
      });

      // Add SNS action to pressure alarm
      this.pressureAlarm.addAlarmAction(
        new cloudwatchActions.SnsAction(this.alertTopic)
      );

      // Create Lambda function for data processing (optional)
      this.dataProcessingLambda = new lambda.Function(this, 'DataProcessingFunction', {
        functionName: `${projectName}-data-processing-${uniqueSuffix}`,
        runtime: lambda.Runtime.PYTHON_3_9,
        handler: 'index.handler',
        description: 'Lambda function for processing industrial IoT data from SiteWise',
        timeout: cdk.Duration.minutes(5),
        memorySize: 512,
        environment: {
          TIMESTREAM_DATABASE: this.timestreamDatabase.ref,
          TIMESTREAM_TABLE: this.timestreamTable.ref,
          ASSET_ID: this.asset.attrAssetId,
          SNS_TOPIC_ARN: this.alertTopic.topicArn
        },
        logRetention: logs.RetentionDays.ONE_WEEK,
        code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime

def handler(event, context):
    """
    Process IoT SiteWise data and perform analytics
    """
    timestream_client = boto3.client('timestream-write')
    sns_client = boto3.client('sns')
    
    database_name = os.environ['TIMESTREAM_DATABASE']
    table_name = os.environ['TIMESTREAM_TABLE']
    asset_id = os.environ['ASSET_ID']
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    
    try:
        # Process incoming IoT SiteWise data
        print(f"Processing data for asset: {asset_id}")
        
        # Example: Extract temperature and pressure from event
        if 'Records' in event:
            for record in event['Records']:
                # Process each record
                print(f"Processing record: {record}")
        
        # Example: Write processed data to Timestream
        # This would be customized based on your specific data processing needs
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Data processed successfully',
                'asset_id': asset_id,
                'timestamp': datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        print(f"Error processing data: {str(e)}")
        
        # Send alert to SNS on error
        sns_client.publish(
            TopicArn=sns_topic_arn,
            Message=f"Error processing industrial IoT data: {str(e)}",
            Subject="Industrial IoT Data Processing Error"
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }
        `)
      });

      // Grant Lambda permissions to access Timestream
      this.dataProcessingLambda.addToRolePolicy(
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'timestream:WriteRecords',
            'timestream:Select',
            'timestream:DescribeTable',
            'timestream:DescribeDatabase'
          ],
          resources: [
            this.timestreamDatabase.attrArn,
            this.timestreamTable.attrArn
          ]
        })
      );

      // Grant Lambda permissions to access IoT SiteWise
      this.dataProcessingLambda.addToRolePolicy(
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'iotsitewise:GetAssetPropertyValue',
            'iotsitewise:GetAssetPropertyValueHistory',
            'iotsitewise:BatchGetAssetPropertyValue',
            'iotsitewise:BatchGetAssetPropertyValueHistory'
          ],
          resources: [
            `arn:aws:iotsitewise:${this.region}:${this.account}:asset/${this.asset.attrAssetId}`
          ]
        })
      );

      // Grant Lambda permissions to publish to SNS
      this.alertTopic.grantPublish(this.dataProcessingLambda);

      // Apply tags to Lambda function
      cdk.Tags.of(this.dataProcessingLambda).add('Environment', environment);
      cdk.Tags.of(this.dataProcessingLambda).add('Project', projectName);
      cdk.Tags.of(this.dataProcessingLambda).add('Service', 'Lambda');
    }

    // Create CloudWatch dashboard for monitoring
    if (enableCloudWatchMonitoring) {
      const dashboard = new cloudwatch.Dashboard(this, 'IndustrialIoTDashboard', {
        dashboardName: `${projectName}-industrial-iot-dashboard-${uniqueSuffix}`,
        widgets: [
          [
            new cloudwatch.GraphWidget({
              title: 'Equipment Temperature',
              left: [
                new cloudwatch.Metric({
                  namespace: 'AWS/IoTSiteWise',
                  metricName: 'Temperature',
                  dimensionsMap: {
                    AssetId: this.asset.attrAssetId
                  },
                  statistic: 'Average',
                  period: cdk.Duration.minutes(5)
                })
              ],
              width: 12,
              height: 6
            }),
            new cloudwatch.GraphWidget({
              title: 'Equipment Pressure',
              left: [
                new cloudwatch.Metric({
                  namespace: 'AWS/IoTSiteWise',
                  metricName: 'Pressure',
                  dimensionsMap: {
                    AssetId: this.asset.attrAssetId
                  },
                  statistic: 'Average',
                  period: cdk.Duration.minutes(5)
                })
              ],
              width: 12,
              height: 6
            })
          ],
          [
            new cloudwatch.GraphWidget({
              title: 'Operational Efficiency',
              left: [
                new cloudwatch.Metric({
                  namespace: 'Manufacturing/Efficiency',
                  metricName: 'OperationalEfficiency',
                  dimensionsMap: {
                    AssetId: this.asset.attrAssetId
                  },
                  statistic: 'Average',
                  period: cdk.Duration.minutes(5)
                })
              ],
              width: 24,
              height: 6
            })
          ]
        ]
      });

      // Apply tags to dashboard
      cdk.Tags.of(dashboard).add('Environment', environment);
      cdk.Tags.of(dashboard).add('Project', projectName);
      cdk.Tags.of(dashboard).add('Service', 'CloudWatch');
    }

    // Stack outputs
    new cdk.CfnOutput(this, 'AssetModelId', {
      value: this.assetModel.attrAssetModelId,
      description: 'IoT SiteWise Asset Model ID',
      exportName: `${this.stackName}-AssetModelId`
    });

    new cdk.CfnOutput(this, 'AssetId', {
      value: this.asset.attrAssetId,
      description: 'IoT SiteWise Asset ID',
      exportName: `${this.stackName}-AssetId`
    });

    new cdk.CfnOutput(this, 'TimestreamDatabaseName', {
      value: this.timestreamDatabase.ref,
      description: 'Timestream Database Name',
      exportName: `${this.stackName}-TimestreamDatabaseName`
    });

    new cdk.CfnOutput(this, 'TimestreamTableName', {
      value: this.timestreamTable.ref,
      description: 'Timestream Table Name',
      exportName: `${this.stackName}-TimestreamTableName`
    });

    new cdk.CfnOutput(this, 'AlertTopicArn', {
      value: this.alertTopic.topicArn,
      description: 'SNS Topic ARN for equipment alerts',
      exportName: `${this.stackName}-AlertTopicArn`
    });

    if (this.dataProcessingLambda) {
      new cdk.CfnOutput(this, 'DataProcessingLambdaArn', {
        value: this.dataProcessingLambda.functionArn,
        description: 'Lambda Function ARN for data processing',
        exportName: `${this.stackName}-DataProcessingLambdaArn`
      });
    }
  }
}

// CDK App
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const environment = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'dev';
const projectName = app.node.tryGetContext('projectName') || process.env.PROJECT_NAME || 'manufacturing-plant';
const enableCloudWatchMonitoring = app.node.tryGetContext('enableCloudWatchMonitoring') ?? true;

// Create the stack
new IndustrialIoTDataCollectionStack(app, 'IndustrialIoTDataCollectionStack', {
  description: 'Industrial IoT Data Collection with AWS IoT SiteWise, Timestream, and CloudWatch',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1'
  },
  environment,
  projectName,
  enableCloudWatchMonitoring,
  temperatureThreshold: 80.0,
  pressureThreshold: 60.0,
  tags: {
    Environment: environment,
    Project: projectName,
    Service: 'IndustrialIoT',
    ManagedBy: 'CDK'
  }
});