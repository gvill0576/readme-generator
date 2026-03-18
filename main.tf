terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

module "s3_bucket" {
  source      = "./modules/s3"
  bucket_name = "readme-generator-output-bucket-${random_string.suffix.result}"
}

module "lambda_execution_role" {
  source             = "./modules/iam"
  role_name          = "ReadmeGeneratorLambdaExecutionRole"
  service_principals = ["lambda.amazonaws.com"]
  policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  ]
}

module "bedrock_agent_role" {
  source             = "./modules/iam"
  role_name          = "ReadmeGeneratorBedrockAgentRole"
  service_principals = ["bedrock.amazonaws.com"]
  policy_arns = [
    "arn:aws:iam::aws:policy/AmazonBedrockFullAccess"
  ]
}

output "readme_bucket_name" {
  description = "The name of the S3 bucket where README files are stored."
  value       = module.s3_bucket.bucket_id
}

# -----------------------------------------------
# LAB 2: Repo Scanner
# -----------------------------------------------

data "archive_file" "repo_scanner_zip" {
  type        = "zip"
  source_dir  = "${path.root}/src/repo_scanner"
  output_path = "${path.root}/dist/repo_scanner.zip"
}

resource "aws_lambda_function" "repo_scanner_lambda" {
  function_name    = "RepoScannerTool"
  role             = module.lambda_execution_role.role_arn
  filename         = data.archive_file.repo_scanner_zip.output_path
  handler          = "lambda_function.handler"
  runtime          = "python3.11"
  timeout          = 30
  source_code_hash = data.archive_file.repo_scanner_zip.output_base64sha256
  layers           = ["arn:aws:lambda:us-east-1:553035198032:layer:git-lambda2:8"]
}

module "repo_scanner_agent" {
  source                  = "./modules/bedrock_agent"
  agent_name              = "Repo_Scanner_Agent"
  agent_resource_role_arn = module.bedrock_agent_role.role_arn
  foundation_model        = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
  instruction             = "Your job is to use the scan_repo tool to get a file list from a public GitHub URL. You are a helpful AI assistant. When a user provides a GitHub URL, you must use the available tool to scan it."
}

resource "aws_bedrockagent_agent_action_group" "repo_scanner_action_group" {
  agent_id           = module.repo_scanner_agent.agent_id
  agent_version      = "DRAFT"
  action_group_name  = "ScanRepoAction"
  action_group_state = "ENABLED"

  action_group_executor {
    lambda = aws_lambda_function.repo_scanner_lambda.arn
  }

  api_schema {
    payload = file("${path.root}/repo_scanner_schema.json")
  }
}

resource "aws_lambda_permission" "allow_bedrock_to_invoke_lambda" {
  statement_id  = "AllowBedrockToInvokeRepoScannerLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.repo_scanner_lambda.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = module.repo_scanner_agent.agent_arn
}

# -----------------------------------------------
# ASSIGNMENT: Data Intelligence Platform
# Labs 1 and 2 Correlation
# -----------------------------------------------

data "archive_file" "repo_intelligence_scanner_zip" {
  type        = "zip"
  source_dir  = "${path.root}/src/repo_intelligence_scanner"
  output_path = "${path.root}/dist/repo_intelligence_scanner.zip"
}

resource "aws_lambda_function" "repo_intelligence_scanner_lambda" {
  function_name    = "RepoIntelligenceScannerTool"
  role             = module.lambda_execution_role.role_arn
  filename         = data.archive_file.repo_intelligence_scanner_zip.output_path
  handler          = "lambda_function.handler"
  runtime          = "python3.11"
  timeout          = 60
  source_code_hash = data.archive_file.repo_intelligence_scanner_zip.output_base64sha256
  layers           = ["arn:aws:lambda:us-east-1:553035198032:layer:git-lambda2:8"]
}

module "repo_intelligence_agent" {
  source                  = "./modules/bedrock_agent"
  agent_name              = "Repo_Intelligence_Agent"
  agent_resource_role_arn = module.bedrock_agent_role.role_arn
  foundation_model        = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
  instruction             = "You are a repository intelligence analyst specializing in data engineering assessment. Your job is to use the scan_repo tool to perform a deep analysis of a public GitHub repository. When a user provides a GitHub URL, scan it and provide a structured summary covering: the technology stack, data engineering relevance, project maturity assessment based on the maturity score, CI/CD and testing signals, and any detected data engineering frameworks or tools."
}

resource "aws_bedrockagent_agent_action_group" "repo_intelligence_action_group" {
  agent_id           = module.repo_intelligence_agent.agent_id
  agent_version      = "DRAFT"
  action_group_name  = "ScanRepoAction"
  action_group_state = "ENABLED"

  action_group_executor {
    lambda = aws_lambda_function.repo_intelligence_scanner_lambda.arn
  }

  api_schema {
    payload = file("${path.root}/repo_intelligence_schema.json")
  }
}

resource "aws_lambda_permission" "allow_bedrock_to_invoke_intelligence_lambda" {
  statement_id  = "AllowBedrockToInvokeIntelligenceLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.repo_intelligence_scanner_lambda.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = module.repo_intelligence_agent.agent_arn
}

output "intelligence_agent_id" {
  description = "The ID of the Repo Intelligence Agent."
  value       = module.repo_intelligence_agent.agent_id
}

# -----------------------------------------------
# LAB 3: Analytical Agents
# -----------------------------------------------

module "project_summarizer_agent" {
  source                  = "./modules/bedrock_agent"
  agent_name              = "Project_Summarizer_Agent"
  agent_resource_role_arn = module.bedrock_agent_role.role_arn
  foundation_model        = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
  instruction = <<-EOT
    You are an expert software developer. Your ONLY task is to analyze the following list of filenames and write a single, concise paragraph summarizing the project's likely purpose.
    Infer the main programming language and potential frameworks from file extensions and common project file names (e.g., 'pom.xml' implies Java/Maven, 'package.json' implies Node.js).
    Do not add any preamble or extra text. Only provide the summary paragraph.
  EOT
}

module "installation_guide_agent" {
  source                  = "./modules/bedrock_agent"
  agent_name              = "Installation_Guide_Agent"
  agent_resource_role_arn = module.bedrock_agent_role.role_arn
  foundation_model        = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
  instruction = <<-EOT
    You are a technical writer. Your ONLY job is to scan the provided list of filenames.
    If you see a common dependency file like 'requirements.txt', 'package.json', 'pom.xml', or 'go.mod', write a '## Getting Started' section in Markdown that includes the standard command to install dependencies for that file type.
    If you do not see any recognizable dependency files, respond with the exact text: 'No dependency management file found.'
  EOT
}

module "usage_examples_agent" {
  source                  = "./modules/bedrock_agent"
  agent_name              = "Usage_Examples_Agent"
  agent_resource_role_arn = module.bedrock_agent_role.role_arn
  foundation_model        = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
  instruction = <<-EOT
    You are a software developer. Your ONLY task is to look at the list of filenames and identify the most likely main script or entry point (e.g., 'main.py', 'index.js', 'app.py').
    Write a '## Usage' section in Markdown that shows a common command to run the project.
    For example, if you see 'main.py', suggest 'python main.py'.
  EOT
}