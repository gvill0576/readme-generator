terraform {
  backend "s3" {
    bucket         = "tf-readme-generator-state-vk877lvf"
    key            = "global/s3/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "readme-generator-tf-locks"
  }
}