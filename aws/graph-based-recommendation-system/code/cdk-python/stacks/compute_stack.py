"""
Compute Stack for Neptune Client Access

This stack creates EC2 infrastructure for connecting to Neptune:
- EC2 instance in public subnet for Gremlin client access
- IAM role with Neptune and S3 access permissions
- Security group configuration for Neptune connectivity
- User data script for automatic software installation
"""

from aws_cdk import (
    Stack,
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_s3 as s3,
    CfnOutput,
)
from constructs import Construct


class ComputeStack(Stack):
    """
    Creates EC2 infrastructure for Neptune client access.
    
    This stack provides a secure EC2 instance that can connect
    to Neptune cluster and access sample data from S3.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        vpc: ec2.Vpc,
        public_subnet: ec2.Subnet,
        neptune_security_group: ec2.SecurityGroup,
        neptune_endpoint: str,
        s3_bucket: s3.Bucket,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.vpc = vpc
        self.public_subnet = public_subnet
        self.neptune_security_group = neptune_security_group
        self.neptune_endpoint = neptune_endpoint
        self.s3_bucket = s3_bucket

        # Create IAM role for EC2 instance
        self.ec2_role = iam.Role(
            self, "NeptuneClientRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            description="IAM role for Neptune client EC2 instance",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore"),
            ],
        )

        # Add Neptune access permissions
        self.ec2_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "neptune-db:*",
                    "neptune:*",
                ],
                resources=["*"],
            )
        )

        # Add S3 access permissions for sample data
        self.s3_bucket.grant_read(self.ec2_role)

        # Add CloudWatch logging permissions
        self.ec2_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                    "logs:DescribeLogStreams",
                ],
                resources=["*"],
            )
        )

        # Create instance profile
        self.instance_profile = iam.CfnInstanceProfile(
            self, "NeptuneClientInstanceProfile",
            roles=[self.ec2_role.role_name],
        )

        # Create key pair for EC2 access
        self.key_pair = ec2.CfnKeyPair(
            self, "NeptuneClientKeyPair",
            key_name="neptune-client-keypair",
            description="Key pair for Neptune client EC2 instance",
        )

        # Create security group for EC2 instance
        self.ec2_security_group = ec2.SecurityGroup(
            self, "NeptuneClientSecurityGroup",
            vpc=self.vpc,
            description="Security group for Neptune client EC2 instance",
            allow_all_outbound=True,
        )

        # Allow SSH access (consider restricting source IP in production)
        self.ec2_security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(22),
            description="Allow SSH access"
        )

        # Add EC2 security group to Neptune security group for access
        self.neptune_security_group.add_ingress_rule(
            peer=self.ec2_security_group,
            connection=ec2.Port.tcp(8182),
            description="Allow Neptune access from EC2 client"
        )

        # User data script for EC2 instance setup
        user_data_script = f"""#!/bin/bash
yum update -y
yum install -y python3 python3-pip git java-11-amazon-corretto

# Install Python packages for Gremlin
pip3 install gremlinpython boto3 requests

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# Download Apache TinkerPop Gremlin Console
cd /opt
wget https://archive.apache.org/dist/tinkerpop/3.7.0/apache-tinkerpop-gremlin-console-3.7.0-bin.zip
unzip apache-tinkerpop-gremlin-console-3.7.0-bin.zip
ln -s apache-tinkerpop-gremlin-console-3.7.0 gremlin-console
chown -R ec2-user:ec2-user /opt/gremlin-console

# Create environment file
cat > /home/ec2-user/.neptune-env << 'EOL'
export NEPTUNE_ENDPOINT={self.neptune_endpoint}
export S3_BUCKET={self.s3_bucket.bucket_name}
export AWS_DEFAULT_REGION={self.region}
EOL

# Create connection test script
cat > /home/ec2-user/test-connection.py << 'EOL'
#!/usr/bin/env python3
import os
import sys
from gremlin_python.driver import client
from gremlin_python.driver.driver_remote_connection import DriverRemoteConnection
from gremlin_python.structure.graph import Graph

def test_neptune_connection():
    try:
        endpoint = os.environ.get('NEPTUNE_ENDPOINT')
        if not endpoint:
            print("❌ NEPTUNE_ENDPOINT environment variable not set")
            return False
            
        # Create connection
        connection = DriverRemoteConnection(f'wss://{{endpoint}}:8182/gremlin', 'g')
        g = Graph().traversal().withRemote(connection)
        
        # Test basic connectivity
        vertex_count = g.V().count().next()
        edge_count = g.E().count().next()
        
        print(f"✅ Connected to Neptune successfully!")
        print(f"Graph contains {{vertex_count}} vertices and {{edge_count}} edges")
        
        # Test sample queries if data exists
        if vertex_count > 0:
            users = g.V().hasLabel('user').valueMap().limit(3).toList()
            products = g.V().hasLabel('product').valueMap().limit(3).toList()
            
            print("\\nSample Users:")
            for user in users:
                print(f"  {{user}}")
            
            print("\\nSample Products:")
            for product in products:
                print(f"  {{product}}")
        
        connection.close()
        return True
        
    except Exception as e:
        print(f"❌ Connection failed: {{e}}")
        return False

if __name__ == "__main__":
    test_neptune_connection()
EOL

chmod +x /home/ec2-user/test-connection.py

# Create sample data download script
cat > /home/ec2-user/download-sample-data.sh << 'EOL'
#!/bin/bash
source ~/.neptune-env
mkdir -p ~/sample-data
aws s3 sync s3://${{S3_BUCKET}}/sample-data/ ~/sample-data/
echo "✅ Sample data downloaded to ~/sample-data/"
EOL

chmod +x /home/ec2-user/download-sample-data.sh

# Set ownership for ec2-user
chown -R ec2-user:ec2-user /home/ec2-user/

# Add environment variables to .bashrc
echo "source ~/.neptune-env" >> /home/ec2-user/.bashrc

# Create systemd service for CloudWatch agent (optional)
# This enables monitoring of the EC2 instance
cat > /etc/systemd/system/neptune-client-setup.service << 'EOL'
[Unit]
Description=Neptune Client Setup Service
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "source /home/ec2-user/.neptune-env && /home/ec2-user/download-sample-data.sh"
User=ec2-user
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOL

systemctl enable neptune-client-setup.service
systemctl start neptune-client-setup.service

# Signal CloudFormation that setup is complete
/opt/aws/bin/cfn-signal -e $? --stack {self.stack_name} --resource EC2Instance --region {self.region}
"""

        # Get latest Amazon Linux 2023 AMI
        amzn_linux = ec2.MachineImage.latest_amazon_linux2023(
            edition=ec2.AmazonLinuxEdition.STANDARD,
            virtualization=ec2.AmazonLinuxVirt.HVM,
            storage=ec2.AmazonLinuxStorage.GENERAL_PURPOSE,
        )

        # Create EC2 instance
        self.ec2_instance = ec2.Instance(
            self, "NeptuneClientInstance",
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.T3, ec2.InstanceSize.MEDIUM
            ),
            machine_image=amzn_linux,
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(subnets=[self.public_subnet]),
            security_group=self.ec2_security_group,
            role=self.ec2_role,
            key_name=self.key_pair.key_name,
            user_data=ec2.UserData.custom(user_data_script),
            source_dest_check=False,
        )

        # Outputs
        CfnOutput(
            self, "EC2InstanceId",
            value=self.ec2_instance.instance_id,
            description="EC2 instance ID for Neptune client",
            export_name="NeptuneClientInstanceId"
        )

        CfnOutput(
            self, "EC2PublicIp",
            value=self.ec2_instance.instance_public_ip,
            description="EC2 instance public IP for SSH access",
            export_name="NeptuneClientPublicIp"
        )

        CfnOutput(
            self, "EC2PrivateIp",
            value=self.ec2_instance.instance_private_ip,
            description="EC2 instance private IP",
            export_name="NeptuneClientPrivateIp"
        )

        CfnOutput(
            self, "KeyPairName",
            value=self.key_pair.key_name,
            description="Key pair name for SSH access",
            export_name="NeptuneClientKeyPairName"
        )

        CfnOutput(
            self, "SSHConnectionCommand",
            value=f"aws ec2-instance-connect ssh --instance-id {self.ec2_instance.instance_id} --os-user ec2-user",
            description="SSH connection command using EC2 Instance Connect",
            export_name="NeptuneClientSSHCommand"
        )