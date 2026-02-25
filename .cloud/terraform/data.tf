data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-22.04-arm64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

data "aws_vpc" "main" {
  id = local.vpc_id
}

data "aws_subnet" "subnet" {
  filter {
    name   = "tag:Name"
    values = ["esgi-sn"]
  }
}

data "aws_subnet" "private_1" {
  filter {
    name   = "tag:Name"
    values = ["esgi-sn"]
  }
}

data "aws_subnet" "private_2" {
  filter {
    name   = "tag:Name"
    values = ["esgi-sn-2"]
  }
}

data "aws_subnet" "public_1" {
  filter {
    name   = "tag:Name"
    values = ["esgi-sn-pub-1"]
  }
}

data "aws_subnet" "public_2" {
  filter {
    name   = "tag:Name"
    values = ["esgi-sn-pub-2"]
  }
}

data "aws_security_group" "web" {
  filter {
    name   = "tag:Name"
    values = ["esgi-web-sg"]
  }
  vpc_id = local.vpc_id
}

data "aws_security_group" "app" {
  filter {
    name   = "tag:Name"
    values = ["esgi-app-sg"]
  }
  vpc_id = local.vpc_id
}

data "aws_security_group" "db" {
  filter {
    name   = "tag:Name"
    values = ["esgi-db-sg"]
  }
  vpc_id = local.vpc_id
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}