############################################
# Three tiers x two Availability Zones.
#   public  - load balancer and NAT only
#   private - application servers (no public IPs)
#   data    - database; no route to the internet at all
############################################

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "securestudy-vpc" }
}

# Default SG with no rules, so nothing launched by accident is reachable.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "securestudy-igw" }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false
  tags                    = { Name = "securestudy-public-${count.index}", Tier = "public" }
}

resource "aws_subnet" "private" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.private_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false
  tags                    = { Name = "securestudy-private-${count.index}", Tier = "app" }
}

resource "aws_subnet" "data" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.data_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false
  tags                    = { Name = "securestudy-data-${count.index}", Tier = "data" }
}

# One NAT gateway keeps cost down (roughly USD 35-45/month, check current pricing); production would use one per AZ.
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "securestudy-nat-eip" }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "securestudy-nat" }
  depends_on    = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "securestudy-public-rt" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  tags = { Name = "securestudy-private-rt" }
}

# Data tier: local VPC routes only.
resource "aws_route_table" "data" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "securestudy-data-rt" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "data" {
  count          = 2
  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data.id
}

# S3 gateway endpoint: app-to-S3 traffic stays on the AWS network and is free.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
  tags              = { Name = "securestudy-s3-endpoint" }
}

# ---------- Flow logs ----------

resource "aws_cloudwatch_log_group" "flow" {
  name              = "/securestudy/vpc-flow"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.main.arn
}

data "aws_iam_policy_document" "flow_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "flow_permissions" {
  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["${aws_cloudwatch_log_group.flow.arn}:*"]
  }
}

resource "aws_iam_role" "flow" {
  name               = "securestudy-vpc-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_assume.json
}

resource "aws_iam_role_policy" "flow" {
  name   = "write-flow-logs"
  role   = aws_iam_role.flow.id
  policy = data.aws_iam_policy_document.flow_permissions.json
}

resource "aws_flow_log" "main" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"
  log_destination = aws_cloudwatch_log_group.flow.arn
  iam_role_arn    = aws_iam_role.flow.arn
}

# ---------- Network ACL on the data tier (second layer behind the SG) ----------

resource "aws_network_acl" "data" {
  # checkov:skip=CKV2_AWS_1:False positive - the NACL is attached through subnet_ids; the graph check cannot follow subnets created with count
  vpc_id     = aws_vpc.main.id
  subnet_ids = [aws_subnet.data[0].id, aws_subnet.data[1].id]
  tags       = { Name = "securestudy-data-nacl" }
}

resource "aws_network_acl_rule" "data_in_db" {
  count          = 2
  network_acl_id = aws_network_acl.data.id
  rule_number    = 100 + count.index
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = local.private_cidrs[count.index]
  from_port      = 5432
  to_port        = 5432
}

resource "aws_network_acl_rule" "data_out_ephemeral" {
  count          = 2
  network_acl_id = aws_network_acl.data.id
  rule_number    = 100 + count.index
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = local.private_cidrs[count.index]
  from_port      = 1024
  to_port        = 65535
}
