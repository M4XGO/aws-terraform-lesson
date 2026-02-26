terraform {
  backend "s3" {
    bucket  = "training-esgi-aws"
    key     = "terraform/terraform.tfstate"
    region  = "eu-west-3"
    encrypt = true
  }
}