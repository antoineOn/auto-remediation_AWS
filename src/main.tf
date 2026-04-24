# VPC Principal
resource "aws_vpc" "ar_vpc_main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "ar-vpc-secops"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "ar_igw_main" {
  vpc_id = aws_vpc.ar_vpc_main.id

  tags = {
    Name = "ar-igw"
  }
}
