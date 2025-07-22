#!/bin/bash

#==============================================================================
# PostgreSQL Setup Script for Azure VMSS
# This script configures PostgreSQL on Ubuntu for high-performance workloads
# with Azure Elastic SAN integration
#==============================================================================

set -e

# Log all output to a file
exec > >(tee -a /var/log/postgres-setup.log)
exec 2>&1

echo "Starting PostgreSQL setup at $(date)"

#==============================================================================
# SYSTEM UPDATES AND DEPENDENCIES
#==============================================================================

# Update system packages
echo "Updating system packages..."
sudo apt-get update -y
sudo apt-get upgrade -y

# Install required packages
echo "Installing required packages..."
sudo apt-get install -y \
    postgresql \
    postgresql-contrib \
    open-iscsi \
    multipath-tools \
    lsscsi \
    sg3-utils \
    wget \
    curl \
    htop \
    iotop \
    sysstat \
    net-tools

#==============================================================================
# ISCSI CONFIGURATION FOR ELASTIC SAN
#==============================================================================

echo "Configuring iSCSI for Elastic SAN..."

# Enable and start iSCSI service
sudo systemctl enable iscsid
sudo systemctl start iscsid
sudo systemctl enable open-iscsi
sudo systemctl start open-iscsi

# Configure iSCSI initiator
sudo sed -i 's/^#node.startup = manual/node.startup = automatic/' /etc/iscsi/iscsid.conf
sudo sed -i 's/^#node.leading_login = No/node.leading_login = Yes/' /etc/iscsi/iscsid.conf

# Configure multipath
sudo tee /etc/multipath.conf > /dev/null <<EOF
defaults {
    user_friendly_names yes
    find_multipaths yes
    failback immediate
}

blacklist {
    devnode "^(ram|raw|loop|fd|md|dm-|sr|scd|st)[0-9]*"
    devnode "^hd[a-z]"
    devnode "^cciss!c[0-9]d[0-9]*"
}

devices {
    device {
        vendor "MSFT"
        product "Virtual HD"
        path_grouping_policy failover
        no_path_retry fail
        rr_weight priorities
    }
}
EOF

# Enable and start multipath
sudo systemctl enable multipathd
sudo systemctl start multipathd

#==============================================================================
# POSTGRESQL CONFIGURATION
#==============================================================================

echo "Configuring PostgreSQL..."

# Stop PostgreSQL service
sudo systemctl stop postgresql

# Create PostgreSQL data directory
sudo mkdir -p /var/lib/postgresql/data
sudo chown -R postgres:postgres /var/lib/postgresql/data

# Create PostgreSQL configuration
sudo -u postgres tee /etc/postgresql/14/main/postgresql.conf > /dev/null <<EOF
# Basic Settings
listen_addresses = '*'
port = 5432
max_connections = 200
shared_buffers = 256MB
effective_cache_size = 1GB
work_mem = 4MB
maintenance_work_mem = 64MB

# Write Ahead Logging
wal_level = replica
max_wal_size = 1GB
min_wal_size = 80MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB

# Query Tuning
random_page_cost = 1.1
effective_io_concurrency = 200
max_worker_processes = 8
max_parallel_workers_per_gather = 4
max_parallel_workers = 8

# Logging
logging_collector = on
log_directory = 'pg_log'
log_filename = 'postgresql-%a.log'
log_truncate_on_rotation = on
log_rotation_age = 1d
log_rotation_size = 100MB
log_min_duration_statement = 1000
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '

# Monitoring
shared_preload_libraries = 'pg_stat_statements'
track_activity_query_size = 2048
track_io_timing = on
track_functions = all
EOF

# Configure PostgreSQL host-based authentication
sudo -u postgres tee /etc/postgresql/14/main/pg_hba.conf > /dev/null <<EOF
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             postgres                                peer
local   all             all                                     peer
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5
host    all             all             0.0.0.0/0               md5
EOF

# Enable and start PostgreSQL
sudo systemctl enable postgresql
sudo systemctl start postgresql

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to start..."
sleep 10

# Create database user and database
echo "Creating database user and database..."
sudo -u postgres psql -c "CREATE USER dbadmin WITH PASSWORD 'SecurePass123!';"
sudo -u postgres psql -c "ALTER USER dbadmin CREATEDB;"
sudo -u postgres psql -c "CREATE DATABASE appdb OWNER dbadmin;"

# Create pg_stat_statements extension
sudo -u postgres psql -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"

#==============================================================================
# PERFORMANCE TUNING
#==============================================================================

echo "Configuring system for high performance..."

# Configure kernel parameters for database workloads
sudo tee -a /etc/sysctl.conf > /dev/null <<EOF

# Database performance tuning
vm.swappiness = 1
vm.dirty_background_ratio = 3
vm.dirty_ratio = 10
vm.dirty_expire_centisecs = 500
vm.dirty_writeback_centisecs = 100
kernel.shmmax = 4294967295
kernel.shmall = 268435456
kernel.sem = 250 32000 100 128
fs.file-max = 2097152
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
EOF

# Apply sysctl settings
sudo sysctl -p

# Configure limits for postgres user
sudo tee /etc/security/limits.d/postgres.conf > /dev/null <<EOF
postgres soft nofile 65536
postgres hard nofile 65536
postgres soft nproc 32768
postgres hard nproc 32768
postgres soft stack 10240
postgres hard stack 32768
EOF

#==============================================================================
# MONITORING AND LOGGING
#==============================================================================

echo "Setting up monitoring and logging..."

# Create monitoring scripts directory
sudo mkdir -p /opt/monitoring
sudo chown root:root /opt/monitoring

# Create PostgreSQL monitoring script
sudo tee /opt/monitoring/postgres-monitor.sh > /dev/null <<'EOF'
#!/bin/bash

# PostgreSQL monitoring script
LOG_FILE="/var/log/postgres-monitor.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$DATE] PostgreSQL Status Check" >> $LOG_FILE

# Check PostgreSQL service status
if systemctl is-active --quiet postgresql; then
    echo "[$DATE] PostgreSQL service: RUNNING" >> $LOG_FILE
else
    echo "[$DATE] PostgreSQL service: STOPPED" >> $LOG_FILE
fi

# Check database connections
CONNECTIONS=$(sudo -u postgres psql -t -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';")
echo "[$DATE] Active connections: $CONNECTIONS" >> $LOG_FILE

# Check database size
DB_SIZE=$(sudo -u postgres psql -t -c "SELECT pg_size_pretty(pg_database_size('appdb'));")
echo "[$DATE] Database size: $DB_SIZE" >> $LOG_FILE

# Check for long-running queries
LONG_QUERIES=$(sudo -u postgres psql -t -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active' AND query_start < now() - interval '5 minutes';")
echo "[$DATE] Long-running queries (>5min): $LONG_QUERIES" >> $LOG_FILE

echo "[$DATE] Monitoring complete" >> $LOG_FILE
EOF

sudo chmod +x /opt/monitoring/postgres-monitor.sh

# Set up cron job for monitoring
echo "*/5 * * * * /opt/monitoring/postgres-monitor.sh" | sudo crontab -u root -

#==============================================================================
# AZURE MONITORING AGENT
#==============================================================================

echo "Installing Azure monitoring agent..."

# Download and install Azure Monitor Agent
wget https://github.com/Microsoft/OMS-Agent-for-Linux/releases/download/OMSAgent_v1.13.27-0/omsagent-1.13.27-0.universal.x64.sh
sudo sh omsagent-1.13.27-0.universal.x64.sh --upgrade

# Clean up
rm -f omsagent-1.13.27-0.universal.x64.sh

#==============================================================================
# FINAL CONFIGURATION
#==============================================================================

echo "Finalizing configuration..."

# Create systemd service for custom initialization
sudo tee /etc/systemd/system/postgres-init.service > /dev/null <<EOF
[Unit]
Description=PostgreSQL Custom Initialization
After=postgresql.service
Requires=postgresql.service

[Service]
Type=oneshot
User=postgres
ExecStart=/bin/bash -c 'sleep 30 && /opt/monitoring/postgres-monitor.sh'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable postgres-init.service
sudo systemctl start postgres-init.service

# Configure automatic startup
sudo systemctl enable postgresql
sudo systemctl enable iscsid
sudo systemctl enable multipathd

# Create status file
echo "PostgreSQL setup completed successfully at $(date)" | sudo tee /var/log/postgres-setup-complete.log

echo "PostgreSQL setup completed successfully!"
echo "Database server is ready for connections"
echo "Default database: appdb"
echo "Database user: dbadmin"
echo "Monitoring script: /opt/monitoring/postgres-monitor.sh"
echo "Logs: /var/log/postgres-setup.log"