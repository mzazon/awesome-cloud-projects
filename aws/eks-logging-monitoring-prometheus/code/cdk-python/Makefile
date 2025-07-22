# Makefile for EKS Observability CDK Python Application

# Variables
PYTHON = python3
PIP = pip
VENV = venv
CDK = cdk
KUBECTL = kubectl

# Colors for output
RED = \033[0;31m
GREEN = \033[0;32m
YELLOW = \033[0;33m
BLUE = \033[0;34m
NC = \033[0m # No Color

# Default target
.PHONY: help
help:
	@echo "$(BLUE)EKS Observability CDK Python Application$(NC)"
	@echo "$(BLUE)========================================$(NC)"
	@echo ""
	@echo "$(GREEN)Available targets:$(NC)"
	@echo "  $(YELLOW)setup$(NC)          - Set up the development environment"
	@echo "  $(YELLOW)install$(NC)        - Install Python dependencies"
	@echo "  $(YELLOW)bootstrap$(NC)      - Bootstrap CDK in AWS account"
	@echo "  $(YELLOW)synth$(NC)          - Synthesize CloudFormation template"
	@echo "  $(YELLOW)deploy$(NC)         - Deploy the CDK stack"
	@echo "  $(YELLOW)destroy$(NC)        - Destroy the CDK stack"
	@echo "  $(YELLOW)diff$(NC)           - Show differences between deployed and current stack"
	@echo "  $(YELLOW)test$(NC)           - Run tests"
	@echo "  $(YELLOW)lint$(NC)           - Run linting tools"
	@echo "  $(YELLOW)format$(NC)         - Format code"
	@echo "  $(YELLOW)clean$(NC)          - Clean build artifacts"
	@echo "  $(YELLOW)kubectl-config$(NC) - Configure kubectl for EKS cluster"
	@echo "  $(YELLOW)verify$(NC)         - Verify deployment"
	@echo "  $(YELLOW)logs$(NC)           - View application logs"
	@echo "  $(YELLOW)help$(NC)           - Show this help message"

# Setup development environment
.PHONY: setup
setup:
	@echo "$(BLUE)Setting up development environment...$(NC)"
	@if [ ! -d "$(VENV)" ]; then \
		echo "$(YELLOW)Creating virtual environment...$(NC)"; \
		$(PYTHON) -m venv $(VENV); \
	fi
	@echo "$(GREEN)Virtual environment ready. Run 'source venv/bin/activate' to activate.$(NC)"

# Install dependencies
.PHONY: install
install:
	@echo "$(BLUE)Installing dependencies...$(NC)"
	@if [ ! -f "$(VENV)/bin/activate" ]; then \
		echo "$(RED)Virtual environment not found. Run 'make setup' first.$(NC)"; \
		exit 1; \
	fi
	@. $(VENV)/bin/activate && $(PIP) install -r requirements.txt
	@echo "$(GREEN)Dependencies installed successfully.$(NC)"

# Bootstrap CDK
.PHONY: bootstrap
bootstrap:
	@echo "$(BLUE)Bootstrapping CDK...$(NC)"
	@$(CDK) bootstrap
	@echo "$(GREEN)CDK bootstrap completed.$(NC)"

# Synthesize CloudFormation template
.PHONY: synth
synth:
	@echo "$(BLUE)Synthesizing CloudFormation template...$(NC)"
	@$(CDK) synth
	@echo "$(GREEN)Template synthesized successfully.$(NC)"

# Deploy the stack
.PHONY: deploy
deploy:
	@echo "$(BLUE)Deploying CDK stack...$(NC)"
	@$(CDK) deploy --require-approval never
	@echo "$(GREEN)Stack deployed successfully.$(NC)"
	@echo "$(YELLOW)Run 'make kubectl-config' to configure kubectl.$(NC)"

# Destroy the stack
.PHONY: destroy
destroy:
	@echo "$(RED)Destroying CDK stack...$(NC)"
	@read -p "Are you sure you want to destroy the stack? (y/N) " -n 1 -r; \
	echo ""; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		$(CDK) destroy --force; \
		echo "$(GREEN)Stack destroyed successfully.$(NC)"; \
	else \
		echo "$(YELLOW)Destroy cancelled.$(NC)"; \
	fi

# Show differences
.PHONY: diff
diff:
	@echo "$(BLUE)Showing stack differences...$(NC)"
	@$(CDK) diff

# Run tests
.PHONY: test
test:
	@echo "$(BLUE)Running tests...$(NC)"
	@if [ ! -f "$(VENV)/bin/activate" ]; then \
		echo "$(RED)Virtual environment not found. Run 'make setup' first.$(NC)"; \
		exit 1; \
	fi
	@. $(VENV)/bin/activate && python -m pytest -v
	@echo "$(GREEN)Tests completed.$(NC)"

# Run linting
.PHONY: lint
lint:
	@echo "$(BLUE)Running linting tools...$(NC)"
	@if [ ! -f "$(VENV)/bin/activate" ]; then \
		echo "$(RED)Virtual environment not found. Run 'make setup' first.$(NC)"; \
		exit 1; \
	fi
	@. $(VENV)/bin/activate && flake8 app.py
	@. $(VENV)/bin/activate && mypy app.py
	@echo "$(GREEN)Linting completed.$(NC)"

# Format code
.PHONY: format
format:
	@echo "$(BLUE)Formatting code...$(NC)"
	@if [ ! -f "$(VENV)/bin/activate" ]; then \
		echo "$(RED)Virtual environment not found. Run 'make setup' first.$(NC)"; \
		exit 1; \
	fi
	@. $(VENV)/bin/activate && black app.py
	@. $(VENV)/bin/activate && isort app.py
	@echo "$(GREEN)Code formatted successfully.$(NC)"

# Clean build artifacts
.PHONY: clean
clean:
	@echo "$(BLUE)Cleaning build artifacts...$(NC)"
	@rm -rf cdk.out/
	@rm -rf __pycache__/
	@rm -rf *.egg-info/
	@rm -rf .pytest_cache/
	@rm -rf .mypy_cache/
	@find . -name "*.pyc" -delete
	@find . -name "*.pyo" -delete
	@echo "$(GREEN)Build artifacts cleaned.$(NC)"

# Configure kubectl
.PHONY: kubectl-config
kubectl-config:
	@echo "$(BLUE)Configuring kubectl...$(NC)"
	@CLUSTER_NAME=$$(aws cloudformation describe-stacks --stack-name EKSObservabilityStack --query "Stacks[0].Outputs[?OutputKey=='ClusterName'].OutputValue" --output text 2>/dev/null || echo ""); \
	if [ -z "$$CLUSTER_NAME" ]; then \
		echo "$(RED)Stack not found or cluster name not available. Deploy the stack first.$(NC)"; \
		exit 1; \
	fi; \
	aws eks update-kubeconfig --name $$CLUSTER_NAME; \
	echo "$(GREEN)kubectl configured successfully.$(NC)"

# Verify deployment
.PHONY: verify
verify:
	@echo "$(BLUE)Verifying deployment...$(NC)"
	@echo "$(YELLOW)Checking nodes...$(NC)"
	@$(KUBECTL) get nodes
	@echo "$(YELLOW)Checking pods...$(NC)"
	@$(KUBECTL) get pods --all-namespaces
	@echo "$(YELLOW)Checking services...$(NC)"
	@$(KUBECTL) get services --all-namespaces
	@echo "$(GREEN)Verification completed.$(NC)"

# View logs
.PHONY: logs
logs:
	@echo "$(BLUE)Viewing application logs...$(NC)"
	@echo "$(YELLOW)Fluent Bit logs:$(NC)"
	@$(KUBECTL) logs -n amazon-cloudwatch -l name=fluent-bit --tail=20
	@echo "$(YELLOW)Sample application logs:$(NC)"
	@$(KUBECTL) logs -l app=sample-app --tail=20

# Full setup and deployment
.PHONY: all
all: setup install bootstrap synth deploy kubectl-config verify
	@echo "$(GREEN)Full setup and deployment completed!$(NC)"

# Development workflow
.PHONY: dev
dev: format lint test synth
	@echo "$(GREEN)Development workflow completed!$(NC)"

# Quick deployment (skip tests)
.PHONY: quick-deploy
quick-deploy: synth deploy
	@echo "$(GREEN)Quick deployment completed!$(NC)"

# Show CDK outputs
.PHONY: outputs
outputs:
	@echo "$(BLUE)CDK Stack Outputs:$(NC)"
	@aws cloudformation describe-stacks --stack-name EKSObservabilityStack --query "Stacks[0].Outputs" --output table

# Show resource usage
.PHONY: status
status:
	@echo "$(BLUE)Resource Status:$(NC)"
	@echo "$(YELLOW)EKS Cluster:$(NC)"
	@aws eks describe-cluster --name $$(aws cloudformation describe-stacks --stack-name EKSObservabilityStack --query "Stacks[0].Outputs[?OutputKey=='ClusterName'].OutputValue" --output text) --query "cluster.{Name:name,Status:status,Version:version}" --output table
	@echo "$(YELLOW)Node Groups:$(NC)"
	@$(KUBECTL) get nodes -o wide
	@echo "$(YELLOW)Pods by Namespace:$(NC)"
	@$(KUBECTL) get pods --all-namespaces -o wide