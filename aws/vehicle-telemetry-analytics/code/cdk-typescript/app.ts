#!/usr/bin/env node

import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as timestream from 'aws-cdk-lib/aws-timestream';
import * as grafana from 'aws-cdk-lib/aws-grafana';
import * as iot from 'aws-cdk-lib/aws-iot';

/**
 * Properties for the Vehicle Telemetry Analytics Stack
 */
interface VehicleTelemetryStackProps extends cdk.StackProps {
  /**
   * Prefix for resource names to ensure uniqueness
   * @default 'vehicle-telemetry'
   */
  readonly resourcePrefix?: string;

  /**
   * Retention period for memory store in hours
   * @default 24
   */
  readonly memoryStoreRetentionHours?: number;

  /**
   * Retention period for magnetic store in days
   * @default 30
   */
  readonly magneticStoreRetentionDays?: number;

  /**
   * Data collection interval in milliseconds
   * @default 10000
   */
  readonly collectionIntervalMs?: number;
}

/**
 * CDK Stack for Real-Time Vehicle Telemetry Analytics
 * 
 * This stack creates a comprehensive vehicle telemetry system using:
 * - AWS IoT FleetWise for standardized vehicle data collection
 * - Amazon Timestream for optimized time-series storage
 * - Amazon Managed Grafana for real-time visualization
 * - S3 for data archival and backup
 */
export class VehicleTelemetryStack extends cdk.Stack {
  public readonly timestreamDatabase: timestream.CfnDatabase;
  public readonly timestreamTable: timestream.CfnTable;
  public readonly fleetWiseRole: iam.Role;
  public readonly dataArchiveBucket: s3.Bucket;
  public readonly grafanaWorkspace: grafana.CfnWorkspace;

  constructor(scope: Construct, id: string, props: VehicleTelemetryStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const resourcePrefix = props.resourcePrefix ?? 'vehicle-telemetry';
    const memoryStoreRetentionHours = props.memoryStoreRetentionHours ?? 24;
    const magneticStoreRetentionDays = props.magneticStoreRetentionDays ?? 30;
    const collectionIntervalMs = props.collectionIntervalMs ?? 10000;

    // Generate unique suffix for resource names
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // Create S3 bucket for telemetry data archival
    this.dataArchiveBucket = new s3.Bucket(this, 'TelemetryDataBucket', {
      bucketName: `${resourcePrefix}-data-${uniqueSuffix}`,
      versioned: true,
      lifecycleRules: [
        {
          id: 'TelemetryDataLifecycle',
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
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });

    // Create Timestream database for vehicle telemetry
    this.timestreamDatabase = new timestream.CfnDatabase(this, 'TelemetryDatabase', {
      databaseName: `telemetry_db_${uniqueSuffix.replace('-', '_')}`,
      tags: [
        { key: 'Project', value: 'VehicleTelemetry' },
        { key: 'Environment', value: 'Demo' },
      ],
    });

    // Create Timestream table with optimized retention policies
    this.timestreamTable = new timestream.CfnTable(this, 'TelemetryTable', {
      databaseName: this.timestreamDatabase.databaseName!,
      tableName: 'vehicle_metrics',
      retentionProperties: {
        memoryStoreRetentionPeriodInHours: memoryStoreRetentionHours.toString(),
        magneticStoreRetentionPeriodInDays: magneticStoreRetentionDays.toString(),
      },
      tags: [
        { key: 'Project', value: 'VehicleTelemetry' },
        { key: 'Environment', value: 'Demo' },
      ],
    });

    // Add explicit dependency
    this.timestreamTable.addDependency(this.timestreamDatabase);

    // Create IAM role for AWS IoT FleetWise
    this.fleetWiseRole = new iam.Role(this, 'FleetWiseServiceRole', {
      roleName: `FleetWiseServiceRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('iotfleetwise.amazonaws.com'),
      description: 'Service role for AWS IoT FleetWise to write to Timestream',
      inlinePolicies: {
        TimestreamWritePolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'timestream:WriteRecords',
                'timestream:DescribeEndpoints',
              ],
              resources: [
                this.timestreamTable.attrArn,
              ],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['timestream:DescribeEndpoints'],
              resources: ['*'],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:PutObject',
                's3:GetObject',
                's3:ListBucket',
              ],
              resources: [
                this.dataArchiveBucket.bucketArn,
                `${this.dataArchiveBucket.bucketArn}/*`,
              ],
            }),
          ],
        }),
      },
    });

    // Create Amazon Managed Grafana workspace
    this.grafanaWorkspace = new grafana.CfnWorkspace(this, 'GrafanaWorkspace', {
      workspaceName: `FleetTelemetry-${uniqueSuffix}`,
      workspaceDescription: 'Vehicle telemetry dashboards and analytics',
      accountAccessType: 'CURRENT_ACCOUNT',
      authenticationProviders: ['AWS_SSO'],
      permissionType: 'SERVICE_MANAGED',
      workspaceDataSources: ['TIMESTREAM'],
      workspaceRoleArn: this.createGrafanaServiceRole().roleArn,
      tags: [
        { key: 'Project', value: 'VehicleTelemetry' },
        { key: 'Environment', value: 'Demo' },
      ],
    });

    // Create IoT Thing for sample vehicle (demonstration purposes)
    const sampleVehicle = new iot.CfnThing(this, 'SampleVehicle', {
      thingName: `vehicle-001-${uniqueSuffix}`,
      attributePayload: {
        attributes: {
          VehicleType: 'StandardVehicle',
          FleetId: `vehicle-fleet-${uniqueSuffix}`,
          Make: 'Demo',
          Model: 'TestVehicle',
          Year: '2024',
        },
      },
    });

    // Create IoT Thing Group for fleet management
    const fleetThingGroup = new iot.CfnThingGroup(this, 'FleetThingGroup', {
      thingGroupName: `vehicle-fleet-${uniqueSuffix}`,
      thingGroupProperties: {
        thingGroupDescription: 'Demo vehicle fleet for telemetry collection',
        attributePayload: {
          attributes: {
            FleetType: 'Demo',
            Region: this.region,
          },
        },
      },
    });

    // Output important values for reference
    new cdk.CfnOutput(this, 'TimestreamDatabaseName', {
      value: this.timestreamDatabase.databaseName!,
      description: 'Name of the Timestream database for vehicle telemetry',
      exportName: `${this.stackName}-TimestreamDatabase`,
    });

    new cdk.CfnOutput(this, 'TimestreamTableName', {
      value: this.timestreamTable.tableName!,
      description: 'Name of the Timestream table for vehicle metrics',
      exportName: `${this.stackName}-TimestreamTable`,
    });

    new cdk.CfnOutput(this, 'FleetWiseRoleArn', {
      value: this.fleetWiseRole.roleArn,
      description: 'ARN of the IAM role for AWS IoT FleetWise',
      exportName: `${this.stackName}-FleetWiseRole`,
    });

    new cdk.CfnOutput(this, 'DataArchiveBucketName', {
      value: this.dataArchiveBucket.bucketName,
      description: 'Name of the S3 bucket for telemetry data archival',
      exportName: `${this.stackName}-DataBucket`,
    });

    new cdk.CfnOutput(this, 'GrafanaWorkspaceId', {
      value: this.grafanaWorkspace.attrId,
      description: 'ID of the Amazon Managed Grafana workspace',
      exportName: `${this.stackName}-GrafanaWorkspace`,
    });

    new cdk.CfnOutput(this, 'GrafanaWorkspaceEndpoint', {
      value: this.grafanaWorkspace.attrEndpoint,
      description: 'Endpoint URL for the Grafana workspace',
      exportName: `${this.stackName}-GrafanaEndpoint`,
    });

    new cdk.CfnOutput(this, 'SampleVehicleThingName', {
      value: sampleVehicle.thingName!,
      description: 'Name of the sample IoT Thing representing a vehicle',
      exportName: `${this.stackName}-SampleVehicle`,
    });

    new cdk.CfnOutput(this, 'FleetThingGroupName', {
      value: fleetThingGroup.thingGroupName!,
      description: 'Name of the IoT Thing Group for the vehicle fleet',
      exportName: `${this.stackName}-FleetGroup`,
    });
  }

  /**
   * Creates the IAM service role for Amazon Managed Grafana
   * with permissions to access Timestream data
   */
  private createGrafanaServiceRole(): iam.Role {
    return new iam.Role(this, 'GrafanaServiceRole', {
      assumedBy: new iam.ServicePrincipal('grafana.amazonaws.com'),
      description: 'Service role for Amazon Managed Grafana to access Timestream',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonGrafanaTimestreamPolicy'),
      ],
      inlinePolicies: {
        TimestreamQueryPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'timestream:Select',
                'timestream:DescribeDatabase',
                'timestream:DescribeTable',
                'timestream:ListDatabases',
                'timestream:ListTables',
                'timestream:ListMeasures',
              ],
              resources: [
                this.timestreamDatabase.attrArn,
                this.timestreamTable.attrArn,
              ],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['timestream:DescribeEndpoints'],
              resources: ['*'],
            }),
          ],
        }),
      },
    });
  }
}

/**
 * CDK Application for Vehicle Telemetry Analytics
 * 
 * This application demonstrates a complete IoT telemetry solution
 * suitable for fleet management and vehicle monitoring use cases.
 */
const app = new cdk.App();

// Create the main stack
new VehicleTelemetryStack(app, 'VehicleTelemetryStack', {
  description: 'Real-time vehicle telemetry analytics using AWS IoT FleetWise and Timestream',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'VehicleTelemetry',
    Environment: 'Demo',
    DeployedBy: 'AWS-CDK',
  },
});

// Synthesize the CloudFormation templates
app.synth();