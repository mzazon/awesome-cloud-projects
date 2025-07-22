#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as iot from 'aws-cdk-lib/aws-iot';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * IoT Device Management Stack
 * 
 * This stack creates a comprehensive IoT device management infrastructure including:
 * - IoT Thing Types for device templates
 * - Thing Groups for device organization
 * - Dynamic Thing Groups for automatic device categorization
 * - IoT Policies for secure device access
 * - Fleet indexing configuration
 * - CloudWatch logging for monitoring
 * - Fleet metrics for operational insights
 */
export class IoTDeviceManagementStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate a unique suffix for resource names
    const randomSuffix = Math.random().toString(36).substring(2, 8);

    // Create IoT Thing Type for device templates
    const thingType = new iot.CfnThingType(this, 'SensorThingType', {
      thingTypeName: `sensor-type-${randomSuffix}`,
      thingTypeProperties: {
        thingTypeDescription: 'Temperature sensor device type',
        searchableAttributes: ['location', 'firmwareVersion', 'manufacturer']
      }
    });

    // Create static Thing Group for device organization
    const thingGroup = new iot.CfnThingGroup(this, 'ProductionSensorGroup', {
      thingGroupName: `sensor-group-${randomSuffix}`,
      thingGroupProperties: {
        thingGroupDescription: 'Production temperature sensors',
        attributePayload: {
          attributes: {
            'Environment': 'Production',
            'Location': 'Factory1'
          }
        }
      }
    });

    // Create dynamic Thing Group for firmware monitoring
    const outdatedFirmwareGroup = new iot.CfnThingGroup(this, 'OutdatedFirmwareGroup', {
      thingGroupName: `outdated-firmware-${randomSuffix}`,
      thingGroupProperties: {
        thingGroupDescription: 'Devices requiring firmware updates'
      },
      queryString: 'attributes.firmwareVersion:1.0.0'
    });

    // Create dynamic Thing Group for building A devices
    const buildingAGroup = new iot.CfnThingGroup(this, 'BuildingASensorGroup', {
      thingGroupName: `building-a-sensors-${randomSuffix}`,
      thingGroupProperties: {
        thingGroupDescription: 'All sensors in Building A'
      },
      queryString: 'attributes.location:Building-A'
    });

    // Create IoT Policy for device permissions
    const devicePolicy = new iot.CfnPolicy(this, 'DevicePolicy', {
      policyName: `device-policy-${randomSuffix}`,
      policyDocument: {
        Version: '2012-10-17',
        Statement: [
          {
            Effect: 'Allow',
            Action: [
              'iot:Connect',
              'iot:Publish',
              'iot:Subscribe',
              'iot:Receive'
            ],
            Resource: [
              `arn:aws:iot:${this.region}:${this.account}:client/\${iot:Connection.Thing.ThingName}`,
              `arn:aws:iot:${this.region}:${this.account}:topic/device/\${iot:Connection.Thing.ThingName}/*`,
              `arn:aws:iot:${this.region}:${this.account}:topicfilter/device/\${iot:Connection.Thing.ThingName}/*`
            ]
          },
          {
            Effect: 'Allow',
            Action: [
              'iot:GetThingShadow',
              'iot:UpdateThingShadow',
              'iot:DeleteThingShadow'
            ],
            Resource: [
              `arn:aws:iot:${this.region}:${this.account}:thing/\${iot:Connection.Thing.ThingName}`
            ]
          }
        ]
      }
    });

    // Create sample IoT devices
    const deviceNames = ['temp-sensor-01', 'temp-sensor-02', 'temp-sensor-03', 'temp-sensor-04'];
    const locations = ['Building-A', 'Building-B', 'Building-C', 'Building-D'];
    const devices: iot.CfnThing[] = [];

    deviceNames.forEach((deviceName, index) => {
      const device = new iot.CfnThing(this, `Device${index + 1}`, {
        thingName: deviceName,
        thingTypeName: thingType.thingTypeName,
        attributePayload: {
          attributes: {
            'location': locations[index],
            'firmwareVersion': '1.0.0',
            'manufacturer': 'AcmeSensors'
          }
        }
      });

      // Add device to static thing group
      new iot.CfnThingGroupInfo(this, `DeviceGroupInfo${index + 1}`, {
        thingName: device.thingName!,
        thingGroupName: thingGroup.thingGroupName!
      });

      // Create certificates for each device
      const certificate = new iot.CfnCertificate(this, `DeviceCertificate${index + 1}`, {
        status: 'ACTIVE',
        certificateSigningRequest: undefined // Will be generated automatically
      });

      // Attach policy to certificate
      new iot.CfnPolicyPrincipalAttachment(this, `PolicyAttachment${index + 1}`, {
        policyName: devicePolicy.policyName!,
        principal: certificate.attrArn
      });

      // Attach certificate to thing
      new iot.CfnThingPrincipalAttachment(this, `ThingPrincipalAttachment${index + 1}`, {
        thingName: device.thingName!,
        principal: certificate.attrArn
      });

      devices.push(device);
      device.addDependency(thingType);
    });

    // Create CloudWatch log group for IoT device logs
    const logGroup = new logs.LogGroup(this, 'IoTDeviceLogGroup', {
      logGroupName: `/aws/iot/device-management-${randomSuffix}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Create IoT logging configuration
    const loggingRole = new iam.Role(this, 'IoTLoggingRole', {
      assumedBy: new iam.ServicePrincipal('iot.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/IoTLogging')
      ]
    });

    // Configure IoT logging
    new iot.CfnLoggingOptions(this, 'IoTLoggingOptions', {
      loggingOptionsPayload: {
        logLevel: 'INFO',
        roleArn: loggingRole.roleArn
      }
    });

    // Create fleet metrics for monitoring
    const connectivityMetric = new iot.CfnFleetMetric(this, 'ConnectedDevicesMetric', {
      metricName: `ConnectedDevices-${randomSuffix}`,
      queryString: 'connectivity.connected:true',
      aggregationType: {
        name: 'Statistics',
        values: ['count']
      },
      period: 300,
      aggregationField: 'connectivity.connected',
      description: 'Count of connected devices in fleet'
    });

    const firmwareMetric = new iot.CfnFleetMetric(this, 'FirmwareVersionsMetric', {
      metricName: `FirmwareVersions-${randomSuffix}`,
      queryString: 'attributes.firmwareVersion:*',
      aggregationType: {
        name: 'Statistics',
        values: ['count']
      },
      period: 300,
      aggregationField: 'attributes.firmwareVersion',
      description: 'Distribution of firmware versions'
    });

    // Create IoT Job for firmware updates
    const firmwareUpdateJob = new iot.CfnJob(this, 'FirmwareUpdateJob', {
      jobId: `firmware-update-${randomSuffix}`,
      targets: [thingGroup.attrArn],
      document: JSON.stringify({
        operation: 'firmwareUpdate',
        firmwareVersion: '1.1.0',
        downloadUrl: 'https://example-firmware-bucket.s3.amazonaws.com/firmware-v1.1.0.bin',
        checksum: 'abc123def456',
        rebootRequired: true,
        timeout: 300
      }),
      description: 'Firmware update to version 1.1.0',
      targetSelection: 'CONTINUOUS',
      jobExecutionsConfig: {
        maxConcurrentExecutions: 5
      },
      timeoutConfig: {
        inProgressTimeoutInMinutes: 30
      }
    });

    // Ensure dependencies are properly set
    thingGroup.addDependency(thingType);
    outdatedFirmwareGroup.addDependency(thingType);
    buildingAGroup.addDependency(thingType);
    devices.forEach(device => {
      device.addDependency(thingType);
    });
    firmwareUpdateJob.addDependency(thingGroup);
    connectivityMetric.addDependency(thingGroup);
    firmwareMetric.addDependency(thingGroup);

    // Stack outputs for verification and integration
    new cdk.CfnOutput(this, 'ThingTypeName', {
      value: thingType.thingTypeName!,
      description: 'Name of the IoT Thing Type'
    });

    new cdk.CfnOutput(this, 'ThingGroupName', {
      value: thingGroup.thingGroupName!,
      description: 'Name of the static Thing Group'
    });

    new cdk.CfnOutput(this, 'OutdatedFirmwareGroupName', {
      value: outdatedFirmwareGroup.thingGroupName!,
      description: 'Name of the dynamic Thing Group for outdated firmware'
    });

    new cdk.CfnOutput(this, 'BuildingAGroupName', {
      value: buildingAGroup.thingGroupName!,
      description: 'Name of the dynamic Thing Group for Building A devices'
    });

    new cdk.CfnOutput(this, 'DevicePolicyName', {
      value: devicePolicy.policyName!,
      description: 'Name of the IoT device policy'
    });

    new cdk.CfnOutput(this, 'DeviceNames', {
      value: deviceNames.join(', '),
      description: 'Names of the provisioned IoT devices'
    });

    new cdk.CfnOutput(this, 'LogGroupName', {
      value: logGroup.logGroupName,
      description: 'Name of the CloudWatch log group for IoT devices'
    });

    new cdk.CfnOutput(this, 'ConnectivityMetricName', {
      value: connectivityMetric.metricName!,
      description: 'Name of the connectivity fleet metric'
    });

    new cdk.CfnOutput(this, 'FirmwareMetricName', {
      value: firmwareMetric.metricName!,
      description: 'Name of the firmware versions fleet metric'
    });

    new cdk.CfnOutput(this, 'FirmwareUpdateJobId', {
      value: firmwareUpdateJob.jobId!,
      description: 'ID of the firmware update job'
    });

    new cdk.CfnOutput(this, 'IoTEndpoint', {
      value: `https://${this.account}.iot.${this.region}.amazonaws.com`,
      description: 'IoT device data endpoint'
    });
  }
}

// CDK App initialization
const app = new cdk.App();

// Create the IoT Device Management stack
new IoTDeviceManagementStack(app, 'IoTDeviceManagementStack', {
  description: 'IoT Device Management infrastructure with AWS IoT Device Management services',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION
  },
  tags: {
    'Project': 'IoT Device Management',
    'Environment': 'Production',
    'CreatedBy': 'CDK'
  }
});

// Synthesize the app
app.synth();