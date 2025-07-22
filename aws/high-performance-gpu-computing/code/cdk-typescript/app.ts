#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as eventsTargets from 'aws-cdk-lib/aws-events-targets';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import { Construct } from 'constructs';

/**
 * Properties for the GPU Workloads Stack
 */
interface GpuWorkloadsStackProps extends cdk.StackProps {
  /**
   * Email address for GPU monitoring alerts
   */
  alertEmail?: string;
  
  /**
   * Instance type for P4 ML training instances
   * @default 'p4d.24xlarge'
   */
  p4InstanceType?: string;
  
  /**
   * Instance type for G4 inference instances
   * @default 'g4dn.xlarge'
   */
  g4InstanceType?: string;
  
  /**
   * Maximum spot price for G4 instances in USD per hour
   * @default '0.50'
   */
  maxSpotPrice?: string;
  
  /**
   * Target capacity for G4 spot fleet
   * @default 2
   */
  spotFleetTargetCapacity?: number;
  
  /**
   * VPC ID to use for deployment. If not provided, default VPC will be used
   */
  vpcId?: string;
}

/**
 * CDK Stack for GPU-Accelerated Workloads with EC2 P4 and G4 Instances
 * 
 * This stack deploys:
 * - P4 instances for ML training with NVIDIA A100 GPUs
 * - G4 spot fleet for cost-optimized inference with NVIDIA T4 GPUs
 * - Comprehensive CloudWatch monitoring with GPU-specific metrics
 * - Automated alerting via SNS for temperature and utilization thresholds
 * - Cost optimization Lambda function for unused instance detection
 * - Security groups and IAM roles following least privilege principles
 */
class GpuWorkloadsStack extends cdk.Stack {
  private readonly alertTopic: sns.Topic;
  private readonly gpuRole: iam.Role;
  private readonly securityGroup: ec2.SecurityGroup;
  private readonly vpc: ec2.IVpc;
  
  constructor(scope: Construct, id: string, props: GpuWorkloadsStackProps = {}) {
    super(scope, id, props);
    
    // Generate unique suffix for resource naming
    const uniqueSuffix = this.node.addr.substring(0, 6);
    
    // Get VPC (use provided VPC ID or default VPC)
    this.vpc = props.vpcId 
      ? ec2.Vpc.fromLookup(this, 'Vpc', { vpcId: props.vpcId })
      : ec2.Vpc.fromLookup(this, 'DefaultVpc', { isDefault: true });
    
    // Create SNS topic for GPU monitoring alerts
    this.alertTopic = this.createAlertTopic(uniqueSuffix, props.alertEmail);
    
    // Create IAM role for GPU instances
    this.gpuRole = this.createGpuInstanceRole(uniqueSuffix);
    
    // Create security group for GPU instances
    this.securityGroup = this.createSecurityGroup(uniqueSuffix);
    
    // Create key pair for SSH access
    const keyPair = this.createKeyPair(uniqueSuffix);
    
    // Get the latest Deep Learning AMI
    const dlAmi = this.getLatestDeepLearningAmi();
    
    // Create user data script for GPU setup
    const userData = this.createGpuUserData();
    
    // Launch P4 instance for ML training
    const p4Instance = this.createP4Instance(
      uniqueSuffix,
      dlAmi,
      userData,
      keyPair,
      props.p4InstanceType || 'p4d.24xlarge'
    );
    
    // Create G4 spot fleet for cost-optimized inference
    this.createG4SpotFleet(
      uniqueSuffix,
      dlAmi,
      userData,
      keyPair,
      props.g4InstanceType || 'g4dn.xlarge',
      props.maxSpotPrice || '0.50',
      props.spotFleetTargetCapacity || 2
    );
    
    // Create CloudWatch dashboard for GPU monitoring
    this.createGpuMonitoringDashboard(p4Instance);
    
    // Create CloudWatch alarms for GPU metrics
    this.createGpuAlarms(p4Instance);
    
    // Create cost optimization Lambda function
    this.createCostOptimizationFunction(uniqueSuffix);
    
    // Create SSM documents for GPU management
    this.createSSMDocuments(uniqueSuffix);
    
    // Output important information
    this.createOutputs(p4Instance, keyPair);
  }
  
  /**
   * Creates SNS topic for GPU monitoring alerts
   */
  private createAlertTopic(uniqueSuffix: string, alertEmail?: string): sns.Topic {
    const topic = new sns.Topic(this, 'GpuAlertTopic', {
      topicName: `gpu-workload-alerts-${uniqueSuffix}`,
      displayName: 'GPU Workload Monitoring Alerts',
      description: 'SNS topic for GPU instance monitoring alerts including temperature and utilization thresholds'
    });
    
    // Subscribe email if provided
    if (alertEmail) {
      topic.addSubscription(new snsSubscriptions.EmailSubscription(alertEmail));
    }
    
    return topic;
  }
  
  /**
   * Creates IAM role for GPU instances with necessary permissions
   */
  private createGpuInstanceRole(uniqueSuffix: string): iam.Role {
    const role = new iam.Role(this, 'GpuInstanceRole', {
      roleName: `gpu-workload-role-${uniqueSuffix}`,
      description: 'IAM role for GPU instances with Systems Manager and CloudWatch permissions',
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy')
      ]
    });
    
    // Add custom policy for GPU metrics publishing
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'cloudwatch:PutMetricData',
        'ec2:DescribeVolumes',
        'ec2:DescribeTags',
        'logs:PutLogEvents',
        'logs:CreateLogGroup',
        'logs:CreateLogStream'
      ],
      resources: ['*']
    }));
    
    return role;
  }
  
  /**
   * Creates security group for GPU instances
   */
  private createSecurityGroup(uniqueSuffix: string): ec2.SecurityGroup {
    const sg = new ec2.SecurityGroup(this, 'GpuSecurityGroup', {
      securityGroupName: `gpu-workload-sg-${uniqueSuffix}`,
      description: 'Security group for GPU workloads with SSH and Jupyter access',
      vpc: this.vpc,
      allowAllOutbound: true
    });
    
    // Allow SSH access (consider restricting source IP)
    sg.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(22),
      'SSH access for GPU instance management'
    );
    
    // Allow Jupyter/TensorBoard access from within security group
    sg.addIngressRule(
      sg,
      ec2.Port.tcp(8888),
      'Jupyter notebook and TensorBoard access'
    );
    
    // Allow HTTPS for package downloads and API access
    sg.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'HTTPS for package downloads and AWS API access'
    );
    
    return sg;
  }
  
  /**
   * Creates EC2 key pair for SSH access
   */
  private createKeyPair(uniqueSuffix: string): ec2.CfnKeyPair {
    return new ec2.CfnKeyPair(this, 'GpuKeyPair', {
      keyName: `gpu-workload-key-${uniqueSuffix}`,
      keyType: 'rsa',
      keyFormat: 'pem',
      tags: [{
        key: 'Name',
        value: `GPU Workload Key Pair ${uniqueSuffix}`
      }]
    });
  }
  
  /**
   * Gets the latest Deep Learning AMI
   */
  private getLatestDeepLearningAmi(): ec2.IMachineImage {
    return ec2.MachineImage.lookup({
      name: 'Deep Learning AMI*Ubuntu*',
      owners: ['amazon'],
      filters: {
        'state': ['available']
      }
    });
  }
  
  /**
   * Creates comprehensive user data script for GPU setup
   */
  private createGpuUserData(): ec2.UserData {
    const userData = ec2.UserData.forLinux();
    
    userData.addCommands(
      '#!/bin/bash',
      'set -e',
      '',
      '# Update system packages',
      'apt-get update -y',
      'apt-get install -y awscli unzip curl',
      '',
      '# Install NVIDIA drivers (if not already present in DLAMI)',
      'if ! nvidia-smi > /dev/null 2>&1; then',
      '  aws s3 cp --recursive s3://ec2-linux-nvidia-drivers/latest/ .',
      '  chmod +x NVIDIA-Linux-x86_64*.run',
      '  ./NVIDIA-Linux-x86_64*.run --silent',
      'fi',
      '',
      '# Install Docker for containerized workloads',
      'apt-get install -y docker.io',
      'systemctl start docker',
      'systemctl enable docker',
      'usermod -aG docker ubuntu',
      '',
      '# Install NVIDIA Container Toolkit',
      'distribution=$(. /etc/os-release;echo $ID$VERSION_ID)',
      'curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg',
      'curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \\',
      '  sed "s#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g" | \\',
      '  tee /etc/apt/sources.list.d/nvidia-container-toolkit.list',
      'apt-get update',
      'apt-get install -y nvidia-container-toolkit',
      'nvidia-ctk runtime configure --runtime=docker',
      'systemctl restart docker',
      '',
      '# Install Python ML frameworks',
      'pip3 install --upgrade pip',
      'pip3 install torch torchvision torchaudio tensorflow-gpu jupyter matplotlib pandas numpy scikit-learn',
      '',
      '# Install CloudWatch agent',
      'wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb',
      'dpkg -i amazon-cloudwatch-agent.deb',
      '',
      '# Configure GPU monitoring for CloudWatch',
      'cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << "EOF"',
      '{',
      '  "agent": {',
      '    "metrics_collection_interval": 60,',
      '    "run_as_user": "cwagent"',
      '  },',
      '  "metrics": {',
      '    "namespace": "GPU/EC2",',
      '    "metrics_collected": {',
      '      "nvidia_gpu": {',
      '        "measurement": [',
      '          "utilization_gpu",',
      '          "utilization_memory",',
      '          "temperature_gpu",',
      '          "power_draw"',
      '        ],',
      '        "metrics_collection_interval": 60',
      '      },',
      '      "cpu": {',
      '        "measurement": ["cpu_usage_idle", "cpu_usage_iowait", "cpu_usage_user", "cpu_usage_system"],',
      '        "metrics_collection_interval": 60',
      '      },',
      '      "disk": {',
      '        "measurement": ["used_percent"],',
      '        "metrics_collection_interval": 60,',
      '        "resources": ["*"]',
      '      },',
      '      "diskio": {',
      '        "measurement": ["io_time"],',
      '        "metrics_collection_interval": 60,',
      '        "resources": ["*"]',
      '      },',
      '      "mem": {',
      '        "measurement": ["mem_used_percent"],',
      '        "metrics_collection_interval": 60',
      '      }',
      '    }',
      '  },',
      '  "logs": {',
      '    "logs_collected": {',
      '      "files": {',
      '        "collect_list": [',
      '          {',
      '            "file_path": "/var/log/nvidia-installer.log",',
      '            "log_group_name": "/aws/ec2/gpu-workloads",',
      '            "log_stream_name": "{instance_id}/nvidia-installer.log"',
      '          }',
      '        ]',
      '      }',
      '    }',
      '  }',
      '}',
      'EOF',
      '',
      '# Start CloudWatch agent',
      '/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \\',
      '  -a fetch-config -m ec2 \\',
      '  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \\',
      '  -s',
      '',
      '# Create GPU monitoring script',
      'cat > /usr/local/bin/gpu-monitor.py << "EOF"',
      '#!/usr/bin/env python3',
      'import subprocess',
      'import json',
      'import time',
      'import boto3',
      'from datetime import datetime',
      '',
      'def get_gpu_metrics():',
      '    try:',
      '        result = subprocess.run([',
      '            "nvidia-smi", ',
      '            "--query-gpu=utilization.gpu,utilization.memory,temperature.gpu,power.draw",',
      '            "--format=csv,noheader,nounits"',
      '        ], capture_output=True, text=True)',
      '        ',
      '        if result.returncode == 0:',
      '            metrics = result.stdout.strip().split(", ")',
      '            return {',
      '                "gpu_util": float(metrics[0]),',
      '                "mem_util": float(metrics[1]),',
      '                "temperature": float(metrics[2]),',
      '                "power_draw": float(metrics[3])',
      '            }',
      '    except Exception as e:',
      '        print(f"Error getting GPU metrics: {e}")',
      '    return None',
      '',
      'def send_custom_metrics(metrics, instance_id):',
      '    cloudwatch = boto3.client("cloudwatch")',
      '    ',
      '    try:',
      '        cloudwatch.put_metric_data(',
      '            Namespace="GPU/Custom",',
      '            MetricData=[',
      '                {',
      '                    "MetricName": "GPUUtilization",',
      '                    "Value": metrics["gpu_util"],',
      '                    "Unit": "Percent",',
      '                    "Dimensions": [',
      '                        {"Name": "InstanceId", "Value": instance_id}',
      '                    ]',
      '                }',
      '            ]',
      '        )',
      '        print(f"Custom metrics sent: {metrics}")',
      '    except Exception as e:',
      '        print(f"Error sending custom metrics: {e}")',
      '',
      'if __name__ == "__main__":',
      '    instance_id = subprocess.check_output([',
      '        "curl", "-s", "http://169.254.169.254/latest/meta-data/instance-id"',
      '    ]).decode().strip()',
      '    ',
      '    while True:',
      '        metrics = get_gpu_metrics()',
      '        if metrics:',
      '            send_custom_metrics(metrics, instance_id)',
      '        time.sleep(60)',
      'EOF',
      '',
      'chmod +x /usr/local/bin/gpu-monitor.py',
      '',
      '# Create systemd service for GPU monitoring',
      'cat > /etc/systemd/system/gpu-monitor.service << "EOF"',
      '[Unit]',
      'Description=GPU Monitoring Service',
      'After=network.target',
      '',
      '[Service]',
      'Type=simple',
      'User=ubuntu',
      'ExecStart=/usr/bin/python3 /usr/local/bin/gpu-monitor.py',
      'Restart=always',
      'RestartSec=10',
      '',
      '[Install]',
      'WantedBy=multi-user.target',
      'EOF',
      '',
      'systemctl daemon-reload',
      'systemctl enable gpu-monitor.service',
      'systemctl start gpu-monitor.service',
      '',
      '# Signal completion',
      'echo "GPU setup completed successfully" > /tmp/gpu-setup-complete',
      'echo "$(date): GPU instance setup completed" >> /var/log/gpu-setup.log'
    );
    
    return userData;
  }
  
  /**
   * Creates P4 instance for ML training workloads
   */
  private createP4Instance(
    uniqueSuffix: string,
    ami: ec2.IMachineImage,
    userData: ec2.UserData,
    keyPair: ec2.CfnKeyPair,
    instanceType: string
  ): ec2.Instance {
    const instance = new ec2.Instance(this, 'P4Instance', {
      instanceName: `P4-ML-Training-${uniqueSuffix}`,
      instanceType: new ec2.InstanceType(instanceType),
      machineImage: ami,
      vpc: this.vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PUBLIC },
      securityGroup: this.securityGroup,
      role: this.gpuRole,
      userData: userData,
      keyName: keyPair.keyName,
      blockDevices: [
        {
          deviceName: '/dev/sda1',
          volume: ec2.BlockDeviceVolume.ebs(100, {
            volumeType: ec2.EbsDeviceVolumeType.GP3,
            iops: 3000,
            throughput: 125,
            encrypted: true
          })
        }
      ],
      detailedMonitoring: true
    });
    
    // Add tags for identification and cost tracking
    cdk.Tags.of(instance).add('Purpose', 'GPU-Workload');
    cdk.Tags.of(instance).add('InstanceClass', 'P4-Training');
    cdk.Tags.of(instance).add('CostCenter', 'ML-Research');
    
    return instance;
  }
  
  /**
   * Creates G4 spot fleet for cost-optimized inference workloads
   */
  private createG4SpotFleet(
    uniqueSuffix: string,
    ami: ec2.IMachineImage,
    userData: ec2.UserData,
    keyPair: ec2.CfnKeyPair,
    instanceType: string,
    maxSpotPrice: string,
    targetCapacity: number
  ): void {
    // Note: CDK doesn't have direct support for Spot Fleet, so we use CfnSpotFleet
    const spotFleetRole = new iam.Role(this, 'SpotFleetRole', {
      roleName: `aws-ec2-spot-fleet-tagging-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('spotfleet.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonEC2SpotFleetTaggingRole')
      ]
    });
    
    // Get subnet IDs for spot fleet configuration
    const publicSubnets = this.vpc.publicSubnets;
    
    const spotFleetConfig = {
      spotPrice: maxSpotPrice,
      targetCapacity: targetCapacity,
      allocationStrategy: 'lowestPrice',
      iamFleetRole: spotFleetRole.roleArn,
      replaceUnhealthyInstances: true,
      terminateInstancesWithExpiration: true,
      launchSpecifications: [
        {
          imageId: ami.getImage(this).imageId,
          instanceType: instanceType,
          keyName: keyPair.keyName,
          securityGroups: [
            {
              groupId: this.securityGroup.securityGroupId
            }
          ],
          subnetId: publicSubnets[0].subnetId,
          iamInstanceProfile: {
            arn: this.gpuRole.roleArn.replace(':role/', ':instance-profile/')
          },
          userData: cdk.Fn.base64(userData.render()),
          blockDeviceMappings: [
            {
              deviceName: '/dev/sda1',
              ebs: {
                volumeSize: 50,
                volumeType: 'gp3',
                encrypted: true,
                deleteOnTermination: true
              }
            }
          ],
          tagSpecifications: [
            {
              resourceType: 'instance',
              tags: [
                {
                  key: 'Name',
                  value: `G4-Spot-Inference-${uniqueSuffix}`
                },
                {
                  key: 'Purpose',
                  value: 'GPU-Workload'
                },
                {
                  key: 'InstanceClass',
                  value: 'G4-Inference'
                }
              ]
            }
          ]
        }
      ]
    };
    
    new ec2.CfnSpotFleet(this, 'G4SpotFleet', {
      spotFleetRequestConfigData: spotFleetConfig
    });
  }
  
  /**
   * Creates CloudWatch dashboard for GPU monitoring
   */
  private createGpuMonitoringDashboard(p4Instance: ec2.Instance): void {
    const dashboard = new cloudwatch.Dashboard(this, 'GpuMonitoringDashboard', {
      dashboardName: 'GPU-Workload-Monitoring',
      defaultInterval: cdk.Duration.minutes(5)
    });
    
    // GPU Utilization widget
    const gpuUtilizationWidget = new cloudwatch.GraphWidget({
      title: 'GPU Utilization',
      left: [
        new cloudwatch.Metric({
          namespace: 'GPU/EC2',
          metricName: 'utilization_gpu',
          dimensionsMap: {
            InstanceId: p4Instance.instanceId
          },
          statistic: 'Average'
        })
      ],
      width: 12,
      height: 6
    });
    
    // GPU Memory Utilization widget
    const gpuMemoryWidget = new cloudwatch.GraphWidget({
      title: 'GPU Memory Utilization',
      left: [
        new cloudwatch.Metric({
          namespace: 'GPU/EC2',
          metricName: 'utilization_memory',
          dimensionsMap: {
            InstanceId: p4Instance.instanceId
          },
          statistic: 'Average'
        })
      ],
      width: 12,
      height: 6
    });
    
    // GPU Temperature widget
    const gpuTemperatureWidget = new cloudwatch.GraphWidget({
      title: 'GPU Temperature',
      left: [
        new cloudwatch.Metric({
          namespace: 'GPU/EC2',
          metricName: 'temperature_gpu',
          dimensionsMap: {
            InstanceId: p4Instance.instanceId
          },
          statistic: 'Average'
        })
      ],
      width: 12,
      height: 6
    });
    
    // GPU Power Consumption widget
    const gpuPowerWidget = new cloudwatch.GraphWidget({
      title: 'GPU Power Consumption',
      left: [
        new cloudwatch.Metric({
          namespace: 'GPU/EC2',
          metricName: 'power_draw',
          dimensionsMap: {
            InstanceId: p4Instance.instanceId
          },
          statistic: 'Average'
        })
      ],
      width: 12,
      height: 6
    });
    
    // Add widgets to dashboard in a 2x2 grid layout
    dashboard.addWidgets(
      gpuUtilizationWidget,
      gpuMemoryWidget
    );
    dashboard.addWidgets(
      gpuTemperatureWidget,
      gpuPowerWidget
    );
    
    // Add instance metrics for context
    const instanceMetricsWidget = new cloudwatch.GraphWidget({
      title: 'Instance Metrics',
      left: [
        p4Instance.metricCpuUtilization(),
        new cloudwatch.Metric({
          namespace: 'AWS/EC2',
          metricName: 'NetworkIn',
          dimensionsMap: {
            InstanceId: p4Instance.instanceId
          }
        })
      ],
      width: 24,
      height: 6
    });
    
    dashboard.addWidgets(instanceMetricsWidget);
  }
  
  /**
   * Creates CloudWatch alarms for GPU performance monitoring
   */
  private createGpuAlarms(p4Instance: ec2.Instance): void {
    // High temperature alarm
    const highTempAlarm = new cloudwatch.Alarm(this, 'GpuHighTemperatureAlarm', {
      alarmName: 'GPU-High-Temperature',
      alarmDescription: 'GPU temperature exceeds safe operating threshold',
      metric: new cloudwatch.Metric({
        namespace: 'GPU/EC2',
        metricName: 'temperature_gpu',
        dimensionsMap: {
          InstanceId: p4Instance.instanceId
        },
        statistic: 'Average'
      }),
      threshold: 85,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      period: cdk.Duration.minutes(5)
    });
    
    highTempAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.alertTopic));
    
    // Low utilization alarm for cost optimization
    const lowUtilAlarm = new cloudwatch.Alarm(this, 'GpuLowUtilizationAlarm', {
      alarmName: 'GPU-Low-Utilization',
      alarmDescription: 'GPU utilization is consistently low - consider stopping instance',
      metric: new cloudwatch.Metric({
        namespace: 'GPU/EC2',
        metricName: 'utilization_gpu',
        dimensionsMap: {
          InstanceId: p4Instance.instanceId
        },
        statistic: 'Average'
      }),
      threshold: 10,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 3,
      period: cdk.Duration.minutes(30)
    });
    
    lowUtilAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.alertTopic));
    
    // Instance status check alarm
    const statusCheckAlarm = new cloudwatch.Alarm(this, 'InstanceStatusCheckAlarm', {
      alarmName: 'GPU-Instance-Status-Check-Failed',
      alarmDescription: 'GPU instance has failed status checks',
      metric: p4Instance.metricStatusCheckFailed(),
      threshold: 1,
      evaluationPeriods: 2
    });
    
    statusCheckAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.alertTopic));
  }
  
  /**
   * Creates Lambda function for automated cost optimization
   */
  private createCostOptimizationFunction(uniqueSuffix: string): void {
    // Create Lambda function for cost optimization
    const costOptimizerFunction = new lambda.Function(this, 'CostOptimizerFunction', {
      functionName: `gpu-cost-optimizer-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      description: 'Monitors GPU instance utilization and tags low-usage instances for review',
      code: lambda.Code.fromInline(`
import boto3
import json
from datetime import datetime, timedelta

def lambda_handler(event, context):
    ec2 = boto3.client('ec2')
    cloudwatch = boto3.client('cloudwatch')
    
    # Get GPU instances
    instances = ec2.describe_instances(
        Filters=[
            {'Name': 'tag:Purpose', 'Values': ['GPU-Workload']},
            {'Name': 'instance-state-name', 'Values': ['running']}
        ]
    )
    
    low_utilization_instances = []
    
    for reservation in instances['Reservations']:
        for instance in reservation['Instances']:
            instance_id = instance['InstanceId']
            
            # Check GPU utilization over last hour
            end_time = datetime.utcnow()
            start_time = end_time - timedelta(hours=1)
            
            try:
                metrics = cloudwatch.get_metric_statistics(
                    Namespace='GPU/EC2',
                    MetricName='utilization_gpu',
                    Dimensions=[
                        {'Name': 'InstanceId', 'Value': instance_id}
                    ],
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=300,
                    Statistics=['Average']
                )
                
                if metrics['Datapoints']:
                    avg_util = sum(dp['Average'] for dp in metrics['Datapoints']) / len(metrics['Datapoints'])
                    
                    # If utilization < 5% for an hour, consider stopping
                    if avg_util < 5:
                        print(f"Low utilization detected for {instance_id}: {avg_util:.2f}%")
                        low_utilization_instances.append({
                            'instance_id': instance_id,
                            'utilization': avg_util
                        })
                        
                        # Add tag for review
                        ec2.create_tags(
                            Resources=[instance_id],
                            Tags=[
                                {'Key': 'LowUtilization', 'Value': str(datetime.now())},
                                {'Key': 'ReviewForTermination', 'Value': 'true'},
                                {'Key': 'UtilizationPercentage', 'Value': f"{avg_util:.2f}"}
                            ]
                        )
                
            except Exception as e:
                print(f"Error checking metrics for {instance_id}: {e}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Cost optimization check completed',
            'low_utilization_instances': low_utilization_instances
        })
    }
      `)
    });
    
    // Grant permissions to Lambda function
    costOptimizerFunction.addToRolePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'ec2:DescribeInstances',
        'ec2:CreateTags',
        'cloudwatch:GetMetricStatistics'
      ],
      resources: ['*']
    }));
    
    // Create EventBridge rule to run cost optimizer every hour
    const costOptimizerRule = new events.Rule(this, 'CostOptimizerRule', {
      ruleName: `gpu-cost-optimizer-schedule-${uniqueSuffix}`,
      description: 'Runs GPU cost optimizer function every hour',
      schedule: events.Schedule.rate(cdk.Duration.hours(1))
    });
    
    costOptimizerRule.addTarget(new eventsTargets.LambdaFunction(costOptimizerFunction));
  }
  
  /**
   * Creates SSM documents for GPU instance management
   */
  private createSSMDocuments(uniqueSuffix: string): void {
    // SSM document for GPU status check
    new ssm.CfnDocument(this, 'GpuStatusCheckDocument', {
      documentType: 'Command',
      documentFormat: 'YAML',
      name: `GPU-Status-Check-${uniqueSuffix}`,
      content: {
        schemaVersion: '2.2',
        description: 'Check GPU status and utilization on EC2 instances',
        parameters: {},
        mainSteps: [
          {
            action: 'aws:runShellScript',
            name: 'checkGpuStatus',
            inputs: {
              runCommand: [
                '#!/bin/bash',
                'echo "=== GPU Status Check ==="',
                'nvidia-smi',
                'echo "=== GPU Processes ==="',
                'nvidia-smi pmon -c 1',
                'echo "=== System Load ==="',
                'uptime',
                'echo "=== Disk Usage ==="',
                'df -h',
                'echo "=== Memory Usage ==="',
                'free -h'
              ]
            }
          }
        ]
      }
    });
    
    // SSM document for GPU performance optimization
    new ssm.CfnDocument(this, 'GpuPerformanceOptimizationDocument', {
      documentType: 'Command',
      documentFormat: 'YAML',
      name: `GPU-Performance-Optimization-${uniqueSuffix}`,
      content: {
        schemaVersion: '2.2',
        description: 'Optimize GPU performance settings',
        parameters: {},
        mainSteps: [
          {
            action: 'aws:runShellScript',
            name: 'optimizeGpuPerformance',
            inputs: {
              runCommand: [
                '#!/bin/bash',
                'echo "=== Setting GPU Performance Mode ==="',
                'sudo nvidia-smi -pm 1',
                'echo "=== Setting Maximum GPU Clocks ==="',
                'sudo nvidia-smi -ac $(nvidia-smi --query-gpu=memory.max,graphics.max --format=csv,noheader,nounits | tr "," ",")',
                'echo "=== Checking Current Settings ==="',
                'nvidia-smi -q -d CLOCK'
              ]
            }
          }
        ]
      }
    });
  }
  
  /**
   * Creates CloudFormation outputs for important resource information
   */
  private createOutputs(p4Instance: ec2.Instance, keyPair: ec2.CfnKeyPair): void {
    new cdk.CfnOutput(this, 'P4InstanceId', {
      value: p4Instance.instanceId,
      description: 'Instance ID of the P4 ML training instance',
      exportName: `P4InstanceId-${this.stackName}`
    });
    
    new cdk.CfnOutput(this, 'P4InstancePublicIp', {
      value: p4Instance.instancePublicIp,
      description: 'Public IP address of the P4 instance',
      exportName: `P4InstancePublicIp-${this.stackName}`
    });
    
    new cdk.CfnOutput(this, 'KeyPairName', {
      value: keyPair.keyName!,
      description: 'Name of the EC2 key pair for SSH access',
      exportName: `KeyPairName-${this.stackName}`
    });
    
    new cdk.CfnOutput(this, 'SecurityGroupId', {
      value: this.securityGroup.securityGroupId,
      description: 'Security group ID for GPU instances',
      exportName: `SecurityGroupId-${this.stackName}`
    });
    
    new cdk.CfnOutput(this, 'SnsTopicArn', {
      value: this.alertTopic.topicArn,
      description: 'SNS topic ARN for GPU monitoring alerts',
      exportName: `SnsTopicArn-${this.stackName}`
    });
    
    new cdk.CfnOutput(this, 'CloudWatchDashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=GPU-Workload-Monitoring`,
      description: 'URL to the CloudWatch dashboard for GPU monitoring',
      exportName: `CloudWatchDashboardUrl-${this.stackName}`
    });
    
    new cdk.CfnOutput(this, 'SshCommand', {
      value: `ssh -i ${keyPair.keyName}.pem ubuntu@${p4Instance.instancePublicIp}`,
      description: 'SSH command to connect to the P4 instance',
      exportName: `SshCommand-${this.stackName}`
    });
  }
}

/**
 * CDK Application for GPU Workloads
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const config: GpuWorkloadsStackProps = {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1'
  },
  alertEmail: app.node.tryGetContext('alertEmail') || process.env.ALERT_EMAIL,
  p4InstanceType: app.node.tryGetContext('p4InstanceType') || 'p4d.24xlarge',
  g4InstanceType: app.node.tryGetContext('g4InstanceType') || 'g4dn.xlarge',
  maxSpotPrice: app.node.tryGetContext('maxSpotPrice') || '0.50',
  spotFleetTargetCapacity: app.node.tryGetContext('spotFleetTargetCapacity') || 2,
  vpcId: app.node.tryGetContext('vpcId')
};

new GpuWorkloadsStack(app, 'GpuWorkloadsStack', config);

app.synth();