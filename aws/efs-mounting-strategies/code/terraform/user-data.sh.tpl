#!/bin/bash
# User data script for EC2 instance with EFS mounting capabilities
# This script installs EFS utilities and prepares mount points

# Update system packages
yum update -y

# Install EFS utilities for enhanced mounting capabilities
yum install -y amazon-efs-utils

# Install additional useful tools
yum install -y htop tree nfs-utils

# Create mount directories
mkdir -p /mnt/efs
mkdir -p /mnt/efs-standard

%{ for ap in access_points ~}
mkdir -p /mnt/efs-${ap.name}
%{ endfor ~}

# Set proper permissions for mount directories
chmod 755 /mnt/efs*

# Create helper scripts for mounting
cat > /home/ec2-user/mount-efs.sh << 'EOF'
#!/bin/bash
# Helper script for mounting EFS file system

EFS_ID="${efs_id}"
AWS_REGION="${aws_region}"

echo "=== EFS Mounting Helper Script ==="
echo "EFS ID: $EFS_ID"
echo "Region: $AWS_REGION"
echo ""

# Function to mount using standard NFS
mount_nfs() {
    echo "Mounting EFS using standard NFS..."
    sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,intr,timeo=600,retrans=2 \
        $EFS_ID.efs.$AWS_REGION.amazonaws.com:/ /mnt/efs-standard
    
    if [ $? -eq 0 ]; then
        echo "✅ Standard NFS mount successful"
    else
        echo "❌ Standard NFS mount failed"
    fi
}

# Function to mount using EFS utils
mount_efs_utils() {
    echo "Mounting EFS using EFS utils with TLS..."
    sudo mount -t efs -o tls $EFS_ID:/ /mnt/efs
    
    if [ $? -eq 0 ]; then
        echo "✅ EFS utils mount successful"
    else
        echo "❌ EFS utils mount failed"
    fi
}

# Function to mount access points
mount_access_points() {
    echo "Mounting EFS access points..."
    
%{ for ap in access_points ~}
    echo "Mounting ${ap.name} access point..."
    sudo mount -t efs -o tls,accesspoint=${ap.id} $EFS_ID:/ /mnt/efs-${ap.name}
    
    if [ $? -eq 0 ]; then
        echo "✅ ${ap.name} access point mount successful"
    else
        echo "❌ ${ap.name} access point mount failed"
    fi
    
%{ endfor ~}
}

# Function to show mount status
show_mounts() {
    echo ""
    echo "=== Current EFS Mounts ==="
    df -h | grep -E "(efs|Filesystem)" | head -1
    df -h | grep efs || echo "No EFS mounts found"
    echo ""
}

# Function to unmount all EFS mounts
unmount_all() {
    echo "Unmounting all EFS mounts..."
    sudo umount -f /mnt/efs* 2>/dev/null || true
    echo "✅ All EFS mounts unmounted"
}

# Function to configure automatic mounting
configure_fstab() {
    echo "Configuring automatic mounting in /etc/fstab..."
    
    # Backup original fstab
    sudo cp /etc/fstab /etc/fstab.backup
    
    # Add EFS entries
    echo "$EFS_ID.efs.$AWS_REGION.amazonaws.com:/ /mnt/efs efs defaults,_netdev,tls" | sudo tee -a /etc/fstab
    echo "$EFS_ID.efs.$AWS_REGION.amazonaws.com:/ /mnt/efs-standard efs defaults,_netdev,nfsvers=4.1,rsize=1048576,wsize=1048576,hard,intr,timeo=600,retrans=2" | sudo tee -a /etc/fstab
    
%{ for ap in access_points ~}
    echo "$EFS_ID.efs.$AWS_REGION.amazonaws.com:/ /mnt/efs-${ap.name} efs defaults,_netdev,tls,accesspoint=${ap.id}" | sudo tee -a /etc/fstab
%{ endfor ~}
    
    echo "✅ fstab configured for automatic mounting"
}

# Function to test file operations
test_file_operations() {
    echo "Testing file operations on EFS mounts..."
    
    # Test main EFS mount
    if mountpoint -q /mnt/efs; then
        echo "Testing write to main EFS mount..."
        echo "Hello from EFS main mount - $(date)" | sudo tee /mnt/efs/test-main.txt
        cat /mnt/efs/test-main.txt
        echo "✅ Main EFS mount write test successful"
    fi
    
    # Test access points
%{ for ap in access_points ~}
    if mountpoint -q /mnt/efs-${ap.name}; then
        echo "Testing write to ${ap.name} access point..."
        echo "Hello from ${ap.name} access point - $(date)" | sudo tee /mnt/efs-${ap.name}/test-${ap.name}.txt
        cat /mnt/efs-${ap.name}/test-${ap.name}.txt
        echo "✅ ${ap.name} access point write test successful"
    fi
    
%{ endfor ~}
}

# Main menu
case "$1" in
    "nfs")
        mount_nfs
        ;;
    "efs")
        mount_efs_utils
        ;;
    "access-points")
        mount_access_points
        ;;
    "all")
        mount_efs_utils
        mount_access_points
        ;;
    "show")
        show_mounts
        ;;
    "unmount")
        unmount_all
        ;;
    "fstab")
        configure_fstab
        ;;
    "test")
        test_file_operations
        ;;
    *)
        echo "Usage: $0 {nfs|efs|access-points|all|show|unmount|fstab|test}"
        echo ""
        echo "Commands:"
        echo "  nfs            - Mount using standard NFS"
        echo "  efs            - Mount using EFS utils with TLS"
        echo "  access-points  - Mount all access points"
        echo "  all            - Mount main EFS and all access points"
        echo "  show           - Show current mounts"
        echo "  unmount        - Unmount all EFS mounts"
        echo "  fstab          - Configure automatic mounting"
        echo "  test           - Test file operations"
        echo ""
        echo "Examples:"
        echo "  $0 all     # Mount everything"
        echo "  $0 show    # Show current mounts"
        echo "  $0 test    # Test file operations"
        ;;
esac
EOF

# Make the script executable
chmod +x /home/ec2-user/mount-efs.sh

# Create performance testing script
cat > /home/ec2-user/test-efs-performance.sh << 'EOF'
#!/bin/bash
# EFS Performance Testing Script

echo "=== EFS Performance Testing ==="
echo "Testing EFS performance with different scenarios..."
echo ""

# Test write performance
test_write_performance() {
    local mount_point=$1
    local test_name=$2
    
    if mountpoint -q $mount_point; then
        echo "Testing write performance for $test_name..."
        echo "Writing 100MB file..."
        time dd if=/dev/zero of=$mount_point/test-write.dat bs=1M count=100 2>/dev/null
        
        echo "File size: $(du -h $mount_point/test-write.dat | cut -f1)"
        rm -f $mount_point/test-write.dat
        echo ""
    else
        echo "$mount_point is not mounted, skipping $test_name test"
        echo ""
    fi
}

# Test read performance
test_read_performance() {
    local mount_point=$1
    local test_name=$2
    
    if mountpoint -q $mount_point; then
        echo "Testing read performance for $test_name..."
        # Create test file first
        dd if=/dev/zero of=$mount_point/test-read.dat bs=1M count=100 2>/dev/null
        
        echo "Reading 100MB file..."
        time dd if=$mount_point/test-read.dat of=/dev/null bs=1M 2>/dev/null
        
        rm -f $mount_point/test-read.dat
        echo ""
    else
        echo "$mount_point is not mounted, skipping $test_name test"
        echo ""
    fi
}

# Test small file operations
test_small_files() {
    local mount_point=$1
    local test_name=$2
    
    if mountpoint -q $mount_point; then
        echo "Testing small file operations for $test_name..."
        mkdir -p $mount_point/small-files-test
        
        echo "Creating 1000 small files..."
        time (
            for i in $(seq 1 1000); do
                echo "Test file $i" > $mount_point/small-files-test/file-$i.txt
            done
        )
        
        echo "Reading 1000 small files..."
        time (
            for i in $(seq 1 1000); do
                cat $mount_point/small-files-test/file-$i.txt > /dev/null
            done
        )
        
        echo "Deleting 1000 small files..."
        time rm -rf $mount_point/small-files-test
        echo ""
    else
        echo "$mount_point is not mounted, skipping $test_name test"
        echo ""
    fi
}

# Run performance tests
echo "Make sure EFS is mounted before running performance tests."
echo "Run './mount-efs.sh all' to mount all EFS file systems."
echo ""

# Test main EFS mount
test_write_performance "/mnt/efs" "Main EFS Mount"
test_read_performance "/mnt/efs" "Main EFS Mount"
test_small_files "/mnt/efs" "Main EFS Mount"

# Test access points
%{ for ap in access_points ~}
test_write_performance "/mnt/efs-${ap.name}" "${ap.name} Access Point"
test_read_performance "/mnt/efs-${ap.name}" "${ap.name} Access Point"
%{ endfor ~}

echo "=== Performance Testing Complete ==="
echo "For production workloads, consider:"
echo "- Using provisioned throughput for consistent performance"
echo "- Optimizing mount options for your specific use case"
echo "- Monitoring CloudWatch metrics for performance insights"
EOF

# Make the performance testing script executable
chmod +x /home/ec2-user/test-efs-performance.sh

# Create a simple monitoring script
cat > /home/ec2-user/monitor-efs.sh << 'EOF'
#!/bin/bash
# EFS Monitoring Script

echo "=== EFS Monitoring Dashboard ==="
echo "Timestamp: $(date)"
echo ""

# Show current mounts
echo "Current EFS Mounts:"
df -h | grep -E "(Filesystem|efs)" | head -1
df -h | grep efs || echo "No EFS mounts found"
echo ""

# Show mount statistics
echo "NFS Mount Statistics:"
nfsstat -m 2>/dev/null | grep -A 10 "${efs_id}" || echo "No NFS statistics available"
echo ""

# Show disk usage
echo "EFS Disk Usage:"
for mount in $(df | grep efs | awk '{print $6}'); do
    echo "Mount: $mount"
    du -sh $mount/* 2>/dev/null || echo "  No files found"
    echo ""
done

# Show system resources
echo "System Resources:"
echo "Memory Usage:"
free -h
echo ""
echo "CPU Usage:"
top -bn1 | grep "Cpu(s)" || echo "CPU info not available"
echo ""

# Show network connectivity to EFS
echo "Network Connectivity:"
ping -c 3 ${efs_id}.efs.${aws_region}.amazonaws.com 2>/dev/null || echo "Ping to EFS failed"
echo ""
EOF

# Make the monitoring script executable
chmod +x /home/ec2-user/monitor-efs.sh

# Create a simple info script
cat > /home/ec2-user/efs-info.sh << 'EOF'
#!/bin/bash
# EFS Information Script

echo "=== EFS Configuration Information ==="
echo "EFS ID: ${efs_id}"
echo "AWS Region: ${aws_region}"
echo "EFS DNS Name: ${efs_id}.efs.${aws_region}.amazonaws.com"
echo ""

echo "Available Scripts:"
echo "  ./mount-efs.sh          - Mount/unmount EFS file systems"
echo "  ./test-efs-performance.sh - Test EFS performance"
echo "  ./monitor-efs.sh        - Monitor EFS status"
echo "  ./efs-info.sh           - Show this information"
echo ""

echo "Quick Start:"
echo "  1. Mount EFS: ./mount-efs.sh all"
echo "  2. Test operations: ./mount-efs.sh test"
echo "  3. Monitor status: ./monitor-efs.sh"
echo "  4. Test performance: ./test-efs-performance.sh"
echo ""

echo "Access Points:"
%{ for ap in access_points ~}
echo "  ${ap.name}: ${ap.id}"
%{ endfor ~}
echo ""

echo "Mount Points:"
echo "  /mnt/efs           - Main EFS mount (EFS utils)"
echo "  /mnt/efs-standard  - Standard NFS mount"
%{ for ap in access_points ~}
echo "  /mnt/efs-${ap.name}    - ${ap.name} access point"
%{ endfor ~}
echo ""
EOF

# Make the info script executable
chmod +x /home/ec2-user/efs-info.sh

# Change ownership of scripts to ec2-user
chown ec2-user:ec2-user /home/ec2-user/*.sh

# Create a simple welcome message
cat > /home/ec2-user/README.txt << 'EOF'
Welcome to the EFS Mounting Strategies Demo Instance!

This instance is configured with Amazon EFS utilities and helper scripts
to demonstrate different EFS mounting strategies.

Available Scripts:
==================
- mount-efs.sh: Mount/unmount EFS file systems
- test-efs-performance.sh: Test EFS performance
- monitor-efs.sh: Monitor EFS status
- efs-info.sh: Show configuration information

Quick Start:
============
1. Run './efs-info.sh' to see configuration
2. Run './mount-efs.sh all' to mount all EFS file systems
3. Run './mount-efs.sh test' to test file operations
4. Run './monitor-efs.sh' to monitor status

EFS Information:
================
EFS ID: ${efs_id}
Region: ${aws_region}
DNS: ${efs_id}.efs.${aws_region}.amazonaws.com

For more information, see the Terraform outputs or AWS documentation.
EOF

# Change ownership of README to ec2-user
chown ec2-user:ec2-user /home/ec2-user/README.txt

# Log the completion
echo "EFS demo instance setup completed at $(date)" > /var/log/efs-setup.log
echo "EFS ID: ${efs_id}" >> /var/log/efs-setup.log
echo "Region: ${aws_region}" >> /var/log/efs-setup.log

# Print completion message
echo "EFS mounting strategies demo setup complete!"
echo "Check /home/ec2-user/README.txt for instructions."