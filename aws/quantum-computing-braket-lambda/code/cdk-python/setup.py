"""
Setup configuration for AWS CDK Python application.
Hybrid quantum-classical computing pipeline with Amazon Braket and Lambda.
"""

from setuptools import setup, find_packages
import os

# Read the README file for long description
def read_readme():
    """Read README file for long description."""
    readme_path = os.path.join(os.path.dirname(__file__), 'README.md')
    if os.path.exists(readme_path):
        with open(readme_path, 'r', encoding='utf-8') as f:
            return f.read()
    return "Hybrid quantum-classical computing pipeline with Amazon Braket and Lambda"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements_path = os.path.join(os.path.dirname(__file__), 'requirements.txt')
    requirements = []
    
    if os.path.exists(requirements_path):
        with open(requirements_path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                # Skip empty lines and comments
                if line and not line.startswith('#'):
                    # Handle inline comments
                    if '#' in line:
                        line = line.split('#')[0].strip()
                    if line:
                        requirements.append(line)
    
    return requirements

# Project metadata
PACKAGE_NAME = "quantum-computing-pipeline"
VERSION = "1.0.0"
DESCRIPTION = "Hybrid quantum-classical computing pipeline with Amazon Braket and Lambda"
AUTHOR = "AWS CDK Team"
AUTHOR_EMAIL = "aws-cdk-team@amazon.com"
URL = "https://github.com/aws/aws-cdk"
LICENSE = "Apache-2.0"

# Python version requirements
PYTHON_REQUIRES = ">=3.8"

# Package classifiers
CLASSIFIERS = [
    "Development Status :: 4 - Beta",
    "Intended Audience :: Developers",
    "Intended Audience :: Science/Research",
    "License :: OSI Approved :: Apache Software License",
    "Programming Language :: Python :: 3",
    "Programming Language :: Python :: 3.8",
    "Programming Language :: Python :: 3.9",
    "Programming Language :: Python :: 3.10",
    "Programming Language :: Python :: 3.11",
    "Programming Language :: Python :: 3.12",
    "Topic :: Scientific/Engineering :: Physics",
    "Topic :: Software Development :: Libraries :: Python Modules",
    "Topic :: System :: Distributed Computing",
    "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
    "Operating System :: OS Independent",
    "Framework :: AWS CDK",
    "Framework :: AWS CDK :: 2",
]

# Keywords for PyPI
KEYWORDS = [
    "aws",
    "cdk",
    "quantum-computing",
    "amazon-braket",
    "lambda",
    "serverless",
    "hybrid-computing",
    "optimization",
    "infrastructure-as-code",
    "cloud-computing",
    "quantum-algorithms",
    "variational-quantum-algorithms",
    "quantum-machine-learning",
    "quantum-optimization",
    "quantum-simulation",
]

# Project URLs
PROJECT_URLS = {
    "Bug Reports": "https://github.com/aws/aws-cdk/issues",
    "Source": "https://github.com/aws/aws-cdk",
    "Documentation": "https://docs.aws.amazon.com/cdk/",
    "Amazon Braket": "https://aws.amazon.com/braket/",
    "AWS Lambda": "https://aws.amazon.com/lambda/",
    "Quantum Computing": "https://aws.amazon.com/quantum-computing/",
}

# Entry points for command line tools
ENTRY_POINTS = {
    "console_scripts": [
        "quantum-pipeline=quantum_computing_pipeline.cli:main",
    ],
}

# Additional package data
PACKAGE_DATA = {
    "quantum_computing_pipeline": [
        "templates/*.json",
        "templates/*.yaml",
        "schemas/*.json",
        "config/*.ini",
        "config/*.yaml",
        "docs/*.md",
        "examples/*.py",
        "examples/*.json",
    ],
}

# Exclude patterns for package discovery
EXCLUDE_PACKAGES = [
    "tests",
    "tests.*",
    "test_*",
    "*_test",
    "*.tests",
    "*.tests.*",
    "build",
    "dist",
    "*.egg-info",
    "__pycache__",
    ".pytest_cache",
    ".coverage",
    ".tox",
    ".git",
    ".github",
    "node_modules",
    "cdk.out",
    "*.tmp",
    "*.temp",
]

# Development dependencies (extras_require)
DEV_REQUIREMENTS = [
    "pytest>=7.0.0",
    "pytest-cov>=4.0.0",
    "black>=23.0.0",
    "flake8>=6.0.0",
    "mypy>=1.0.0",
    "pre-commit>=3.0.0",
    "sphinx>=5.0.0",
    "sphinx-rtd-theme>=1.0.0",
    "moto>=4.0.0",
    "responses>=0.23.0",
    "bandit>=1.7.0",
    "safety>=2.0.0",
    "isort>=5.0.0",
    "autopep8>=2.0.0",
]

# Testing dependencies
TEST_REQUIREMENTS = [
    "pytest>=7.0.0",
    "pytest-cov>=4.0.0",
    "pytest-mock>=3.0.0",
    "pytest-xdist>=3.0.0",
    "pytest-html>=3.0.0",
    "pytest-benchmark>=4.0.0",
    "hypothesis>=6.0.0",
    "factory-boy>=3.0.0",
    "moto>=4.0.0",
    "testcontainers>=3.0.0",
]

# Documentation dependencies
DOCS_REQUIREMENTS = [
    "sphinx>=5.0.0",
    "sphinx-rtd-theme>=1.0.0",
    "sphinx-autodoc-typehints>=1.24.0",
    "mkdocs>=1.4.0",
    "mkdocs-material>=8.0.0",
    "mkdocs-mermaid2-plugin>=0.6.0",
    "pdoc>=14.0.0",
]

# Quantum computing dependencies (optional)
QUANTUM_REQUIREMENTS = [
    "amazon-braket-sdk>=1.75.0",
    "pennylane>=0.33.1",
    "pennylane-braket>=0.33.0",
    "numpy>=1.24.0",
    "scipy>=1.10.0",
    "matplotlib>=3.7.0",
    "qiskit>=0.45.0",
    "cirq>=1.2.0",
]

# Performance monitoring dependencies
MONITORING_REQUIREMENTS = [
    "prometheus-client>=0.17.0",
    "statsd>=4.0.0",
    "sentry-sdk>=1.38.0",
    "datadog>=0.47.0",
    "newrelic>=8.0.0",
    "psutil>=5.9.0",
    "memory-profiler>=0.60.0",
]

# All extra requirements
EXTRAS_REQUIRE = {
    "dev": DEV_REQUIREMENTS,
    "test": TEST_REQUIREMENTS,
    "docs": DOCS_REQUIREMENTS,
    "quantum": QUANTUM_REQUIREMENTS,
    "monitoring": MONITORING_REQUIREMENTS,
    "all": (
        DEV_REQUIREMENTS + 
        TEST_REQUIREMENTS + 
        DOCS_REQUIREMENTS + 
        QUANTUM_REQUIREMENTS + 
        MONITORING_REQUIREMENTS
    ),
}

# Setup configuration
setup(
    name=PACKAGE_NAME,
    version=VERSION,
    description=DESCRIPTION,
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    author=AUTHOR,
    author_email=AUTHOR_EMAIL,
    url=URL,
    project_urls=PROJECT_URLS,
    license=LICENSE,
    classifiers=CLASSIFIERS,
    keywords=" ".join(KEYWORDS),
    python_requires=PYTHON_REQUIRES,
    
    # Package discovery
    packages=find_packages(exclude=EXCLUDE_PACKAGES),
    package_data=PACKAGE_DATA,
    include_package_data=True,
    
    # Dependencies
    install_requires=read_requirements(),
    extras_require=EXTRAS_REQUIRE,
    
    # Entry points
    entry_points=ENTRY_POINTS,
    
    # Metadata for wheel
    zip_safe=False,
    
    # Additional metadata
    platforms=["any"],
    maintainer=AUTHOR,
    maintainer_email=AUTHOR_EMAIL,
    
    # PyPI metadata
    download_url=f"{URL}/archive/v{VERSION}.tar.gz",
    
    # Setup requires for building
    setup_requires=[
        "setuptools>=68.0.0",
        "wheel>=0.41.0",
        "setuptools_scm>=7.0.0",
    ],
    
    # Build backend
    use_scm_version={
        "write_to": "quantum_computing_pipeline/_version.py",
        "write_to_template": '__version__ = "{version}"',
    },
    
    # Test configuration
    test_suite="tests",
    tests_require=TEST_REQUIREMENTS,
    
    # Command line options
    options={
        "build_py": {
            "compile": True,
            "optimize": 2,
        },
        "sdist": {
            "formats": ["gztar", "zip"],
        },
        "bdist_wheel": {
            "universal": False,
        },
        "egg_info": {
            "tag_build": "",
            "tag_date": False,
        },
    },
    
    # Namespace packages
    namespace_packages=[],
    
    # Data files
    data_files=[
        ("share/quantum-computing-pipeline/examples", [
            "examples/basic_optimization.py",
            "examples/quantum_chemistry.py",
            "examples/machine_learning.py",
        ]),
        ("share/quantum-computing-pipeline/config", [
            "config/default.yaml",
            "config/development.yaml",
            "config/production.yaml",
        ]),
        ("share/quantum-computing-pipeline/docs", [
            "docs/README.md",
            "docs/DEPLOYMENT.md",
            "docs/TROUBLESHOOTING.md",
        ]),
    ],
    
    # Script files
    scripts=[],
    
    # Package configuration
    package_dir={"": "."},
    
    # Metadata version
    metadata_version="2.1",
    
    # Obsoletes and provides
    obsoletes=[],
    provides=[PACKAGE_NAME],
    
    # Requires external
    requires_external=[],
    
    # Home page
    home_page=URL,
    
    # Download URL
    download_url=f"{URL}/archive/v{VERSION}.tar.gz",
)

# Post-installation message
def post_install():
    """Display post-installation message."""
    print(f"""
    ╔═══════════════════════════════════════════════════════════════════════════════╗
    ║                                                                               ║
    ║                    Quantum Computing Pipeline v{VERSION}                    ║
    ║                                                                               ║
    ║  Successfully installed hybrid quantum-classical computing pipeline!         ║
    ║                                                                               ║
    ║  Next steps:                                                                  ║
    ║  1. Configure AWS credentials: aws configure                                  ║
    ║  2. Bootstrap CDK environment: cdk bootstrap                                  ║
    ║  3. Deploy the stack: cdk deploy                                              ║
    ║  4. Check the deployment: cdk list                                            ║
    ║                                                                               ║
    ║  Documentation: https://docs.aws.amazon.com/cdk/                             ║
    ║  Amazon Braket: https://aws.amazon.com/braket/                               ║
    ║  Support: https://github.com/aws/aws-cdk/issues                              ║
    ║                                                                               ║
    ╚═══════════════════════════════════════════════════════════════════════════════╝
    """)

# Custom commands
class PostInstallCommand:
    """Custom post-installation command."""
    
    def run(self):
        """Run post-installation tasks."""
        post_install()

# Add custom command to setup
if __name__ == "__main__":
    import sys
    
    # Check Python version
    if sys.version_info < (3, 8):
        print("ERROR: Python 3.8 or higher is required.")
        sys.exit(1)
    
    # Run setup
    try:
        setup()
        post_install()
    except Exception as e:
        print(f"ERROR: Setup failed: {e}")
        sys.exit(1)