#!/usr/bin/env python3
"""
CDK Python Application for Sustainable Manufacturing Monitoring
with AWS IoT SiteWise and CloudWatch Carbon Insights

This application deploys a comprehensive sustainability monitoring system
that tracks manufacturing equipment data, calculates carbon emissions,
and provides real-time analytics for ESG reporting.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_iotsitewise as sitewise,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_events as events,
    aws_events_targets as targets,
    aws_cloudwatch as cloudwatch,
    CfnParameter,
    CfnOutput,
    Duration,
    RemovalPolicy,
)
from constructs import Construct
from typing import Dict, List, Optional
import json


class SustainableManufacturingStack(Stack):
    """
    CDK Stack for Sustainable Manufacturing Monitoring Solution
    
    This stack creates:
    - IoT SiteWise asset model for manufacturing equipment
    - Manufacturing equipment assets
    - Lambda function for carbon emissions calculation
    - CloudWatch alarms for sustainability thresholds
    - EventBridge rule for automated reporting
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Parameters
        self.create_parameters()
        
        # Core resources
        self.create_asset_model()
        self.create_manufacturing_assets()
        self.create_carbon_calculator_lambda()
        self.create_cloudwatch_alarms()
        self.create_automated_reporting()
        
        # Outputs
        self.create_outputs()

    def create_parameters(self) -> None:
        """Create CloudFormation parameters for customization"""
        self.environment_name = CfnParameter(
            self, "EnvironmentName",
            type="String",
            description="Name of the environment (e.g., dev, staging, prod)",
            default="dev",
            allowed_pattern="[a-zA-Z0-9-]+",
            constraint_description="Must contain only alphanumeric characters and hyphens"
        )
        
        self.carbon_intensity_factor = CfnParameter(
            self, "CarbonIntensityFactor",
            type="Number",
            description="Carbon intensity factor (kg CO2 per kWh) for the region",
            default=0.393,
            min_value=0.1,
            max_value=1.0
        )
        
        self.high_carbon_threshold = CfnParameter(
            self, "HighCarbonThreshold",
            type="Number",
            description="Threshold for high carbon emissions alarm (kg CO2/hour)",
            default=50.0,
            min_value=10.0,
            max_value=500.0
        )
        
        self.high_power_threshold = CfnParameter(
            self, "HighPowerThreshold",
            type="Number",
            description="Threshold for high power consumption alarm (kW)",
            default=100.0,
            min_value=10.0,
            max_value=1000.0
        )

    def create_asset_model(self) -> None:
        """Create IoT SiteWise asset model for manufacturing equipment"""
        # Define asset model properties
        asset_model_properties = [
            {
                "name": "Equipment_Serial_Number",
                "dataType": "STRING",
                "type": {
                    "attribute": {
                        "defaultValue": "UNKNOWN"
                    }
                }
            },
            {
                "name": "Power_Consumption_kW",
                "dataType": "DOUBLE",
                "unit": "kW",
                "type": {
                    "measurement": {}
                }
            },
            {
                "name": "Production_Rate_Units_Hour",
                "dataType": "DOUBLE",
                "unit": "units/hour",
                "type": {
                    "measurement": {}
                }
            },
            {
                "name": "Equipment_Temperature_C",
                "dataType": "DOUBLE",
                "unit": "Celsius",
                "type": {
                    "measurement": {}
                }
            },
            {
                "name": "Equipment_Vibration_mm_s",
                "dataType": "DOUBLE",
                "unit": "mm/s",
                "type": {
                    "measurement": {}
                }
            }
        ]

        # Create the asset model
        self.asset_model = sitewise.CfnAssetModel(
            self, "SustainableManufacturingAssetModel",
            asset_model_name="SustainableManufacturingModel",
            asset_model_description="Asset model for sustainable manufacturing monitoring with ESG reporting capabilities",
            asset_model_properties=asset_model_properties,
            asset_model_hierarchies=[
                {
                    "name": "ProductionLineHierarchy",
                    "logicalId": "ProductionLineHierarchy"
                }
            ],
            tags=[
                {
                    "key": "Environment",
                    "value": self.environment_name.value_as_string
                },
                {
                    "key": "Purpose",
                    "value": "SustainabilityMonitoring"
                },
                {
                    "key": "ESGReporting",
                    "value": "true"
                }
            ]
        )

    def create_manufacturing_assets(self) -> None:
        """Create manufacturing equipment assets"""
        # Production Line A - Extruder
        self.equipment_1 = sitewise.CfnAsset(
            self, "ProductionLineAExtruder",
            asset_name="Production_Line_A_Extruder",
            asset_model_id=self.asset_model.ref,
            asset_description="High-efficiency plastic extruder for sustainable manufacturing",
            asset_properties=[
                {
                    "logicalId": "Equipment_Serial_Number",
                    "alias": "EXT-A-001",
                    "notificationState": "ENABLED"
                }
            ],
            tags=[
                {
                    "key": "ProductionLine",
                    "value": "LineA"
                },
                {
                    "key": "EquipmentType",
                    "value": "Extruder"
                },
                {
                    "key": "CriticalityLevel",
                    "value": "High"
                }
            ]
        )
        
        # Production Line B - Injection Molding
        self.equipment_2 = sitewise.CfnAsset(
            self, "ProductionLineBInjectionMolding",
            asset_name="Production_Line_B_Injection_Molding",
            asset_model_id=self.asset_model.ref,
            asset_description="Energy-efficient injection molding machine with smart monitoring",
            asset_properties=[
                {
                    "logicalId": "Equipment_Serial_Number",
                    "alias": "INJ-B-001",
                    "notificationState": "ENABLED"
                }
            ],
            tags=[
                {
                    "key": "ProductionLine",
                    "value": "LineB"
                },
                {
                    "key": "EquipmentType",
                    "value": "InjectionMolding"
                },
                {
                    "key": "CriticalityLevel",
                    "value": "High"
                }
            ]
        )
        
        # Production Line C - Assembly
        self.equipment_3 = sitewise.CfnAsset(
            self, "ProductionLineCAssembly",
            asset_name="Production_Line_C_Assembly",
            asset_model_id=self.asset_model.ref,
            asset_description="Automated assembly line with sustainability tracking",
            asset_properties=[
                {
                    "logicalId": "Equipment_Serial_Number",
                    "alias": "ASM-C-001",
                    "notificationState": "ENABLED"
                }
            ],
            tags=[
                {
                    "key": "ProductionLine",
                    "value": "LineC"
                },
                {
                    "key": "EquipmentType",
                    "value": "Assembly"
                },
                {
                    "key": "CriticalityLevel",
                    "value": "Medium"
                }
            ]
        )

    def create_carbon_calculator_lambda(self) -> None:
        """Create Lambda function for carbon emissions calculation"""
        # Create IAM role for Lambda
        lambda_role = iam.Role(
            self, "CarbonCalculatorLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for carbon calculator Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AWSIoTSiteWiseReadOnlyAccess")
            ],
            inline_policies={
                "CloudWatchMetricsPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "cloudwatch:PutMetricData",
                                "cloudwatch:GetMetricStatistics",
                                "cloudwatch:ListMetrics"
                            ],
                            resources=["*"]
                        )
                    ]
                )
            }
        )

        # Lambda function code
        lambda_code = '''
import json
import boto3
import datetime
from decimal import Decimal
import os
from typing import Dict, Any, Optional

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function to calculate carbon emissions from manufacturing equipment data.
    
    Args:
        event: Lambda event containing asset_id and optional parameters
        context: Lambda context object
        
    Returns:
        Dictionary with carbon emissions calculations and metrics
    """
    # Carbon intensity factors (kg CO2 per kWh) by region
    CARBON_INTENSITY_FACTORS = {
        'us-east-1': 0.393,     # Virginia
        'us-west-2': 0.295,     # Oregon  
        'eu-west-1': 0.316,     # Ireland
        'ap-northeast-1': 0.518, # Tokyo
        'ap-southeast-2': 0.79,  # Sydney
        'eu-central-1': 0.338,   # Frankfurt
        'us-west-1': 0.351,     # N. California
        'ap-south-1': 0.708,    # Mumbai
        'sa-east-1': 0.074      # São Paulo
    }
    
    # Initialize AWS clients
    sitewise = boto3.client('iotsitewise')
    cloudwatch = boto3.client('cloudwatch')
    
    try:
        # Extract parameters from event
        asset_id = event.get('asset_id')
        custom_carbon_factor = event.get('carbon_intensity_factor')
        
        if not asset_id:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'Asset ID is required',
                    'message': 'Please provide asset_id in the event payload'
                })
            }
        
        # Get asset properties to find measurement property IDs
        asset_description = sitewise.describe_asset(assetId=asset_id)
        asset_name = asset_description['assetName']
        
        # Find property IDs for measurements
        power_property_id = None
        production_property_id = None
        temperature_property_id = None
        vibration_property_id = None
        
        for prop in asset_description['assetProperties']:
            if prop['name'] == 'Power_Consumption_kW':
                power_property_id = prop['id']
            elif prop['name'] == 'Production_Rate_Units_Hour':
                production_property_id = prop['id']
            elif prop['name'] == 'Equipment_Temperature_C':
                temperature_property_id = prop['id']
            elif prop['name'] == 'Equipment_Vibration_mm_s':
                vibration_property_id = prop['id']
        
        if not power_property_id:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'Power consumption property not found',
                    'asset_id': asset_id,
                    'asset_name': asset_name
                })
            }
        
        # Get latest measurement values
        measurements = {}
        
        # Get power consumption
        try:
            power_response = sitewise.get_asset_property_value(
                assetId=asset_id,
                propertyId=power_property_id
            )
            measurements['power_consumption_kw'] = power_response['propertyValue']['value']['doubleValue']
        except Exception as e:
            print(f"Could not retrieve power consumption: {str(e)}")
            measurements['power_consumption_kw'] = 0.0
        
        # Get production rate
        if production_property_id:
            try:
                production_response = sitewise.get_asset_property_value(
                    assetId=asset_id,
                    propertyId=production_property_id
                )
                measurements['production_rate_units_hour'] = production_response['propertyValue']['value']['doubleValue']
            except Exception as e:
                print(f"Could not retrieve production rate: {str(e)}")
                measurements['production_rate_units_hour'] = 0.0
        
        # Get temperature
        if temperature_property_id:
            try:
                temp_response = sitewise.get_asset_property_value(
                    assetId=asset_id,
                    propertyId=temperature_property_id
                )
                measurements['equipment_temperature_c'] = temp_response['propertyValue']['value']['doubleValue']
            except Exception as e:
                print(f"Could not retrieve temperature: {str(e)}")
                measurements['equipment_temperature_c'] = 0.0
        
        # Get vibration
        if vibration_property_id:
            try:
                vibration_response = sitewise.get_asset_property_value(
                    assetId=asset_id,
                    propertyId=vibration_property_id
                )
                measurements['equipment_vibration_mm_s'] = vibration_response['propertyValue']['value']['doubleValue']
            except Exception as e:
                print(f"Could not retrieve vibration: {str(e)}")
                measurements['equipment_vibration_mm_s'] = 0.0
        
        # Calculate carbon emissions
        region = context.invoked_function_arn.split(':')[3]
        carbon_factor = custom_carbon_factor or CARBON_INTENSITY_FACTORS.get(region, 0.4)
        
        power_consumption = measurements['power_consumption_kw']
        carbon_emissions_kg_co2_per_hour = power_consumption * carbon_factor
        
        # Calculate efficiency metrics
        production_rate = measurements.get('production_rate_units_hour', 0)
        energy_efficiency = production_rate / power_consumption if power_consumption > 0 else 0
        carbon_intensity_per_unit = carbon_emissions_kg_co2_per_hour / production_rate if production_rate > 0 else 0
        
        # Calculate daily projections
        daily_energy_consumption_kwh = power_consumption * 24
        daily_carbon_emissions_kg = carbon_emissions_kg_co2_per_hour * 24
        daily_production_units = production_rate * 24
        
        # Prepare metrics for CloudWatch
        current_timestamp = datetime.datetime.utcnow()
        metric_data = [
            {
                'MetricName': 'CarbonEmissions',
                'Dimensions': [
                    {'Name': 'AssetId', 'Value': asset_id},
                    {'Name': 'AssetName', 'Value': asset_name}
                ],
                'Value': carbon_emissions_kg_co2_per_hour,
                'Unit': 'None',
                'Timestamp': current_timestamp
            },
            {
                'MetricName': 'PowerConsumption',
                'Dimensions': [
                    {'Name': 'AssetId', 'Value': asset_id},
                    {'Name': 'AssetName', 'Value': asset_name}
                ],
                'Value': power_consumption,
                'Unit': 'None',
                'Timestamp': current_timestamp
            },
            {
                'MetricName': 'EnergyEfficiency',
                'Dimensions': [
                    {'Name': 'AssetId', 'Value': asset_id},
                    {'Name': 'AssetName', 'Value': asset_name}
                ],
                'Value': energy_efficiency,
                'Unit': 'None',
                'Timestamp': current_timestamp
            },
            {
                'MetricName': 'CarbonIntensityPerUnit',
                'Dimensions': [
                    {'Name': 'AssetId', 'Value': asset_id},
                    {'Name': 'AssetName', 'Value': asset_name}
                ],
                'Value': carbon_intensity_per_unit,
                'Unit': 'None',
                'Timestamp': current_timestamp
            }
        ]
        
        # Add additional metrics if available
        if 'equipment_temperature_c' in measurements:
            metric_data.append({
                'MetricName': 'EquipmentTemperature',
                'Dimensions': [
                    {'Name': 'AssetId', 'Value': asset_id},
                    {'Name': 'AssetName', 'Value': asset_name}
                ],
                'Value': measurements['equipment_temperature_c'],
                'Unit': 'None',
                'Timestamp': current_timestamp
            })
        
        if 'equipment_vibration_mm_s' in measurements:
            metric_data.append({
                'MetricName': 'EquipmentVibration',
                'Dimensions': [
                    {'Name': 'AssetId', 'Value': asset_id},
                    {'Name': 'AssetName', 'Value': asset_name}
                ],
                'Value': measurements['equipment_vibration_mm_s'],
                'Unit': 'None',
                'Timestamp': current_timestamp
            })
        
        # Send metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='Manufacturing/Sustainability',
            MetricData=metric_data
        )
        
        # Prepare response
        response_data = {
            'asset_id': asset_id,
            'asset_name': asset_name,
            'timestamp': current_timestamp.isoformat(),
            'measurements': measurements,
            'calculations': {
                'carbon_emissions_kg_co2_per_hour': round(carbon_emissions_kg_co2_per_hour, 4),
                'energy_efficiency_units_per_kwh': round(energy_efficiency, 2),
                'carbon_intensity_per_unit_kg_co2': round(carbon_intensity_per_unit, 6),
                'carbon_intensity_factor': carbon_factor
            },
            'daily_projections': {
                'energy_consumption_kwh': round(daily_energy_consumption_kwh, 2),
                'carbon_emissions_kg': round(daily_carbon_emissions_kg, 2),
                'production_units': round(daily_production_units, 0)
            },
            'region': region
        }
        
        return {
            'statusCode': 200,
            'body': json.dumps(response_data, default=str)
        }
        
    except Exception as e:
        error_message = f"Error calculating carbon emissions: {str(e)}"
        print(error_message)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message,
                'asset_id': asset_id if 'asset_id' in locals() else 'unknown'
            })
        }
'''

        # Create Lambda function
        self.carbon_calculator_lambda = lambda_.Function(
            self, "CarbonCalculatorLambda",
            function_name=f"manufacturing-carbon-calculator-{self.environment_name.value_as_string}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=lambda_role,
            timeout=Duration.minutes(5),
            memory_size=512,
            environment={
                "CARBON_INTENSITY_FACTOR": self.carbon_intensity_factor.value_as_string,
                "ENVIRONMENT": self.environment_name.value_as_string
            },
            description="Lambda function for calculating carbon emissions from manufacturing equipment data",
            tags={
                "Environment": self.environment_name.value_as_string,
                "Purpose": "CarbonCalculation",
                "ESGReporting": "true"
            }
        )

    def create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for sustainability thresholds"""
        # High Carbon Emissions Alarm
        self.high_carbon_alarm = cloudwatch.Alarm(
            self, "HighCarbonEmissionsAlarm",
            alarm_name=f"High-Carbon-Emissions-{self.environment_name.value_as_string}",
            alarm_description="Alert when carbon emissions exceed sustainability threshold",
            metric=cloudwatch.Metric(
                namespace="Manufacturing/Sustainability",
                metric_name="CarbonEmissions",
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=self.high_carbon_threshold.value_as_number,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            datapoints_to_alarm=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        # High Power Consumption Alarm
        self.high_power_alarm = cloudwatch.Alarm(
            self, "HighPowerConsumptionAlarm",
            alarm_name=f"High-Power-Consumption-{self.environment_name.value_as_string}",
            alarm_description="Alert when power consumption exceeds efficiency threshold",
            metric=cloudwatch.Metric(
                namespace="Manufacturing/Sustainability",
                metric_name="PowerConsumption",
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=self.high_power_threshold.value_as_number,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=3,
            datapoints_to_alarm=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        # Low Energy Efficiency Alarm
        self.low_efficiency_alarm = cloudwatch.Alarm(
            self, "LowEnergyEfficiencyAlarm",
            alarm_name=f"Low-Energy-Efficiency-{self.environment_name.value_as_string}",
            alarm_description="Alert when energy efficiency drops below optimal levels",
            metric=cloudwatch.Metric(
                namespace="Manufacturing/Sustainability",
                metric_name="EnergyEfficiency",
                statistic="Average",
                period=Duration.minutes(15)
            ),
            threshold=5.0,  # units per kWh
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            evaluation_periods=2,
            datapoints_to_alarm=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

    def create_automated_reporting(self) -> None:
        """Create EventBridge rule for automated sustainability reporting"""
        # Create EventBridge rule for daily reporting
        self.daily_reporting_rule = events.Rule(
            self, "DailySustainabilityReporting",
            rule_name=f"daily-sustainability-report-{self.environment_name.value_as_string}",
            description="Trigger daily sustainability calculations and reporting",
            schedule=events.Schedule.cron(
                minute="0",
                hour="8",  # 8 AM UTC
                day="*",
                month="*",
                year="*"
            ),
            enabled=True
        )
        
        # Add Lambda function as target for each equipment asset
        self.daily_reporting_rule.add_target(
            targets.LambdaFunction(
                self.carbon_calculator_lambda,
                event=events.RuleTargetInput.from_object({
                    "asset_id": self.equipment_1.ref,
                    "report_type": "daily",
                    "automated": True
                })
            )
        )
        
        # Create EventBridge rule for hourly monitoring
        self.hourly_monitoring_rule = events.Rule(
            self, "HourlySustainabilityMonitoring",
            rule_name=f"hourly-sustainability-monitor-{self.environment_name.value_as_string}",
            description="Trigger hourly sustainability calculations for real-time monitoring",
            schedule=events.Schedule.rate(Duration.hours(1)),
            enabled=True
        )
        
        # Add Lambda targets for hourly monitoring
        equipment_assets = [self.equipment_1, self.equipment_2, self.equipment_3]
        for i, equipment in enumerate(equipment_assets):
            self.hourly_monitoring_rule.add_target(
                targets.LambdaFunction(
                    self.carbon_calculator_lambda,
                    event=events.RuleTargetInput.from_object({
                        "asset_id": equipment.ref,
                        "report_type": "hourly",
                        "automated": True
                    })
                )
            )

    def create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources"""
        CfnOutput(
            self, "AssetModelId",
            value=self.asset_model.ref,
            description="ID of the IoT SiteWise asset model for manufacturing equipment",
            export_name=f"{self.stack_name}-AssetModelId"
        )
        
        CfnOutput(
            self, "Equipment1Id",
            value=self.equipment_1.ref,
            description="ID of Production Line A Extruder asset",
            export_name=f"{self.stack_name}-Equipment1Id"
        )
        
        CfnOutput(
            self, "Equipment2Id",
            value=self.equipment_2.ref,
            description="ID of Production Line B Injection Molding asset",
            export_name=f"{self.stack_name}-Equipment2Id"
        )
        
        CfnOutput(
            self, "Equipment3Id",
            value=self.equipment_3.ref,
            description="ID of Production Line C Assembly asset",
            export_name=f"{self.stack_name}-Equipment3Id"
        )
        
        CfnOutput(
            self, "CarbonCalculatorLambdaArn",
            value=self.carbon_calculator_lambda.function_arn,
            description="ARN of the carbon calculator Lambda function",
            export_name=f"{self.stack_name}-CarbonCalculatorLambdaArn"
        )
        
        CfnOutput(
            self, "CarbonCalculatorLambdaName",
            value=self.carbon_calculator_lambda.function_name,
            description="Name of the carbon calculator Lambda function",
            export_name=f"{self.stack_name}-CarbonCalculatorLambdaName"
        )
        
        CfnOutput(
            self, "CloudWatchDashboardUrl",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:",
            description="URL to create CloudWatch dashboard for sustainability monitoring",
            export_name=f"{self.stack_name}-CloudWatchDashboardUrl"
        )
        
        CfnOutput(
            self, "SustainabilityMetricsNamespace",
            value="Manufacturing/Sustainability",
            description="CloudWatch namespace for sustainability metrics",
            export_name=f"{self.stack_name}-SustainabilityMetricsNamespace"
        )


# CDK App
app = cdk.App()

# Get environment name from context or use default
environment_name = app.node.try_get_context("environment") or "dev"

# Create the stack
SustainableManufacturingStack(
    app, 
    f"SustainableManufacturingStack-{environment_name}",
    description="Sustainable Manufacturing Monitoring with AWS IoT SiteWise and CloudWatch Carbon Insights",
    env=cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region")
    ),
    tags={
        "Project": "SustainableManufacturing",
        "Environment": environment_name,
        "Purpose": "ESGReporting",
        "CostCenter": "Manufacturing",
        "Owner": "SustainabilityTeam"
    }
)

app.synth()