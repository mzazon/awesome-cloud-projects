import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as ecsPatterns from 'aws-cdk-lib/aws-ecs-patterns';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as applicationautoscaling from 'aws-cdk-lib/aws-applicationautoscaling';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import { Construct } from 'constructs';

export class ContainerHealthCheckStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Configuration parameters
    const containerPort = 80;
    const desiredCount = 2;
    const minCapacity = 1;
    const maxCapacity = 10;
    const cpuTargetUtilization = 70;

    // Create VPC with public and private subnets
    const vpc = new ec2.Vpc(this, 'HealthCheckVpc', {
      maxAzs: 2,
      enableDnsHostnames: true,
      enableDnsSupport: true,
      subnetConfiguration: [
        {
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
          cidrMask: 24,
        },
        {
          name: 'Private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
          cidrMask: 24,
        },
      ],
    });

    // Create ECS cluster
    const cluster = new ecs.Cluster(this, 'HealthCheckCluster', {
      vpc,
      clusterName: 'health-check-cluster',
      containerInsights: true,
    });

    // Create CloudWatch Log Group
    const logGroup = new logs.LogGroup(this, 'HealthCheckLogGroup', {
      logGroupName: '/ecs/health-check-app',
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create task definition with health check
    const taskDefinition = new ecs.FargateTaskDefinition(this, 'HealthCheckTaskDef', {
      memoryLimitMiB: 512,
      cpu: 256,
      family: 'health-check-app',
    });

    // Add container to task definition with comprehensive health check
    const container = taskDefinition.addContainer('health-check-container', {
      image: ecs.ContainerImage.fromRegistry('nginx:latest'),
      essential: true,
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: 'ecs',
        logGroup: logGroup,
      }),
      environment: {
        NGINX_PORT: containerPort.toString(),
      },
      // Custom nginx configuration for health endpoints
      command: [
        'sh',
        '-c',
        `echo 'server { 
          listen ${containerPort}; 
          location / { return 200 "Healthy Application"; } 
          location /health { return 200 "OK"; }
          location /ready { return 200 "Ready"; }
        }' > /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'`,
      ],
      healthCheck: {
        command: [
          'CMD-SHELL',
          `curl -f http://localhost:${containerPort}/health || exit 1`,
        ],
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        retries: 3,
        startPeriod: cdk.Duration.seconds(60),
      },
      portMappings: [
        {
          containerPort: containerPort,
          protocol: ecs.Protocol.TCP,
        },
      ],
    });

    // Create security group for ALB
    const albSecurityGroup = new ec2.SecurityGroup(this, 'AlbSecurityGroup', {
      vpc,
      description: 'Security group for Application Load Balancer',
      allowAllOutbound: true,
    });

    albSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'Allow HTTP traffic from internet'
    );

    albSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'Allow HTTPS traffic from internet'
    );

    // Create security group for ECS tasks
    const ecsSecurityGroup = new ec2.SecurityGroup(this, 'EcsSecurityGroup', {
      vpc,
      description: 'Security group for ECS tasks',
      allowAllOutbound: true,
    });

    ecsSecurityGroup.addIngressRule(
      albSecurityGroup,
      ec2.Port.tcp(containerPort),
      'Allow traffic from ALB'
    );

    // Create Application Load Balancer
    const loadBalancer = new elbv2.ApplicationLoadBalancer(this, 'HealthCheckAlb', {
      vpc,
      internetFacing: true,
      securityGroup: albSecurityGroup,
      loadBalancerName: 'health-check-alb',
    });

    // Create target group with health check configuration
    const targetGroup = new elbv2.ApplicationTargetGroup(this, 'HealthCheckTargetGroup', {
      vpc,
      port: containerPort,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetType: elbv2.TargetType.IP,
      healthCheck: {
        enabled: true,
        path: '/health',
        protocol: elbv2.Protocol.HTTP,
        port: containerPort.toString(),
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
        healthyHttpCodes: '200',
      },
      targetGroupName: 'health-check-tg',
    });

    // Create listener for ALB
    const listener = loadBalancer.addListener('HealthCheckListener', {
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      defaultTargetGroups: [targetGroup],
    });

    // Create ECS service
    const service = new ecs.FargateService(this, 'HealthCheckService', {
      cluster,
      taskDefinition,
      desiredCount,
      serviceName: 'health-check-service',
      securityGroups: [ecsSecurityGroup],
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      healthCheckGracePeriod: cdk.Duration.seconds(300),
      enableExecuteCommand: true,
    });

    // Attach service to target group
    service.attachToApplicationTargetGroup(targetGroup);

    // Create SNS topic for alerts
    const alertTopic = new sns.Topic(this, 'HealthCheckAlerts', {
      topicName: 'health-check-alerts',
      displayName: 'Health Check Alerts',
    });

    // Create CloudWatch alarms for health monitoring
    const unhealthyTargetsAlarm = new cloudwatch.Alarm(this, 'UnhealthyTargetsAlarm', {
      alarmName: 'UnhealthyTargets',
      alarmDescription: 'Alert when targets are unhealthy',
      metric: targetGroup.metricUnhealthyHostCount({
        statistic: 'Average',
        period: cdk.Duration.minutes(1),
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    const highResponseTimeAlarm = new cloudwatch.Alarm(this, 'HighResponseTimeAlarm', {
      alarmName: 'HighResponseTime',
      alarmDescription: 'Alert when response time is high',
      metric: targetGroup.metricTargetResponseTime({
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1.0,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    const lowRunningTasksAlarm = new cloudwatch.Alarm(this, 'LowRunningTasksAlarm', {
      alarmName: 'ECSServiceRunningTasks',
      alarmDescription: 'Alert when ECS service running tasks are low',
      metric: service.metricRunningTaskCount({
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.BREACHING,
    });

    // Create Lambda function for self-healing
    const selfHealingFunction = new lambda.Function(this, 'SelfHealingFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ecs = boto3.client('ecs')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    try:
        # Parse CloudWatch alarm from SNS message
        if 'Records' in event and len(event['Records']) > 0:
            message = json.loads(event['Records'][0]['Sns']['Message'])
            alarm_name = message['AlarmName']
            
            logger.info(f"Processing alarm: {alarm_name}")
            
            if 'ECSServiceRunningTasks' in alarm_name:
                # Handle ECS service health issues
                cluster_name = '${cluster.clusterName}'
                service_name = '${service.serviceName}'
                
                # Force new deployment to restart unhealthy tasks
                response = ecs.update_service(
                    cluster=cluster_name,
                    service=service_name,
                    forceNewDeployment=True
                )
                
                logger.info(f"Forced new deployment for service {service_name}")
                
            elif 'UnhealthyTargets' in alarm_name:
                # Handle load balancer health issues
                logger.info("Unhealthy targets detected, ECS will handle automatically")
                
            elif 'HighResponseTime' in alarm_name:
                # Handle high response time issues
                logger.info("High response time detected, consider scaling or investigation")
                
            return {
                'statusCode': 200,
                'body': json.dumps('Self-healing action completed')
            }
        else:
            logger.warning("No valid alarm message found in event")
            return {
                'statusCode': 400,
                'body': json.dumps('Invalid event format')
            }
            
    except Exception as e:
        logger.error(f"Error in self-healing: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
`),
      timeout: cdk.Duration.seconds(60),
      functionName: 'self-healing-function',
      description: 'Self-healing function for container health issues',
    });

    // Grant permissions to Lambda function
    selfHealingFunction.addToRolePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'ecs:UpdateService',
          'ecs:DescribeServices',
          'ecs:ListTasks',
          'ecs:DescribeTasks',
          'cloudwatch:GetMetricStatistics',
          'cloudwatch:ListMetrics',
        ],
        resources: ['*'],
      })
    );

    // Add SNS actions to alarms
    unhealthyTargetsAlarm.addAlarmAction(
      new cloudwatchActions.SnsAction(alertTopic)
    );
    highResponseTimeAlarm.addAlarmAction(
      new cloudwatchActions.SnsAction(alertTopic)
    );
    lowRunningTasksAlarm.addAlarmAction(
      new cloudwatchActions.SnsAction(alertTopic)
    );

    // Subscribe Lambda to SNS topic
    alertTopic.addSubscription(
      new sns.Subscription(this, 'LambdaSubscription', {
        protocol: sns.SubscriptionProtocol.LAMBDA,
        endpoint: selfHealingFunction.functionArn,
      })
    );

    // Grant SNS permission to invoke Lambda
    selfHealingFunction.addPermission('AllowSNSInvoke', {
      principal: new iam.ServicePrincipal('sns.amazonaws.com'),
      action: 'lambda:InvokeFunction',
      sourceArn: alertTopic.topicArn,
    });

    // Configure auto-scaling for ECS service
    const scalingTarget = service.autoScaleTaskCount({
      minCapacity,
      maxCapacity,
    });

    // CPU-based scaling policy
    scalingTarget.scaleOnCpuUtilization('CpuScaling', {
      targetUtilizationPercent: cpuTargetUtilization,
      scaleInCooldown: cdk.Duration.minutes(5),
      scaleOutCooldown: cdk.Duration.minutes(5),
    });

    // Memory-based scaling policy
    scalingTarget.scaleOnMemoryUtilization('MemoryScaling', {
      targetUtilizationPercent: 80,
      scaleInCooldown: cdk.Duration.minutes(5),
      scaleOutCooldown: cdk.Duration.minutes(5),
    });

    // Outputs
    new cdk.CfnOutput(this, 'LoadBalancerDNS', {
      value: loadBalancer.loadBalancerDnsName,
      description: 'DNS name of the Application Load Balancer',
      exportName: 'HealthCheckLoadBalancerDNS',
    });

    new cdk.CfnOutput(this, 'LoadBalancerUrl', {
      value: `http://${loadBalancer.loadBalancerDnsName}`,
      description: 'URL of the Application Load Balancer',
    });

    new cdk.CfnOutput(this, 'HealthCheckUrl', {
      value: `http://${loadBalancer.loadBalancerDnsName}/health`,
      description: 'Health check endpoint URL',
    });

    new cdk.CfnOutput(this, 'ClusterName', {
      value: cluster.clusterName,
      description: 'ECS Cluster Name',
      exportName: 'HealthCheckClusterName',
    });

    new cdk.CfnOutput(this, 'ServiceName', {
      value: service.serviceName,
      description: 'ECS Service Name',
      exportName: 'HealthCheckServiceName',
    });

    new cdk.CfnOutput(this, 'SelfHealingFunctionName', {
      value: selfHealingFunction.functionName,
      description: 'Self-healing Lambda function name',
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: alertTopic.topicArn,
      description: 'SNS Topic ARN for health check alerts',
    });

    new cdk.CfnOutput(this, 'VpcId', {
      value: vpc.vpcId,
      description: 'VPC ID',
      exportName: 'HealthCheckVpcId',
    });
  }
}