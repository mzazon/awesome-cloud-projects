# Create a specification file for the service
cat > service-spec.yaml << 'EOF'
service_name: "my-web-app"
desired_count: 2
cpu: "256"
memory: "512"
container_image: "nginx:latest"
container_port: 80
EOF

# Create the Proton service
aws proton create-service \
    --name "my-web-app" \
    --template-name "${service_template_name}" \
    --template-major-version "${split(".", service_template_version)[0]}" \
    --branch-name "main" \
    --repository-connection-arn "YOUR_REPOSITORY_CONNECTION_ARN" \
    --repository-id "YOUR_REPOSITORY_ID" \
    --spec file://service-spec.yaml