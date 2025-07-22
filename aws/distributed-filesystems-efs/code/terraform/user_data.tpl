#!/bin/bash
# User data script for EFS client instances

# Update system packages
yum update -y

# Install EFS utilities and CloudWatch agent
yum install -y amazon-efs-utils amazon-cloudwatch-agent

# Create mount directories
mkdir -p /mnt/efs
%{ for i, name in access_point_names ~}
mkdir -p /mnt/${name}
%{ endfor ~}

# Configure CloudWatch agent if log group is provided
%{ if log_group_name != "" ~}
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/messages",
                        "log_group_name": "${log_group_name}",
                        "log_stream_name": "{instance_id}/var/log/messages"
                    },
                    {
                        "file_path": "/var/log/efs-mount.log",
                        "log_group_name": "${log_group_name}",
                        "log_stream_name": "{instance_id}/var/log/efs-mount"
                    }
                ]
            }
        }
    }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config -m ec2 -s \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
%{ endif ~}

# Create EFS mount script
cat > /usr/local/bin/mount-efs.sh << 'EOF'
#!/bin/bash
LOG_FILE="/var/log/efs-mount.log"
EFS_ID="${efs_id}"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

# Mount main EFS file system
log_message "Mounting EFS file system: $EFS_ID"
mount -t efs -o tls,iam $EFS_ID:/ /mnt/efs
if [ $? -eq 0 ]; then
    log_message "Successfully mounted EFS file system"
else
    log_message "Failed to mount EFS file system"
    exit 1
fi

# Mount access points
%{ for i, id in access_point_ids ~}
log_message "Mounting access point: ${id}"
mount -t efs -o tls,iam,accesspoint=${id} $EFS_ID:/ /mnt/${access_point_names[i]}
if [ $? -eq 0 ]; then
    log_message "Successfully mounted access point: ${access_point_names[i]}"
else
    log_message "Failed to mount access point: ${access_point_names[i]}"
fi
%{ endfor ~}

# Add entries to fstab for persistent mounting
log_message "Adding entries to /etc/fstab for persistent mounting"
echo "$EFS_ID:/ /mnt/efs efs defaults,_netdev,tls,iam" >> /etc/fstab
%{ for i, id in access_point_ids ~}
echo "$EFS_ID:/ /mnt/${access_point_names[i]} efs defaults,_netdev,tls,iam,accesspoint=${id}" >> /etc/fstab
%{ endfor ~}

# Create test files
log_message "Creating test files"
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
echo "Hello from instance $INSTANCE_ID" > /mnt/efs/test-$INSTANCE_ID.txt
%{ for i, name in access_point_names ~}
echo "${name} content from instance $INSTANCE_ID" > /mnt/${name}/test-${name}-$INSTANCE_ID.txt
%{ endfor ~}

log_message "EFS mounting completed successfully"
EOF

# Make the script executable
chmod +x /usr/local/bin/mount-efs.sh

# Wait for EFS mount targets to be available
sleep 30

# Run the mount script
/usr/local/bin/mount-efs.sh

# Create a service to ensure EFS is mounted on boot
cat > /etc/systemd/system/efs-mount.service << 'EOF'
[Unit]
Description=Mount EFS file systems
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/mount-efs.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
systemctl enable efs-mount.service

# Install performance testing tools
yum install -y fio

# Create performance test script
cat > /usr/local/bin/test-efs-performance.sh << 'EOF'
#!/bin/bash
LOG_FILE="/var/log/efs-performance.log"

echo "EFS Performance Test - $(date)" | tee -a $LOG_FILE
echo "================================" | tee -a $LOG_FILE

# Test write performance
echo "Testing write performance..." | tee -a $LOG_FILE
fio --name=write-test --directory=/mnt/efs \
    --rw=write --bs=1M --size=100M --numjobs=4 \
    --time_based --runtime=30 --group_reporting \
    --output-format=json | tee -a $LOG_FILE

# Test read performance
echo "Testing read performance..." | tee -a $LOG_FILE
fio --name=read-test --directory=/mnt/efs \
    --rw=read --bs=1M --size=100M --numjobs=4 \
    --time_based --runtime=30 --group_reporting \
    --output-format=json | tee -a $LOG_FILE

# Show mount information
echo "Mount information:" | tee -a $LOG_FILE
df -h /mnt/efs | tee -a $LOG_FILE
mount | grep efs | tee -a $LOG_FILE

echo "Performance test completed - $(date)" | tee -a $LOG_FILE
EOF

chmod +x /usr/local/bin/test-efs-performance.sh

# Log completion
echo "$(date '+%Y-%m-%d %H:%M:%S') - User data script completed successfully" >> /var/log/efs-mount.log