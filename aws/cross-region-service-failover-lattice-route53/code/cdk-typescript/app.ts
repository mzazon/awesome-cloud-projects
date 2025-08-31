#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as vpclattice from 'aws-cdk-lib/aws-vpclattice';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * Interface for stack configuration parameters
 */
interface CrossRegionFailoverStackProps extends cdk.StackProps {
  readonly isPrimaryRegion: boolean;
  readonly serviceName: string;
  readonly serviceNetworkName: string;
  readonly functionName: string;
  readonly domainName?: string;
  readonly simulateFailure?: boolean;
}

/**
 * Regional stack that deploys VPC Lattice service infrastructure
 * and Lambda health check functions in a single region
 */
class CrossRegionFailoverRegionalStack extends cdk.Stack {
  public readonly vpc: ec2.Vpc;
  public readonly serviceNetwork: vpclattice.CfnServiceNetwork;
  public readonly service: vpclattice.CfnService;
  public readonly healthCheckFunction: lambda.Function;
  public readonly serviceDnsName: string;

  constructor(scope: Construct, id: string, props: CrossRegionFailoverStackProps) {
    super(scope, id, props);

    const regionSuffix = props.isPrimaryRegion ? 'primary' : 'secondary';

    // Create VPC for service deployment
    this.vpc = new ec2.Vpc(this, `ServiceVpc${regionSuffix}`, {
      cidr: props.isPrimaryRegion ? '10.0.0.0/16' : '10.1.0.0/16',
      maxAzs: 2,
      natGateways: 0, // No NAT gateways needed for VPC Lattice services
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: 24,
          name: 'Private',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
    });

    // Create CloudWatch Log Group for Lambda function
    const logGroup = new logs.LogGroup(this, `HealthCheckLogGroup${regionSuffix}`, {
      logGroupName: `/aws/lambda/${props.functionName}-${regionSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create IAM role for Lambda function
    const lambdaRole = new iam.Role(this, `HealthCheckLambdaRole${regionSuffix}`, {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        CloudWatchLogs: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: [logGroup.logGroupArn],
            }),
          ],
        }),
      },
    });

    // Create Lambda function for health checks
    this.healthCheckFunction = new lambda.Function(this, `HealthCheckFunction${regionSuffix}`, {
      functionName: `${props.functionName}-${regionSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      environment: {
        REGION: this.region,
        SIMULATE_FAILURE: props.simulateFailure?.toString() || 'false',
      },
      logGroup: logGroup,
      code: lambda.Code.fromInline(`
import json
import os
import time
from datetime import datetime

def lambda_handler(event, context):
    """
    Health check endpoint that validates service availability
    Returns HTTP 200 for healthy, 503 for unhealthy
    """
    region = os.environ.get('AWS_REGION', 'unknown')
    simulate_failure = os.environ.get('SIMULATE_FAILURE', 'false').lower()
    
    try:
        current_time = datetime.utcnow().isoformat()
        
        # Check for simulated failure from environment variable
        if simulate_failure == 'true':
            health_status = False
        else:
            # Add actual health validation logic here
            # Example: Check database connectivity, external APIs, etc.
            health_status = check_service_health()
        
        if health_status:
            response = {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'X-Health-Check': 'pass'
                },
                'body': json.dumps({
                    'status': 'healthy',
                    'region': region,
                    'timestamp': current_time,
                    'version': '1.0'
                })
            }
        else:
            response = {
                'statusCode': 503,
                'headers': {
                    'Content-Type': 'application/json',
                    'X-Health-Check': 'fail'
                },
                'body': json.dumps({
                    'status': 'unhealthy',
                    'region': region,
                    'timestamp': current_time
                })
            }
            
        return response
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'status': 'error',
                'message': str(e),
                'region': region
            })
        }

def check_service_health():
    """
    Implement actual health check logic
    Returns True if healthy, False otherwise
    """
    # Example health checks:
    # - Database connectivity
    # - External API availability
    # - Cache service status
    # - Disk space checks
    return True
      `),
    });

    // Create VPC Lattice Service Network
    this.serviceNetwork = new vpclattice.CfnServiceNetwork(this, `ServiceNetwork${regionSuffix}`, {
      name: `${props.serviceNetworkName}-${regionSuffix}`,
      authType: 'NONE', // Simplified for demo - use AWS_IAM for production
      tags: [
        {
          key: 'Environment',
          value: 'production',
        },
        {
          key: 'Region',
          value: regionSuffix,
        },
      ],
    });

    // Create VPC Lattice Target Group for Lambda function
    const targetGroup = new vpclattice.CfnTargetGroup(this, `HealthCheckTargetGroup${regionSuffix}`, {
      name: `health-check-targets-${regionSuffix}`,
      type: 'LAMBDA',
      targets: [
        {
          id: this.healthCheckFunction.functionArn,
        },
      ],
      config: {
        healthCheck: {
          enabled: true,
          path: '/',
          protocol: 'HTTPS',
          intervalSeconds: 30,
          timeoutSeconds: 5,
          healthyThresholdCount: 2,
          unhealthyThresholdCount: 3,
        },
      },
    });

    // Grant VPC Lattice permission to invoke Lambda function
    this.healthCheckFunction.addPermission(`VpcLatticeInvokePermission${regionSuffix}`, {
      principal: new iam.ServicePrincipal('vpc-lattice.amazonaws.com'),
      action: 'lambda:InvokeFunction',
    });

    // Create VPC Lattice Service
    this.service = new vpclattice.CfnService(this, `HealthCheckService${regionSuffix}`, {
      name: `${props.serviceName}-${regionSuffix}`,
      authType: 'NONE', // Simplified for demo - use AWS_IAM for production
    });

    // Create Service Listener
    const listener = new vpclattice.CfnListener(this, `HealthCheckListener${regionSuffix}`, {
      serviceIdentifier: this.service.attrId,
      name: 'health-check-listener',
      protocol: 'HTTPS',
      port: 443,
      defaultAction: {
        forward: {
          targetGroups: [
            {
              targetGroupIdentifier: targetGroup.attrId,
            },
          ],
        },
      },
    });

    // Associate service with service network
    const serviceNetworkServiceAssociation = new vpclattice.CfnServiceNetworkServiceAssociation(
      this,
      `ServiceNetworkAssociation${regionSuffix}`,
      {
        serviceIdentifier: this.service.attrId,
        serviceNetworkIdentifier: this.serviceNetwork.attrId,
      }
    );

    // Associate VPC with service network
    const serviceNetworkVpcAssociation = new vpclattice.CfnServiceNetworkVpcAssociation(
      this,
      `ServiceNetworkVpcAssociation${regionSuffix}`,
      {
        serviceNetworkIdentifier: this.serviceNetwork.attrId,
        vpcIdentifier: this.vpc.vpcId,
        securityGroupIds: [this.vpc.vpcDefaultSecurityGroup],
      }
    );

    // Store service DNS name for Route53 configuration
    this.serviceDnsName = this.service.attrDnsEntryDomainName;

    // Create CloudWatch alarms for monitoring
    const healthCheckAlarm = new cloudwatch.Alarm(this, `ServiceHealthAlarm${regionSuffix}`, {
      alarmName: `${regionSuffix}-Service-Health`,
      alarmDescription: `Monitor ${regionSuffix} region service health`,
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Lambda',
        metricName: 'Errors',
        dimensionsMap: {
          FunctionName: this.healthCheckFunction.functionName,
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(1),
      }),
      threshold: 1,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
    });

    // Outputs for cross-stack references
    new cdk.CfnOutput(this, `ServiceDnsName${regionSuffix}`, {
      value: this.serviceDnsName,
      description: `VPC Lattice service DNS name for ${regionSuffix} region`,
      exportName: `${this.stackName}-ServiceDnsName`,
    });

    new cdk.CfnOutput(this, `ServiceNetworkId${regionSuffix}`, {
      value: this.serviceNetwork.attrId,
      description: `VPC Lattice service network ID for ${regionSuffix} region`,
      exportName: `${this.stackName}-ServiceNetworkId`,
    });

    new cdk.CfnOutput(this, `HealthCheckFunctionArn${regionSuffix}`, {
      value: this.healthCheckFunction.functionArn,
      description: `Health check Lambda function ARN for ${regionSuffix} region`,
      exportName: `${this.stackName}-HealthCheckFunctionArn`,
    });
  }
}

/**
 * Route53 stack that manages DNS failover configuration
 * Deployed in a single region but manages global DNS
 */
class Route53FailoverStack extends cdk.Stack {
  public readonly hostedZone: route53.HostedZone;
  public readonly primaryHealthCheck: route53.HealthCheck;
  public readonly secondaryHealthCheck: route53.HealthCheck;

  constructor(
    scope: Construct,
    id: string,
    props: cdk.StackProps & {
      domainName: string;
      primaryServiceDns: string;
      secondaryServiceDns: string;
    }
  ) {
    super(scope, id, props);

    // Create hosted zone for DNS management
    this.hostedZone = new route53.HostedZone(this, 'FailoverHostedZone', {
      zoneName: props.domainName,
      comment: 'Hosted zone for cross-region service failover',
    });

    // Create health check for primary region
    this.primaryHealthCheck = new route53.HealthCheck(this, 'PrimaryHealthCheck', {
      type: route53.HealthCheckType.HTTPS,
      resourcePath: '/',
      fqdn: props.primaryServiceDns,
      port: 443,
      requestInterval: cdk.Duration.seconds(30),
      failureThreshold: 3,
    });

    // Tag the primary health check
    cdk.Tags.of(this.primaryHealthCheck).add('Name', 'primary-service-health');
    cdk.Tags.of(this.primaryHealthCheck).add('Region', 'primary');

    // Create health check for secondary region
    this.secondaryHealthCheck = new route53.HealthCheck(this, 'SecondaryHealthCheck', {
      type: route53.HealthCheckType.HTTPS,
      resourcePath: '/',
      fqdn: props.secondaryServiceDns,
      port: 443,
      requestInterval: cdk.Duration.seconds(30),
      failureThreshold: 3,
    });

    // Tag the secondary health check
    cdk.Tags.of(this.secondaryHealthCheck).add('Name', 'secondary-service-health');
    cdk.Tags.of(this.secondaryHealthCheck).add('Region', 'secondary');

    // Create primary DNS record with failover routing
    new route53.CnameRecord(this, 'PrimaryFailoverRecord', {
      zone: this.hostedZone,
      recordName: props.domainName,
      domainName: props.primaryServiceDns,
      ttl: cdk.Duration.seconds(60),
      setIdentifier: 'primary',
      failover: route53.HealthCheckFailover.PRIMARY,
      healthCheck: this.primaryHealthCheck,
      comment: 'Primary region failover record',
    });

    // Create secondary DNS record with failover routing
    new route53.CnameRecord(this, 'SecondaryFailoverRecord', {
      zone: this.hostedZone,
      recordName: props.domainName,
      domainName: props.secondaryServiceDns,
      ttl: cdk.Duration.seconds(60),
      setIdentifier: 'secondary',
      failover: route53.HealthCheckFailover.SECONDARY,
      comment: 'Secondary region failover record',
    });

    // Create CloudWatch alarms for health check monitoring
    const primaryHealthCheckAlarm = new cloudwatch.Alarm(this, 'PrimaryHealthCheckAlarm', {
      alarmName: 'Primary-Service-Health',
      alarmDescription: 'Monitor primary region service health via Route53',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Route53',
        metricName: 'HealthCheckStatus',
        dimensionsMap: {
          HealthCheckId: this.primaryHealthCheck.healthCheckId,
        },
        statistic: 'Minimum',
        period: cdk.Duration.minutes(1),
      }),
      threshold: 1,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
    });

    const secondaryHealthCheckAlarm = new cloudwatch.Alarm(this, 'SecondaryHealthCheckAlarm', {
      alarmName: 'Secondary-Service-Health',
      alarmDescription: 'Monitor secondary region service health via Route53',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Route53',
        metricName: 'HealthCheckStatus',
        dimensionsMap: {
          HealthCheckId: this.secondaryHealthCheck.healthCheckId,
        },
        statistic: 'Minimum',
        period: cdk.Duration.minutes(1),
      }),
      threshold: 1,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
    });

    // Outputs
    new cdk.CfnOutput(this, 'HostedZoneId', {
      value: this.hostedZone.hostedZoneId,
      description: 'Route53 hosted zone ID',
      exportName: `${this.stackName}-HostedZoneId`,
    });

    new cdk.CfnOutput(this, 'NameServers', {
      value: cdk.Fn.join(', ', this.hostedZone.hostedZoneNameServers || []),
      description: 'Route53 hosted zone name servers',
    });

    new cdk.CfnOutput(this, 'PrimaryHealthCheckId', {
      value: this.primaryHealthCheck.healthCheckId,
      description: 'Primary region health check ID',
      exportName: `${this.stackName}-PrimaryHealthCheckId`,
    });

    new cdk.CfnOutput(this, 'SecondaryHealthCheckId', {
      value: this.secondaryHealthCheck.healthCheckId,
      description: 'Secondary region health check ID',
      exportName: `${this.stackName}-SecondaryHealthCheckId`,
    });

    new cdk.CfnOutput(this, 'DomainName', {
      value: props.domainName,
      description: 'Failover domain name',
      exportName: `${this.stackName}-DomainName`,
    });
  }
}

/**
 * Main CDK Application
 */
class CrossRegionFailoverApp extends cdk.App {
  constructor() {
    super();

    // Configuration parameters
    const serviceName = this.node.tryGetContext('serviceName') || 'api-service';
    const serviceNetworkName = this.node.tryGetContext('serviceNetworkName') || 'microservices-network';
    const functionName = this.node.tryGetContext('functionName') || 'health-check-service';
    const domainName = this.node.tryGetContext('domainName') || 'api.example.com';
    const primaryRegion = this.node.tryGetContext('primaryRegion') || 'us-east-1';
    const secondaryRegion = this.node.tryGetContext('secondaryRegion') || 'us-west-2';
    const simulateFailure = this.node.tryGetContext('simulateFailure') === 'true';

    // Deploy primary region stack
    const primaryStack = new CrossRegionFailoverRegionalStack(this, 'CrossRegionFailoverPrimary', {
      env: { region: primaryRegion },
      isPrimaryRegion: true,
      serviceName,
      serviceNetworkName,
      functionName,
      domainName,
      simulateFailure,
      description: 'Primary region infrastructure for cross-region service failover',
    });

    // Deploy secondary region stack
    const secondaryStack = new CrossRegionFailoverRegionalStack(this, 'CrossRegionFailoverSecondary', {
      env: { region: secondaryRegion },
      isPrimaryRegion: false,
      serviceName,
      serviceNetworkName,
      functionName,
      domainName,
      simulateFailure: false, // Secondary region should always be healthy
      description: 'Secondary region infrastructure for cross-region service failover',
    });

    // Deploy Route53 stack (in primary region)
    const route53Stack = new Route53FailoverStack(this, 'CrossRegionFailoverRoute53', {
      env: { region: primaryRegion },
      domainName,
      primaryServiceDns: primaryStack.serviceDnsName,
      secondaryServiceDns: secondaryStack.serviceDnsName,
      description: 'Route53 DNS failover configuration for cross-region service failover',
    });

    // Add dependencies
    route53Stack.addDependency(primaryStack);
    route53Stack.addDependency(secondaryStack);

    // Add tags to all stacks
    const commonTags = {
      Project: 'CrossRegionServiceFailover',
      Environment: 'Production',
      Architecture: 'VPCLattice-Route53-Failover',
      CostCenter: 'Engineering',
    };

    Object.entries(commonTags).forEach(([key, value]) => {
      cdk.Tags.of(primaryStack).add(key, value);
      cdk.Tags.of(secondaryStack).add(key, value);
      cdk.Tags.of(route53Stack).add(key, value);
    });
  }
}

// Create and deploy the application
new CrossRegionFailoverApp();