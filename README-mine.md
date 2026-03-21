# readme-generator

## Overview

This is an automated README generation system built on AWS infrastructure. The project uses three Lambda functions orchestrated together to scan GitHub repositories, analyze their code structure and purpose, and generate comprehensive README.md documentation using AWS Bedrock AI agents. The repo_scanner Lambda extracts the file structure, the repo_intelligence_scanner Lambda analyzes the codebase to understand its purpose and components, and the orchestrator Lambda coordinates the workflow between these services. The entire infrastructure is provisioned through Terraform modules that manage S3 storage for artifacts, IAM permissions, and Bedrock agent configurations. A GitHub Actions workflow automates deployment, making this a fully automated solution for generating intelligent, AI-powered repository documentation based on actual code analysis.

## Usage

### Prerequisites
- AWS CLI configured with appropriate credentials
- Terraform installed (v1.0+)
- AWS account with permissions for Lambda, S3, IAM, and Bedrock

### Deployment

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### Running the Application
Once deployed, the orchestrator Lambda function coordinates the repository scanning and intelligence gathering:

```bash
# Invoke the orchestrator Lambda (replace with your function name)
aws lambda invoke \
  --function-name readme-generator-orchestrator \
  --payload '{"repository_url": "https://github.com/user/repo"}' \
  response.json

# View the response
cat response.json
```

### CI/CD
The project includes GitHub Actions automation at `.github/workflows/deploy.yml` for continuous deployment.

### Architecture
- **Orchestrator Lambda**: Coordinates the README generation workflow
- **Repo Scanner Lambda**: Scans repository structure and files
- **Repo Intelligence Scanner Lambda**: Analyzes code using AWS Bedrock AI
- **S3 Module**: Storage for generated READMEs
- **IAM Module**: Manages permissions for Lambda functions

## Features

✅ **Project Overview** - Description of the AWS Bedrock-powered repository intelligence system  
✅ **Architecture** - Details about the Lambda functions and their roles  
✅ **Prerequisites** - Required AWS services and tools  
✅ **Setup Guide** - Step-by-step Terraform deployment instructions  
✅ **Project Structure** - Clear breakdown of all directories and modules  
✅ **Configuration** - Information about schema files and customization  
✅ **CI/CD** - GitHub Actions deployment workflow details  
✅ **Usage Examples** - How to trigger and use the system