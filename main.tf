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
    You are an expert software developer writing a project summary for a README.md.
    Analyze the provided file list and write a confident, factual summary of the project's purpose and key components.
    **Do not use uncertain or hedging language** like 'it appears to be,' 'likely,' or 'seems to be.' State your analysis as fact.
    Your response must be only the summary paragraph.
  EOT
}

module "installation_guide_agent" {
  source                  = "./modules/bedrock_agent"
  agent_name              = "Installation_Guide_Agent"
  agent_resource_role_arn = module.bedrock_agent_role.role_arn
  foundation_model        = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
  instruction = <<-EOT
    You are a technical writer creating a README.md. Your ONLY job is to scan the provided list of filenames.
    If you see a common dependency file, write a '## Installation' section in Markdown.
    Your response must be concise and contain ONLY the command.
    For example, if you see 'requirements.txt', your entire response MUST be:
    ## Installation
```bash
    pip install -r requirements.txt
```
    If you do not see any recognizable dependency files, respond with an empty string.
  EOT
}

module "usage_examples_agent" {
  source                  = "./modules/bedrock_agent"
  agent_name              = "Usage_Examples_Agent"
  agent_resource_role_arn = module.bedrock_agent_role.role_arn
  foundation_model        = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
  instruction = <<-EOT
    You are a software developer writing a README.md. Your ONLY task is to identify the most likely entry point from a list of filenames.
    Write a '## Usage' section in Markdown showing the command to run the project.
    Your response MUST be concise and wrap the command in a bash code block.
    For example, if you see 'main.py', your entire response MUST be:
    ## Usage
```bash
    python main.py
```
  EOT
}
# -----------------------------------------------
# LAB 4: Final Compiler Agent
# -----------------------------------------------

module "final_compiler_agent" {
  source                  = "./modules/bedrock_agent"
  agent_name              = "Final_Compiler_Agent"
  agent_resource_role_arn = module.bedrock_agent_role.role_arn
  foundation_model        = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
  instruction = <<-EOT
    You are a technical document compiler. Your task is to take a JSON object containing different sections of a README file and assemble them into a single Markdown document.
    Use the repository name for the main H1 header (e.g., # repository_name).
    Combine the other sections provided.
    Your output MUST be only the pure, complete Markdown document.
    Do NOT include any preamble, apologies, explanations of your process, or any conversational text.
  EOT
}
# -----------------------------------------------
# LAB 4: Orchestrator IAM and Lambda
# -----------------------------------------------

module "orchestrator_execution_role" {
  source             = "./modules/iam"
  role_name          = "ReadmeGeneratorOrchestratorExecutionRole"
  service_principals = ["lambda.amazonaws.com"]
  policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  ]
}

resource "aws_iam_policy" "orchestrator_permissions" {
  name        = "ReadmeGeneratorOrchestratorPolicy"
  description = "Allows Lambda to invoke Bedrock Agents and use the S3 bucket."

  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Sid    = "BedrockAgentInvoke"
        Action = [
          "bedrock:InvokeAgent",
          "bedrock-agent-runtime:InvokeAgent"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Sid    = "S3BucketOperations"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:HeadObject"
        ]
        Effect   = "Allow"
        Resource = "${module.s3_bucket.bucket_arn}/*"
      }
    ]
  })

  lifecycle {
    ignore_changes = [policy]
  }
}

resource "aws_iam_role_policy_attachment" "orchestrator_permissions_attach" {
  role       = module.orchestrator_execution_role.role_name
  policy_arn = aws_iam_policy.orchestrator_permissions.arn
}

data "archive_file" "orchestrator_zip" {
  type        = "zip"
  source_dir  = "${path.root}/src/orchestrator"
  output_path = "${path.root}/dist/orchestrator.zip"
}

resource "aws_lambda_function" "orchestrator_lambda" {
  function_name    = "ReadmeGeneratorOrchestrator"
  role             = module.orchestrator_execution_role.role_arn
  filename         = data.archive_file.orchestrator_zip.output_path
  handler          = "lambda_function.handler"
  runtime          = "python3.11"
  timeout          = 180
  source_code_hash = data.archive_file.orchestrator_zip.output_base64sha256

  environment {
    variables = {
      REPO_SCANNER_AGENT_ID             = module.repo_scanner_agent.agent_id
      REPO_SCANNER_AGENT_ALIAS_ID       = "TSTALIASID"
      PROJECT_SUMMARIZER_AGENT_ID       = module.project_summarizer_agent.agent_id
      PROJECT_SUMMARIZER_AGENT_ALIAS_ID = "TSTALIASID"
      INSTALLATION_GUIDE_AGENT_ID       = module.installation_guide_agent.agent_id
      INSTALLATION_GUIDE_AGENT_ALIAS_ID = "TSTALIASID"
      USAGE_EXAMPLES_AGENT_ID           = module.usage_examples_agent.agent_id
      USAGE_EXAMPLES_AGENT_ALIAS_ID     = "TSTALIASID"
      FINAL_COMPILER_AGENT_ID           = module.final_compiler_agent.agent_id
      FINAL_COMPILER_AGENT_ALIAS_ID     = "TSTALIASID"
      OUTPUT_BUCKET                     = module.s3_bucket.bucket_id
    }
  }
}
# -----------------------------------------------
# LAB 4: S3 Event Trigger
# -----------------------------------------------

resource "aws_lambda_permission" "allow_s3_to_invoke_orchestrator" {
  statement_id  = "AllowS3ToInvokeOrchestratorLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.orchestrator_lambda.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = module.s3_bucket.bucket_arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = module.s3_bucket.bucket_id

  lambda_function {
    lambda_function_arn = aws_lambda_function.orchestrator_lambda.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "inputs/"
  }

  depends_on = [aws_lambda_permission.allow_s3_to_invoke_orchestrator]
}