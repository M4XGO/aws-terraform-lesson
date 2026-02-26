resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "esgi-nat-eip"
  })
}

resource "aws_nat_gateway" "main" {
  allocation_id     = aws_eip.nat.id
  connectivity_type = "public"
  availability_mode = "regional"
  vpc_id            = local.vpc_id

  tags = merge(local.common_tags, {
    Name = "esgi-nat-gw"
  })

  depends_on = [aws_eip.nat]
}

resource "aws_route_table" "private" {
  vpc_id = local.vpc_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "esgi-private-rt"
  })
}

resource "aws_route_table_association" "private_1" {
  subnet_id      = data.aws_subnet.private_1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_2" {
  subnet_id      = data.aws_subnet.private_2.id
  route_table_id = aws_route_table.private.id
}
