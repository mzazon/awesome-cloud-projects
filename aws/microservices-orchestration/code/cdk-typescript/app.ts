#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { EventDrivenMicroservicesStack } from './lib/event-driven-microservices-stack';

/**
 * CDK Application for Event-Driven Microservices with EventBridge and Step Functions
 * 
 * This application deploys a complete event-driven microservices architecture including:
 * - EventBridge custom event bus for decoupled messaging
 * - Step Functions for workflow orchestration
 * - Lambda functions implementing microservices
 * - DynamoDB for data persistence
 * - CloudWatch for monitoring and observability
 */
const app = new cdk.App();

// Get environment configuration from context or use defaults
const environment = app.node.tryGetContext('environment') || 'dev';
const projectName = app.node.tryGetContext('projectName') || 'microservices-demo';

// Create the main stack
new EventDrivenMicroservicesStack(app, `EventDrivenMicroservicesStack-${environment}`, {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
  },
  
  // Stack configuration
  stackName: `${projectName}-eventbridge-stepfunctions-${environment}`,
  description: 'Event-driven microservices architecture with EventBridge and Step Functions',
  
  // Custom properties
  projectName,
  environment,
  
  // Resource configuration
  tags: {
    Project: projectName,
    Environment: environment,
    Recipe: 'event-driven-microservices-eventbridge-step-functions',
    ManagedBy: 'CDK',
  },
});

// Add metadata to the app
app.node.setContext('@aws-cdk/core:enableStackNameDuplicates', true);
app.node.setContext('@aws-cdk/aws-lambda:recognizeLayerVersion', true);
app.node.setContext('@aws-cdk/aws-lambda:recognizeVersionProps', true);