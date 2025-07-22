#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as iot from 'aws-cdk-lib/aws-iot';
import * as kinesis from 'aws-cdk-lib/aws-kinesis';
import * as firehose from 'aws-cdk-lib/aws-kinesisfirehose';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as glue from 'aws-cdk-lib/aws-glue';
import * as quicksight from 'aws-cdk-lib/aws-quicksight';
import * as iam from 'aws-cdk-lib/aws-iam';
import { RemovalPolicy } from 'aws-cdk-lib';

/**
 * CDK Stack for IoT Data Visualization with QuickSight
 * 
 * This stack creates a complete IoT analytics pipeline that:
 * - Collects sensor data through AWS IoT Core
 * - Processes data streams with Kinesis
 * - Stores data in S3 with intelligent partitioning
 * - Catalogs data with AWS Glue
 * - Visualizes data with Amazon QuickSight
 */
export class IoTDataVisualizationStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.tryGetContext('uniqueSuffix') || 
                        Math.random().toString(36).substring(2, 8);

    // S3 Bucket for IoT data storage with intelligent partitioning
    const iotDataBucket = new s3.Bucket(this, 'IoTDataBucket', {
      bucketName: `iot-analytics-bucket-${uniqueSuffix}`,
      versioned: false,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'iot-data-lifecycle',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            },
            {
              storageClass: s3.StorageClass.DEEP_ARCHIVE,
              transitionAfter: cdk.Duration.days(365),
            },
          ],
        },
      ],
    });

    // Kinesis Data Stream for real-time IoT data processing
    const iotDataStream = new kinesis.Stream(this, 'IoTDataStream', {
      streamName: `iot-data-stream-${uniqueSuffix}`,
      shardCount: 1,
      retentionPeriod: cdk.Duration.days(7),
      encryption: kinesis.StreamEncryption.MANAGED,
    });

    // IAM Role for IoT Rules Engine to access Kinesis
    const iotKinesisRole = new iam.Role(this, 'IoTKinesisRole', {
      roleName: `IoTKinesisRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('iot.amazonaws.com'),
      inlinePolicies: {
        KinesisAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'kinesis:PutRecord',
                'kinesis:PutRecords',
              ],
              resources: [iotDataStream.streamArn],
            }),
          ],
        }),
      },
    });

    // IAM Role for Kinesis Data Firehose to access S3
    const firehoseRole = new iam.Role(this, 'FirehoseDeliveryRole', {
      roleName: `FirehoseDeliveryRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('firehose.amazonaws.com'),
      inlinePolicies: {
        S3Access: new iam.PolicyDocument({
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
                iotDataBucket.bucketArn,
                iotDataBucket.arnForObjects('*'),
              ],
            }),
          ],
        }),
        KinesisAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'kinesis:DescribeStream',
                'kinesis:GetShardIterator',
                'kinesis:GetRecords',
                'kinesis:ListShards',
              ],
              resources: [iotDataStream.streamArn],
            }),
          ],
        }),
      },
    });

    // Kinesis Data Firehose for delivering data to S3
    const firehoseDeliveryStream = new firehose.CfnDeliveryStream(this, 'FirehoseDeliveryStream', {
      deliveryStreamName: `iot-firehose-${uniqueSuffix}`,
      deliveryStreamType: 'KinesisStreamAsSource',
      kinesisStreamSourceConfiguration: {
        kinesisStreamArn: iotDataStream.streamArn,
        roleArn: firehoseRole.roleArn,
      },
      s3DestinationConfiguration: {
        bucketArn: iotDataBucket.bucketArn,
        roleArn: firehoseRole.roleArn,
        prefix: 'iot-data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/',
        bufferingHints: {
          sizeInMBs: 1,
          intervalInSeconds: 60,
        },
        compressionFormat: 'GZIP',
        encryptionConfiguration: {
          noEncryptionConfig: 'NoEncryption',
        },
        cloudWatchLoggingOptions: {
          enabled: true,
          logGroupName: `/aws/kinesisfirehose/iot-firehose-${uniqueSuffix}`,
        },
      },
    });

    // AWS Glue Database for data cataloging
    const glueDatabase = new glue.CfnDatabase(this, 'IoTAnalyticsDatabase', {
      catalogId: this.account,
      databaseInput: {
        name: `iot_analytics_db_${uniqueSuffix.replace('-', '_')}`,
        description: 'Database for IoT sensor data analytics',
      },
    });

    // AWS Glue Table for IoT sensor data
    const glueTable = new glue.CfnTable(this, 'IoTSensorDataTable', {
      catalogId: this.account,
      databaseName: glueDatabase.ref,
      tableInput: {
        name: 'iot_sensor_data',
        description: 'Table for IoT sensor data',
        tableType: 'EXTERNAL_TABLE',
        parameters: {
          'classification': 'json',
          'compressionType': 'gzip',
          'typeOfData': 'file',
        },
        storageDescriptor: {
          columns: [
            {
              name: 'device_id',
              type: 'string',
              comment: 'IoT device identifier',
            },
            {
              name: 'temperature',
              type: 'int',
              comment: 'Temperature reading in Celsius',
            },
            {
              name: 'humidity',
              type: 'int',
              comment: 'Humidity percentage',
            },
            {
              name: 'pressure',
              type: 'int',
              comment: 'Pressure reading in hPa',
            },
            {
              name: 'timestamp',
              type: 'string',
              comment: 'Device timestamp',
            },
            {
              name: 'event_time',
              type: 'bigint',
              comment: 'Server-side timestamp',
            },
          ],
          location: `s3://${iotDataBucket.bucketName}/iot-data/`,
          inputFormat: 'org.apache.hadoop.mapred.TextInputFormat',
          outputFormat: 'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat',
          compressed: true,
          serdeInfo: {
            serializationLibrary: 'org.openx.data.jsonserde.JsonSerDe',
            parameters: {
              'paths': 'device_id,temperature,humidity,pressure,timestamp,event_time',
            },
          },
        },
        partitionKeys: [
          {
            name: 'year',
            type: 'string',
            comment: 'Year partition',
          },
          {
            name: 'month',
            type: 'string',
            comment: 'Month partition',
          },
          {
            name: 'day',
            type: 'string',
            comment: 'Day partition',
          },
          {
            name: 'hour',
            type: 'string',
            comment: 'Hour partition',
          },
        ],
      },
    });

    // IoT Thing for device representation
    const iotThing = new iot.CfnThing(this, 'IoTSensorThing', {
      thingName: `iot-sensor-${uniqueSuffix}`,
      attributePayload: {
        attributes: {
          'deviceType': 'sensor',
          'location': 'production-floor',
          'manufacturer': 'IoT-Corp',
        },
      },
    });

    // IoT Policy for device permissions
    const iotPolicy = new iot.CfnPolicy(this, 'IoTDevicePolicy', {
      policyName: `iot-device-policy-${uniqueSuffix}`,
      policyDocument: {
        Version: '2012-10-17',
        Statement: [
          {
            Effect: 'Allow',
            Action: [
              'iot:Connect',
              'iot:Publish',
            ],
            Resource: '*',
          },
        ],
      },
    });

    // IoT Topic Rule to route data to Kinesis
    const iotTopicRule = new iot.CfnTopicRule(this, 'IoTTopicRule', {
      ruleName: `RouteToKinesis_${uniqueSuffix.replace('-', '_')}`,
      topicRulePayload: {
        sql: 'SELECT *, timestamp() as event_time FROM "topic/sensor/data"',
        description: 'Route IoT sensor data to Kinesis Data Streams',
        actions: [
          {
            kinesis: {
              streamName: iotDataStream.streamName,
              roleArn: iotKinesisRole.roleArn,
            },
          },
        ],
      },
    });

    // IAM Role for QuickSight to access Athena and S3
    const quickSightRole = new iam.Role(this, 'QuickSightServiceRole', {
      roleName: `QuickSightServiceRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('quicksight.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSQuickSightAthenaAccess'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonS3ReadOnlyAccess'),
      ],
      inlinePolicies: {
        AthenaAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'athena:BatchGetQueryExecution',
                'athena:GetQueryExecution',
                'athena:GetQueryResults',
                'athena:GetWorkGroup',
                'athena:ListDatabases',
                'athena:ListDataCatalogs',
                'athena:ListTableMetadata',
                'athena:ListWorkGroups',
                'athena:StartQueryExecution',
                'athena:StopQueryExecution',
              ],
              resources: ['*'],
            }),
          ],
        }),
        GlueAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'glue:GetDatabase',
                'glue:GetDatabases',
                'glue:GetTable',
                'glue:GetTables',
                'glue:GetPartition',
                'glue:GetPartitions',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Output important resource identifiers
    new cdk.CfnOutput(this, 'IoTDataBucketName', {
      value: iotDataBucket.bucketName,
      description: 'S3 bucket name for IoT data storage',
      exportName: `IoTDataBucket-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'KinesisStreamName', {
      value: iotDataStream.streamName,
      description: 'Kinesis stream name for IoT data processing',
      exportName: `KinesisStream-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'FirehoseDeliveryStreamName', {
      value: firehoseDeliveryStream.deliveryStreamName!,
      description: 'Firehose delivery stream name',
      exportName: `FirehoseStream-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'GlueDatabaseName', {
      value: glueDatabase.ref,
      description: 'Glue database name for data cataloging',
      exportName: `GlueDatabase-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'IoTThingName', {
      value: iotThing.thingName!,
      description: 'IoT thing name for device representation',
      exportName: `IoTThing-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'IoTTopicRuleName', {
      value: iotTopicRule.ruleName!,
      description: 'IoT topic rule name for data routing',
      exportName: `IoTTopicRule-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'QuickSightDataSourceInstructions', {
      value: `Create QuickSight data source using Athena with database: ${glueDatabase.ref}`,
      description: 'Instructions for creating QuickSight data source',
    });

    // Tags for resource management and cost allocation
    cdk.Tags.of(this).add('Project', 'IoT-Analytics');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('Owner', 'DataEngineering');
    cdk.Tags.of(this).add('Purpose', 'IoT-Data-Visualization');
  }
}

// CDK App initialization
const app = new cdk.App();

// Stack deployment with environment configuration
new IoTDataVisualizationStack(app, 'IoTDataVisualizationStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'IoT Data Visualization with QuickSight - Complete analytics pipeline for IoT sensor data',
  terminationProtection: false,
});

// Synthesize the CloudFormation template
app.synth();