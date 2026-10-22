############################################
# Security groups chain the tiers together by reference, not by IP:
#   internet -> alb (443) -> app (8443) -> db (5432)
# Rules are separate resources so the groups can refer to each other.
############################################

resource "aws_security_group" "alb" {
  name        = "securestudy-alb"
  description = "Public load balancer"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "securestudy-alb-sg" }
}

resource "aws_security_group" "app" {
  name        = "securestudy-app"
  description = "Application servers, reachable only from the load balancer"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "securestudy-app-sg" }
}

resource "aws_security_group" "db" {
  name        = "securestudy-db"
  description = "PostgreSQL, reachable only from the application tier"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "securestudy-db-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from the internet (the only public entry point)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward to application tier"
  ip_protocol                  = "tcp"
  from_port                    = 8443
  to_port                      = 8443
  referenced_security_group_id = aws_security_group.app.id
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "HTTPS from the load balancer only"
  ip_protocol                  = "tcp"
  from_port                    = 8443
  to_port                      = 8443
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "app_https_out" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS out (package repos, AWS APIs via NAT)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "app_to_db" {
  security_group_id            = aws_security_group.app.id
  description                  = "PostgreSQL to the database tier"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.db.id
}

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL from the application tier only"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.app.id
}
