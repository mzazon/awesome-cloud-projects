#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { IoTFirmwareUpdatesStack } from './lib/iot-firmware-updates-stack';

const app = new cdk.App();

// Get deployment context values with defaults
const account = app.node.tryGetContext('account') || process.env.CDK_DEFAULT_ACCOUNT;
const region = app.node.tryGetContext('region') || process.env.CDK_DEFAULT_REGION || 'us-east-1';
const environment = app.node.tryGetContext('environment') || 'dev';

new IoTFirmwareUpdatesStack(app, `IoTFirmwareUpdatesStack-${environment}`, {
  env: {
    account: account,
    region: region,
  },
  stackName: `iot-firmware-updates-${environment}`,
  description: 'AWS CDK Stack for IoT Firmware Updates with Device Management Jobs',
  
  // Stack-specific configuration
  environment: environment,
  
  tags: {
    Project: 'IoTFirmwareUpdates',
    Environment: environment,
    ManagedBy: 'CDK',
    Recipe: 'iot-firmware-updates-device-management-jobs'
  }
});

app.synth();