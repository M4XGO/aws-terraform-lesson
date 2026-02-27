# TP13: Infrastructure as Code CloudFormation socle réseau reproductible

# ─────────────────────────────────────────────────────────────────
# ÉTAPE 1 : Template CloudFormation — VPC, subnets, IGW, routes, tags
# ─────────────────────────────────────────────────────────────────
locals {
  cf_network_template = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "ESGI — Socle réseau reproductible : VPC, Subnets publics/privés, IGW, Route Tables"

    Parameters = {
      ProjectName = {
        Type        = "String"
        Default     = "esgi-aws"
        Description = "Nom du projet"
      }
      Environment = {
        Type          = "String"
        Default       = "training"
        AllowedValues = ["training", "dev", "staging", "prod"]
        Description   = "Environnement de déploiement"
      }
      Owner = {
        Type        = "String"
        Default     = "nony_faugeras"
        Description = "Propriétaire de la ressource"
      }
      CostCenter = {
        Type        = "String"
        Default     = "esgi-m1"
        Description = "Centre de coût"
      }
      VpcCidr = {
        Type        = "String"
        Default     = "10.1.0.0/16"
        Description = "CIDR block principal du VPC"
      }
      PublicSubnet1Cidr = {
        Type        = "String"
        Default     = "10.1.1.0/24"
        Description = "CIDR subnet publique AZ-a"
      }
      PublicSubnet2Cidr = {
        Type        = "String"
        Default     = "10.1.2.0/24"
        Description = "CIDR subnet publique AZ-b"
      }
      PrivateSubnet1Cidr = {
        Type        = "String"
        Default     = "10.1.10.0/24"
        Description = "CIDR subnet privée AZ-a"
      }
      PrivateSubnet2Cidr = {
        Type        = "String"
        Default     = "10.1.11.0/24"
        Description = "CIDR subnet privée AZ-b"
      }
    }

    Resources = {
      VPC = {
        Type = "AWS::EC2::VPC"
        Properties = {
          CidrBlock          = { Ref = "VpcCidr" }
          EnableDnsHostnames = true
          EnableDnsSupport   = true
          Tags = [
            { Key = "Name",       Value = { "Fn::Sub" = "$${ProjectName}-cf-vpc" } },
            { Key = "Project",    Value = { Ref = "ProjectName" } },
            { Key = "Env",        Value = { Ref = "Environment" } },
            { Key = "Owner",      Value = { Ref = "Owner" } },
            { Key = "CostCenter", Value = { Ref = "CostCenter" } },
            { Key = "ManagedBy",  Value = "cloudformation" }
          ]
        }
      }

      InternetGateway = {
        Type = "AWS::EC2::InternetGateway"
        Properties = {
          Tags = [
            { Key = "Name",       Value = { "Fn::Sub" = "$${ProjectName}-cf-igw" } },
            { Key = "Project",    Value = { Ref = "ProjectName" } },
            { Key = "Env",        Value = { Ref = "Environment" } },
            { Key = "ManagedBy",  Value = "cloudformation" }
          ]
        }
      }

      VPCGatewayAttachment = {
        Type = "AWS::EC2::VPCGatewayAttachment"
        Properties = {
          VpcId             = { Ref = "VPC" }
          InternetGatewayId = { Ref = "InternetGateway" }
        }
      }

      PublicSubnet1 = {
        Type = "AWS::EC2::Subnet"
        Properties = {
          VpcId               = { Ref = "VPC" }
          CidrBlock           = { Ref = "PublicSubnet1Cidr" }
          AvailabilityZone    = { "Fn::Select" = [0, { "Fn::GetAZs" = "" }] }
          MapPublicIpOnLaunch = true
          Tags = [
            { Key = "Name",      Value = { "Fn::Sub" = "$${ProjectName}-cf-sn-pub-1" } },
            { Key = "Project",   Value = { Ref = "ProjectName" } },
            { Key = "Env",       Value = { Ref = "Environment" } },
            { Key = "Tier",      Value = "public" },
            { Key = "ManagedBy", Value = "cloudformation" }
          ]
        }
      }

      PublicSubnet2 = {
        Type = "AWS::EC2::Subnet"
        Properties = {
          VpcId               = { Ref = "VPC" }
          CidrBlock           = { Ref = "PublicSubnet2Cidr" }
          AvailabilityZone    = { "Fn::Select" = [1, { "Fn::GetAZs" = "" }] }
          MapPublicIpOnLaunch = true
          Tags = [
            { Key = "Name",      Value = { "Fn::Sub" = "$${ProjectName}-cf-sn-pub-2" } },
            { Key = "Project",   Value = { Ref = "ProjectName" } },
            { Key = "Env",       Value = { Ref = "Environment" } },
            { Key = "Tier",      Value = "public" },
            { Key = "ManagedBy", Value = "cloudformation" }
          ]
        }
      }

      PrivateSubnet1 = {
        Type = "AWS::EC2::Subnet"
        Properties = {
          VpcId               = { Ref = "VPC" }
          CidrBlock           = { Ref = "PrivateSubnet1Cidr" }
          AvailabilityZone    = { "Fn::Select" = [0, { "Fn::GetAZs" = "" }] }
          MapPublicIpOnLaunch = false
          Tags = [
            { Key = "Name",      Value = { "Fn::Sub" = "$${ProjectName}-cf-sn-priv-1" } },
            { Key = "Project",   Value = { Ref = "ProjectName" } },
            { Key = "Env",       Value = { Ref = "Environment" } },
            { Key = "Tier",      Value = "private" },
            { Key = "ManagedBy", Value = "cloudformation" }
          ]
        }
      }

      PrivateSubnet2 = {
        Type = "AWS::EC2::Subnet"
        Properties = {
          VpcId               = { Ref = "VPC" }
          CidrBlock           = { Ref = "PrivateSubnet2Cidr" }
          AvailabilityZone    = { "Fn::Select" = [1, { "Fn::GetAZs" = "" }] }
          MapPublicIpOnLaunch = false
          Tags = [
            { Key = "Name",      Value = { "Fn::Sub" = "$${ProjectName}-cf-sn-priv-2" } },
            { Key = "Project",   Value = { Ref = "ProjectName" } },
            { Key = "Env",       Value = { Ref = "Environment" } },
            { Key = "Tier",      Value = "private" },
            { Key = "ManagedBy", Value = "cloudformation" }
          ]
        }
      }

      PublicRouteTable = {
        Type = "AWS::EC2::RouteTable"
        Properties = {
          VpcId = { Ref = "VPC" }
          Tags = [
            { Key = "Name",      Value = { "Fn::Sub" = "$${ProjectName}-cf-rt-pub" } },
            { Key = "Project",   Value = { Ref = "ProjectName" } },
            { Key = "Env",       Value = { Ref = "Environment" } },
            { Key = "Tier",      Value = "public" },
            { Key = "ManagedBy", Value = "cloudformation" }
          ]
        }
      }

      PublicRoute = {
        Type      = "AWS::EC2::Route"
        DependsOn = "VPCGatewayAttachment"
        Properties = {
          RouteTableId         = { Ref = "PublicRouteTable" }
          DestinationCidrBlock = "0.0.0.0/0"
          GatewayId            = { Ref = "InternetGateway" }
        }
      }

      PublicSubnet1RouteTableAssociation = {
        Type = "AWS::EC2::SubnetRouteTableAssociation"
        Properties = {
          SubnetId     = { Ref = "PublicSubnet1" }
          RouteTableId = { Ref = "PublicRouteTable" }
        }
      }

      PublicSubnet2RouteTableAssociation = {
        Type = "AWS::EC2::SubnetRouteTableAssociation"
        Properties = {
          SubnetId     = { Ref = "PublicSubnet2" }
          RouteTableId = { Ref = "PublicRouteTable" }
        }
      }

      PrivateRouteTable = {
        Type = "AWS::EC2::RouteTable"
        Properties = {
          VpcId = { Ref = "VPC" }
          Tags = [
            { Key = "Name",      Value = { "Fn::Sub" = "$${ProjectName}-cf-rt-priv" } },
            { Key = "Project",   Value = { Ref = "ProjectName" } },
            { Key = "Env",       Value = { Ref = "Environment" } },
            { Key = "Tier",      Value = "private" },
            { Key = "ManagedBy", Value = "cloudformation" }
          ]
        }
      }

      PrivateSubnet1RouteTableAssociation = {
        Type = "AWS::EC2::SubnetRouteTableAssociation"
        Properties = {
          SubnetId     = { Ref = "PrivateSubnet1" }
          RouteTableId = { Ref = "PrivateRouteTable" }
        }
      }

      PrivateSubnet2RouteTableAssociation = {
        Type = "AWS::EC2::SubnetRouteTableAssociation"
        Properties = {
          SubnetId     = { Ref = "PrivateSubnet2" }
          RouteTableId = { Ref = "PrivateRouteTable" }
        }
      }
    }

    Outputs = {
      VpcId = {
        Description = "ID du VPC créé par CloudFormation"
        Value       = { Ref = "VPC" }
        Export      = { Name = { "Fn::Sub" = "$${AWS::StackName}-VpcId" } }
      }
      VpcCidr = {
        Description = "CIDR block du VPC"
        Value       = { "Fn::GetAtt" = ["VPC", "CidrBlock"] }
        Export      = { Name = { "Fn::Sub" = "$${AWS::StackName}-VpcCidr" } }
      }
      PublicSubnet1Id = {
        Description = "ID subnet publique AZ-a"
        Value       = { Ref = "PublicSubnet1" }
        Export      = { Name = { "Fn::Sub" = "$${AWS::StackName}-PublicSubnet1Id" } }
      }
      PublicSubnet2Id = {
        Description = "ID subnet publique AZ-b"
        Value       = { Ref = "PublicSubnet2" }
        Export      = { Name = { "Fn::Sub" = "$${AWS::StackName}-PublicSubnet2Id" } }
      }
      PrivateSubnet1Id = {
        Description = "ID subnet privée AZ-a"
        Value       = { Ref = "PrivateSubnet1" }
        Export      = { Name = { "Fn::Sub" = "$${AWS::StackName}-PrivateSubnet1Id" } }
      }
      PrivateSubnet2Id = {
        Description = "ID subnet privée AZ-b"
        Value       = { Ref = "PrivateSubnet2" }
        Export      = { Name = { "Fn::Sub" = "$${AWS::StackName}-PrivateSubnet2Id" } }
      }
      PublicRouteTableId = {
        Description = "ID de la route table publique"
        Value       = { Ref = "PublicRouteTable" }
        Export      = { Name = { "Fn::Sub" = "$${AWS::StackName}-PublicRTId" } }
      }
      PrivateRouteTableId = {
        Description = "ID de la route table privée"
        Value       = { Ref = "PrivateRouteTable" }
        Export      = { Name = { "Fn::Sub" = "$${AWS::StackName}-PrivateRTId" } }
      }
    }
  })
}

resource "aws_cloudformation_stack" "network" {
  name          = "esgi-cf-network"
  template_body = local.cf_network_template

  parameters = {
    ProjectName        = local.project
    Environment        = local.environment
    Owner              = local.owner
    CostCenter         = local.cost_center
    VpcCidr            = "10.1.0.0/16"
    PublicSubnet1Cidr  = "10.1.1.0/24"
    PublicSubnet2Cidr  = "10.1.2.0/24"
    PrivateSubnet1Cidr = "10.1.10.0/24"
    PrivateSubnet2Cidr = "10.1.11.0/24"
  }

  tags = merge(local.common_tags, {
    Name = "esgi-cf-network"
  })
}


output "cf_network_vpc_id" {
  value       = aws_cloudformation_stack.network.outputs["VpcId"]
  description = "VPC ID créé par la stack CloudFormation"
}

output "cf_network_public_subnet_1_id" {
  value       = aws_cloudformation_stack.network.outputs["PublicSubnet1Id"]
  description = "Subnet publique AZ-a (CloudFormation)"
}

output "cf_network_public_subnet_2_id" {
  value       = aws_cloudformation_stack.network.outputs["PublicSubnet2Id"]
  description = "Subnet publique AZ-b (CloudFormation)"
}

output "cf_network_private_subnet_1_id" {
  value       = aws_cloudformation_stack.network.outputs["PrivateSubnet1Id"]
  description = "Subnet privée AZ-a (CloudFormation)"
}

output "cf_network_private_subnet_2_id" {
  value       = aws_cloudformation_stack.network.outputs["PrivateSubnet2Id"]
  description = "Subnet privée AZ-b (CloudFormation)"
}
