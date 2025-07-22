# Create a specification file for the environment
cat > environment-spec.yaml << 'EOF'
vpc_cidr: "10.0.0.0/16"
environment_name: "my-environment"
EOF

# Create the Proton environment
aws proton create-environment \
    --name "my-environment" \
    --template-name "${environment_template_name}" \
    --template-major-version "${split(".", environment_template_version)[0]}" \
    --proton-service-role-arn "${proton_service_role_arn}" \
    --spec file://environment-spec.yaml