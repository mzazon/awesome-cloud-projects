#!/bin/bash
# User data script for Kubernetes cluster installation

set -e

# Update system packages
yum update -y

# Install Docker
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

# Configure Docker daemon for Kubernetes
cat <<EOF > /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

systemctl restart docker

# Disable swap (required for Kubernetes)
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Configure sysctl for Kubernetes
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system

# Load required kernel modules
modprobe br_netfilter
echo 'br_netfilter' > /etc/modules-load.d/br_netfilter.conf

# Install Kubernetes components using new pkgs.k8s.io repository
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${kubernetes_version}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${kubernetes_version}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

# Install Kubernetes packages
yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

# Enable kubelet service
systemctl enable kubelet

# Configure kubelet with cloud provider
cat <<EOF > /etc/default/kubelet
KUBELET_EXTRA_ARGS=--cloud-provider=external
EOF

# Configure crictl for container runtime
cat <<EOF > /etc/crictl.yaml
runtime-endpoint: unix:///var/run/dockershim.sock
image-endpoint: unix:///var/run/dockershim.sock
timeout: 2
debug: false
pull-image-on-create: false
EOF

# Set up completion for kubectl
echo 'source <(kubectl completion bash)' >> /home/ec2-user/.bashrc
echo 'alias k=kubectl' >> /home/ec2-user/.bashrc
echo 'complete -F __start_kubectl k' >> /home/ec2-user/.bashrc

# Install useful tools for Kubernetes troubleshooting
yum install -y git curl wget jq

# Create directory for kubeconfig
mkdir -p /home/ec2-user/.kube
chown ec2-user:ec2-user /home/ec2-user/.kube

# Create a simple health check script for demo purposes
cat <<'EOF' > /home/ec2-user/health-check-server.py
#!/usr/bin/env python3
import http.server
import socketserver
import json
import os

PORT_8080 = 8080
PORT_9090 = 9090

class HealthHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            
            response = {
                'status': 'healthy',
                'service': 'k8s-demo-service',
                'instance_id': os.environ.get('AWS_INSTANCE_ID', 'unknown'),
                'timestamp': self.date_time_string()
            }
            self.wfile.write(json.dumps(response).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        # Suppress default log output
        pass

if __name__ == "__main__":
    import sys
    import threading
    
    def start_server(port):
        with socketserver.TCPServer(("", port), HealthHandler) as httpd:
            print(f"Health check server running on port {port}")
            httpd.serve_forever()
    
    # Start servers on both ports for demo purposes
    thread1 = threading.Thread(target=start_server, args=(PORT_8080,))
    thread2 = threading.Thread(target=start_server, args=(PORT_9090,))
    
    thread1.daemon = True
    thread2.daemon = True
    
    thread1.start()
    thread2.start()
    
    print("Health check servers started on ports 8080 and 9090")
    print("Press Ctrl+C to stop")
    
    try:
        while True:
            thread1.join(1)
            thread2.join(1)
    except KeyboardInterrupt:
        print("\nShutting down health check servers")
        sys.exit(0)
EOF

chmod +x /home/ec2-user/health-check-server.py
chown ec2-user:ec2-user /home/ec2-user/health-check-server.py

# Install Python 3 for health check server
yum install -y python3

# Create systemd service for health check servers
cat <<EOF > /etc/systemd/system/k8s-health-check.service
[Unit]
Description=Kubernetes Demo Health Check Service
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user
ExecStart=/usr/bin/python3 /home/ec2-user/health-check-server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the health check service
systemctl daemon-reload
systemctl enable k8s-health-check
systemctl start k8s-health-check

# Log completion
echo "Kubernetes node setup completed at $(date)" >> /var/log/k8s-setup.log
echo "Docker version: $(docker --version)" >> /var/log/k8s-setup.log
echo "Kubelet version: $(kubelet --version)" >> /var/log/k8s-setup.log

# Create a setup completion marker
touch /home/ec2-user/k8s-setup-complete
chown ec2-user:ec2-user /home/ec2-user/k8s-setup-complete