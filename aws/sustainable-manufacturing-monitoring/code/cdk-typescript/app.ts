#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as ssm from 'aws-cdk-lib/aws-ssm';

/**
 * Stack for sustainable manufacturing monitoring using AWS IoT SiteWise and CloudWatch Carbon Insights
 * 
 * This stack deploys:
 * - Lambda function for carbon emissions calculations
 * - CloudWatch alarms for sustainability thresholds
 * - EventBridge rules for automated reporting
 * - IAM roles with least privilege access
 * - SSM parameters for configuration management
 */
export class SustainableManufacturingMonitoringStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate random suffix for unique resource naming
    const randomSuffix = Math.random().toString(36).substring(2, 8);

    // Create IAM role for Lambda function with least privilege access
    const lambdaRole = new iam.Role(this, 'CarbonCalculatorLambdaRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for carbon calculator Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        IoTSiteWiseAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'iotsitewise:DescribeAsset',
                'iotsitewise:GetAssetPropertyValue',
                'iotsitewise:GetAssetPropertyValueHistory',
                'iotsitewise:BatchGetAssetPropertyValue',
              ],
              resources: ['*'], // IoT SiteWise resources are created externally
            }),
          ],
        }),
        CloudWatchAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudwatch:PutMetricData',
                'cloudwatch:GetMetricStatistics',
                'cloudwatch:ListMetrics',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create CloudWatch log group for Lambda function
    const lambdaLogGroup = new logs.LogGroup(this, 'CarbonCalculatorLogGroup', {
      logGroupName: `/aws/lambda/manufacturing-carbon-calculator-${randomSuffix}`,
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create Lambda function for carbon emissions calculations
    const carbonCalculatorFunction = new lambda.Function(this, 'CarbonCalculatorFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'carbon-calculator.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import datetime
from decimal import Decimal
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function to calculate carbon emissions from manufacturing equipment data
    
    Args:
        event: Event data containing asset_id and optional parameters
        context: Lambda context object
        
    Returns:
        JSON response with carbon emissions calculations
    """
    
    # Carbon intensity factors (kg CO2 per kWh) by AWS region
    # These values represent typical grid carbon intensity factors
    CARBON_INTENSITY_FACTORS = {
        'us-east-1': 0.393,      # Virginia - Mixed grid with renewables
        'us-west-2': 0.295,      # Oregon - High renewable energy
        'eu-west-1': 0.316,      # Ireland - Moderate renewable mix
        'ap-northeast-1': 0.518, # Tokyo - Higher carbon intensity
        'us-east-2': 0.451,      # Ohio - Coal-heavy grid
        'eu-central-1': 0.408,   # Frankfurt - Mixed European grid
        'ap-southeast-1': 0.500, # Singapore - Natural gas dominant
        'ca-central-1': 0.120,   # Canada - Hydro dominant
        'default': 0.400         # Global average fallback
    }
    
    sitewise = boto3.client('iotsitewise')
    cloudwatch = boto3.client('cloudwatch')
    
    try:
        # Validate input parameters
        asset_id = event.get('asset_id')
        if not asset_id:
            logger.error("Asset ID is required but not provided")
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Asset ID required'})
            }
        
        logger.info(f"Processing carbon calculations for asset: {asset_id}")
        
        # Get asset properties to find the correct property IDs
        try:
            asset_properties = sitewise.describe_asset(assetId=asset_id)
        except Exception as e:
            logger.error(f"Failed to describe asset {asset_id}: {str(e)}")
            return {
                'statusCode': 404,
                'body': json.dumps({'error': f'Asset not found: {asset_id}'})
            }
        
        # Find Power_Consumption_kW property ID
        power_property_id = None
        production_property_id = None
        
        for prop in asset_properties['assetProperties']:
            if prop['name'] == 'Power_Consumption_kW':
                power_property_id = prop['id']
            elif prop['name'] == 'Production_Rate_Units_Hour':
                production_property_id = prop['id']
        
        if not power_property_id:
            logger.error(f"Power consumption property not found for asset {asset_id}")
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Power consumption property not found'})
            }
        
        # Get latest power consumption value
        try:
            power_response = sitewise.get_asset_property_value(
                assetId=asset_id,
                propertyId=power_property_id
            )
            power_consumption = power_response['propertyValue']['value']['doubleValue']
        except Exception as e:
            logger.error(f"Failed to get power consumption for asset {asset_id}: {str(e)}")
            return {
                'statusCode': 500,
                'body': json.dumps({'error': 'Failed to retrieve power consumption data'})
            }
        
        # Get production rate if available
        production_rate = None
        if production_property_id:
            try:
                production_response = sitewise.get_asset_property_value(
                    assetId=asset_id,
                    propertyId=production_property_id
                )
                production_rate = production_response['propertyValue']['value']['doubleValue']
            except Exception as e:
                logger.warning(f"Failed to get production rate for asset {asset_id}: {str(e)}")
        
        # Calculate carbon emissions using regional carbon intensity factor
        region = context.invoked_function_arn.split(':')[3]
        carbon_factor = CARBON_INTENSITY_FACTORS.get(region, CARBON_INTENSITY_FACTORS['default'])
        
        # Carbon emissions in kg CO2 per hour
        carbon_emissions = power_consumption * carbon_factor
        
        # Calculate energy efficiency if production rate is available
        energy_efficiency = None
        if production_rate and power_consumption > 0:
            energy_efficiency = production_rate / power_consumption  # units per kWh
        
        # Prepare metrics for CloudWatch
        metrics = [
            {
                'MetricName': 'CarbonEmissions',
                'Dimensions': [
                    {
                        'Name': 'AssetId',
                        'Value': asset_id
                    },
                    {
                        'Name': 'Region',
                        'Value': region
                    }
                ],
                'Value': carbon_emissions,
                'Unit': 'None',
                'Timestamp': datetime.datetime.utcnow()
            },
            {
                'MetricName': 'PowerConsumption',
                'Dimensions': [
                    {
                        'Name': 'AssetId',
                        'Value': asset_id
                    }
                ],
                'Value': power_consumption,
                'Unit': 'None',
                'Timestamp': datetime.datetime.utcnow()
            }
        ]
        
        # Add energy efficiency metric if available
        if energy_efficiency:
            metrics.append({
                'MetricName': 'EnergyEfficiency',
                'Dimensions': [
                    {
                        'Name': 'AssetId',
                        'Value': asset_id
                    }
                ],
                'Value': energy_efficiency,
                'Unit': 'None',
                'Timestamp': datetime.datetime.utcnow()
            })
        
        # Send metrics to CloudWatch
        try:
            cloudwatch.put_metric_data(
                Namespace='Manufacturing/Sustainability',
                MetricData=metrics
            )
            logger.info(f"Successfully sent {len(metrics)} metrics to CloudWatch")
        except Exception as e:
            logger.error(f"Failed to send metrics to CloudWatch: {str(e)}")
            return {
                'statusCode': 500,
                'body': json.dumps({'error': 'Failed to send metrics to CloudWatch'})
            }
        
        # Prepare response
        response_data = {
            'asset_id': asset_id,
            'carbon_emissions_kg_co2_per_hour': round(carbon_emissions, 4),
            'power_consumption_kw': power_consumption,
            'carbon_intensity_factor': carbon_factor,
            'region': region,
            'timestamp': datetime.datetime.utcnow().isoformat()
        }
        
        if energy_efficiency:
            response_data['energy_efficiency_units_per_kwh'] = round(energy_efficiency, 2)
        
        if production_rate:
            response_data['production_rate_units_per_hour'] = production_rate
        
        logger.info(f"Carbon calculation completed successfully for asset {asset_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(response_data)
        }
        
    except Exception as e:
        logger.error(f"Unexpected error in carbon calculation: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': f'Internal server error: {str(e)}'})
        }
      `),
      functionName: `manufacturing-carbon-calculator-${randomSuffix}`,
      description: 'Calculate carbon emissions from manufacturing equipment data',
      role: lambdaRole,
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      environment: {
        'LOG_LEVEL': 'INFO',
        'STACK_NAME': this.stackName,
      },
      logGroup: lambdaLogGroup,
    });

    // Create CloudWatch alarms for sustainability thresholds
    const highCarbonEmissionsAlarm = new cloudwatch.Alarm(this, 'HighCarbonEmissionsAlarm', {
      alarmName: `High-Carbon-Emissions-${randomSuffix}`,
      alarmDescription: 'Alert when carbon emissions exceed sustainable threshold',
      metric: new cloudwatch.Metric({
        namespace: 'Manufacturing/Sustainability',
        metricName: 'CarbonEmissions',
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 50.0,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    const lowEnergyEfficiencyAlarm = new cloudwatch.Alarm(this, 'LowEnergyEfficiencyAlarm', {
      alarmName: `Low-Energy-Efficiency-${randomSuffix}`,
      alarmDescription: 'Alert when energy efficiency drops below optimal levels',
      metric: new cloudwatch.Metric({
        namespace: 'Manufacturing/Sustainability',
        metricName: 'PowerConsumption',
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 100.0,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 3,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Create EventBridge rule for automated daily sustainability reporting
    const dailySustainabilityRule = new events.Rule(this, 'DailySustainabilityRule', {
      ruleName: `daily-sustainability-report-${randomSuffix}`,
      description: 'Trigger daily sustainability calculations and reporting',
      schedule: events.Schedule.cron({
        minute: '0',
        hour: '8',
        day: '*',
        month: '*',
        year: '*',
      }),
    });

    // Add Lambda function as target for EventBridge rule
    dailySustainabilityRule.addTarget(new targets.LambdaFunction(carbonCalculatorFunction, {
      event: events.RuleTargetInput.fromObject({
        source: 'eventbridge.scheduled',
        detail: {
          reportType: 'daily',
          timestamp: events.EventField.fromPath('$.time'),
        },
      }),
    }));

    // Create SSM parameters for configuration management
    const carbonIntensityParameter = new ssm.StringParameter(this, 'CarbonIntensityParameter', {
      parameterName: `/manufacturing/sustainability/carbon-intensity-${randomSuffix}`,
      stringValue: JSON.stringify({
        'us-east-1': 0.393,
        'us-west-2': 0.295,
        'eu-west-1': 0.316,
        'ap-northeast-1': 0.518,
        'default': 0.400,
      }),
      description: 'Carbon intensity factors by AWS region (kg CO2 per kWh)',
      tier: ssm.ParameterTier.STANDARD,
    });

    const sustainabilityThresholdsParameter = new ssm.StringParameter(this, 'SustainabilityThresholdsParameter', {
      parameterName: `/manufacturing/sustainability/thresholds-${randomSuffix}`,
      stringValue: JSON.stringify({
        carbonEmissionsThreshold: 50.0,
        powerConsumptionThreshold: 100.0,
        energyEfficiencyMinimum: 10.0,
      }),
      description: 'Sustainability monitoring thresholds for manufacturing equipment',
      tier: ssm.ParameterTier.STANDARD,
    });

    // Create CloudWatch dashboard for sustainability monitoring
    const sustainabilityDashboard = new cloudwatch.Dashboard(this, 'SustainabilityDashboard', {
      dashboardName: `Manufacturing-Sustainability-${randomSuffix}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Carbon Emissions Trend',
            width: 12,
            height: 6,
            left: [
              new cloudwatch.Metric({
                namespace: 'Manufacturing/Sustainability',
                metricName: 'CarbonEmissions',
                statistic: 'Average',
                period: cdk.Duration.hours(1),
              }),
            ],
            leftYAxis: {
              label: 'kg CO2/hour',
              min: 0,
            },
          }),
          new cloudwatch.GraphWidget({
            title: 'Power Consumption',
            width: 12,
            height: 6,
            left: [
              new cloudwatch.Metric({
                namespace: 'Manufacturing/Sustainability',
                metricName: 'PowerConsumption',
                statistic: 'Average',
                period: cdk.Duration.hours(1),
              }),
            ],
            leftYAxis: {
              label: 'kW',
              min: 0,
            },
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Energy Efficiency',
            width: 24,
            height: 6,
            left: [
              new cloudwatch.Metric({
                namespace: 'Manufacturing/Sustainability',
                metricName: 'EnergyEfficiency',
                statistic: 'Average',
                period: cdk.Duration.hours(1),
              }),
            ],
            leftYAxis: {
              label: 'units/kWh',
              min: 0,
            },
          }),
        ],
      ],
    });

    // Stack outputs for integration with other systems
    new cdk.CfnOutput(this, 'CarbonCalculatorFunctionName', {
      value: carbonCalculatorFunction.functionName,
      description: 'Name of the carbon calculator Lambda function',
      exportName: `${this.stackName}-CarbonCalculatorFunction`,
    });

    new cdk.CfnOutput(this, 'CarbonCalculatorFunctionArn', {
      value: carbonCalculatorFunction.functionArn,
      description: 'ARN of the carbon calculator Lambda function',
      exportName: `${this.stackName}-CarbonCalculatorFunctionArn`,
    });

    new cdk.CfnOutput(this, 'HighCarbonEmissionsAlarmName', {
      value: highCarbonEmissionsAlarm.alarmName,
      description: 'Name of the high carbon emissions CloudWatch alarm',
      exportName: `${this.stackName}-HighCarbonEmissionsAlarm`,
    });

    new cdk.CfnOutput(this, 'SustainabilityDashboardName', {
      value: sustainabilityDashboard.dashboardName,
      description: 'Name of the sustainability monitoring CloudWatch dashboard',
      exportName: `${this.stackName}-SustainabilityDashboard`,
    });

    new cdk.CfnOutput(this, 'EventBridgeRuleName', {
      value: dailySustainabilityRule.ruleName,
      description: 'Name of the daily sustainability reporting EventBridge rule',
      exportName: `${this.stackName}-EventBridgeRule`,
    });

    new cdk.CfnOutput(this, 'CarbonIntensityParameterName', {
      value: carbonIntensityParameter.parameterName,
      description: 'SSM parameter name for carbon intensity factors',
      exportName: `${this.stackName}-CarbonIntensityParameter`,
    });

    // Add tags to all resources in the stack
    cdk.Tags.of(this).add('Project', 'SustainableManufacturingMonitoring');
    cdk.Tags.of(this).add('Environment', 'Development');
    cdk.Tags.of(this).add('Purpose', 'ESGReporting');
    cdk.Tags.of(this).add('CostCenter', 'Manufacturing');
    cdk.Tags.of(this).add('Owner', 'SustainabilityTeam');
  }
}

// Create CDK app and instantiate the stack
const app = new cdk.App();

// Get context values for deployment customization
const environment = app.node.tryGetContext('environment') || 'development';
const region = app.node.tryGetContext('region') || process.env.CDK_DEFAULT_REGION;
const account = app.node.tryGetContext('account') || process.env.CDK_DEFAULT_ACCOUNT;

// Instantiate the stack with environment-specific configuration
new SustainableManufacturingMonitoringStack(app, 'SustainableManufacturingMonitoringStack', {
  env: {
    account: account,
    region: region,
  },
  description: 'Sustainable Manufacturing Monitoring with AWS IoT SiteWise and CloudWatch Carbon Insights',
  tags: {
    Application: 'SustainableManufacturingMonitoring',
    Environment: environment,
    Repository: 'aws-recipes',
  },
});

// Synthesize the CloudFormation template
app.synth();