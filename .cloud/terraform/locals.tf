locals {
  project     = "esgi-aws"
  owner       = "nony&faugeras"
  environment = "training"
  cost_center = "esgi-m1"

  common_tags = {
    Project    = local.project
    Owner      = local.owner
    Env        = local.environment
    CostCenter = local.cost_center
    ManagedBy  = "terraform"
  }

  vpc_id = "vpc-040089e30f22f2bd5"

  public_subnet_names  = ["esgi-sn-pub-1", "esgi-sn-pub-2"]
  private_subnet_names = ["esgi-sn", "esgi-sn-2"]
}
