terraform {
  required_version = ">= 0.11.6"
}

resource "aws_security_group" "vault_lb" {
  count = "${var.create ? 1 : 0}"

  name_prefix = "${var.name}-vault-lb-"
  description = "Security group for Vault ${var.name} LB"
  vpc_id      = "${var.vpc_id}"
  tags        = "${merge(var.tags, map("Name", format("%s-vault-lb", var.name)))}"
}

resource "aws_security_group_rule" "vault_lb_http_80" [
  {
  count = "${var.create ? 1 : 0}"

  security_group_id = "${aws_security_group.vault_lb.id}"
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_blocks       = ["${split(",", var.is_internal_lb ? join(",", var.cidr_blocks) : "${tmx-ip-block-inet}")}"]
},
  {
  count = "${var.create ? 1 : 0}"

  security_group_id = "${aws_security_group.vault_lb.id}"
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_blocks       = ["${split(",", var.is_internal_lb ? join(",", var.cidr_blocks) : "${tmx-ip-block-dmz}")}"]
},
  {
  count = "${var.create ? 1 : 0}"

  security_group_id = "${aws_security_group.vault_lb.id}"
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_blocks       = ["${split(",", var.is_internal_lb ? join(",", var.cidr_blocks) : "${tmx-ip-block-corp-nat}"})}"]
},
  {
  count = "${var.create ? 1 : 0}"

  security_group_id = "${aws_security_group.vault_lb.id}"
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_blocks       = ["${split(",", var.is_internal_lb ? join(",", var.cidr_blocks) : "${tmx-ip-block-wifi-firewall}")}"]
}
]

resource "aws_security_group_rule" "vault_lb_https_443" [
  {
  count = "${var.create && var.use_lb_cert ? 1 : 0}"

  security_group_id = "${aws_security_group.vault_lb.id}"
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_blocks       = ["${split(",", var.is_internal_lb ? join(",", var.cidr_blocks) : "${tmx-ip-block-inet}")}"]
},
  {
  count = "${var.create && var.use_lb_cert ? 1 : 0}"

  security_group_id = "${aws_security_group.vault_lb.id}"
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_blocks       = ["${split(",", var.is_internal_lb ? join(",", var.cidr_blocks) : "${tmx-ip-block-dmz}")}"]
},
  {
  count = "${var.create && var.use_lb_cert ? 1 : 0}"

  security_group_id = "${aws_security_group.vault_lb.id}"
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_blocks       = ["${split(",", var.is_internal_lb ? join(",", var.cidr_blocks) : "${tmx-ip-block-corp-nat}")}"]
},
  {
  count = "${var.create && var.use_lb_cert ? 1 : 0}"

  security_group_id = "${aws_security_group.vault_lb.id}"
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_blocks       = ["${split(",", var.is_internal_lb ? join(",", var.cidr_blocks) : "${tmx-ip-block-wifi-firewall}")}"]
}
]

resource "aws_security_group_rule" "vault_lb_tcp_8200" {
  count = "${var.create ? 1 : 0}"

  security_group_id = "${aws_security_group.vault_lb.id}"
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 8200
  to_port           = 8200
  cidr_blocks       = ["${split(",", var.is_internal_lb ? join(",", var.cidr_blocks) : "0.0.0.0/0")}"]
}

resource "aws_security_group_rule" "outbound_tcp" {
  count = "${var.create ? 1 : 0}"

  security_group_id = "${aws_security_group.vault_lb.id}"
  type              = "egress"
  protocol          = "tcp"
  from_port         = 0
  to_port           = 65535
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "random_id" "vault_lb_access_logs" {
  count = "${var.create && !var.lb_bucket_override ? 1 : 0}"

  byte_length = 4
  prefix      = "${format("%s-vault-lb-access-logs-", var.name)}"
}

data "aws_elb_service_account" "vault_lb_access_logs" {
  count = "${var.create && !var.lb_bucket_override ? 1 : 0}"
}

resource "aws_s3_bucket" "vault_lb_access_logs" {
  count = "${var.create && !var.lb_bucket_override ? 1 : 0}"

  bucket = "${random_id.vault_lb_access_logs.hex}"
  acl    = "private"
  tags   = "${merge(var.tags, map("Name", format("%s-vault-lb-access-logs", var.name)))}"

  force_destroy = true

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm     = "AES256"
      }
    }
  }

  logging {
    target_bucket = "${var.s3_logging_target}"
    target_prefix = "${var.lb_bucket_prefix}log/"
  }

  policy = <<POLICY
{
  "Id": "Policy",
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "LBAccessLogs",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::${random_id.vault_lb_access_logs.hex}${var.lb_bucket_prefix != "" ? format("//", var.lb_bucket_prefix) : ""}/AWSLogs/*",
      "Principal": {
        "AWS": [
          "${data.aws_elb_service_account.vault_lb_access_logs.arn}"
        ]
      }
    },
    {
      "Sid": "ForceSSLOnlyAccess",
      "Effect": "Deny",
      "Principal": {
          "AWS": "*"
      },
      "Action": "s3:*",
      "Resource": "arn:aws:s3:::${random_id.vault_lb_access_logs.hex}${var.lb_bucket_prefix != "" ? format("//", var.lb_bucket_prefix) : ""}/*",
      "Condition": {
          "Bool": {
              "aws:SecureTransport": "false"
          }
      }
    }
  ]
}
POLICY
}

resource "random_id" "vault_lb" {
  count = "${var.create ? 1 : 0}"

  byte_length = 4
  prefix      = "vault-lb-"
}

resource "aws_lb" "vault" {
  count = "${var.create ? 1 : 0}"

  name            = "${random_id.vault_lb.hex}"
  internal        = "${var.is_internal_lb ? true : false}"
  subnets         = ["${var.subnet_ids}"]
  security_groups = ["${aws_security_group.vault_lb.id}"]
  tags            = "${merge(var.tags, map("Name", format("%s-vault-lb", var.name)))}"

  access_logs {
    bucket  = "${var.lb_bucket_override ? var.lb_bucket : element(concat(aws_s3_bucket.vault_lb_access_logs.*.id, list("")), 0)}"
    prefix  = "${var.lb_bucket_prefix}"
    enabled = "${var.lb_logs_enabled}"
  }
}

resource "random_id" "vault_http_8200" {
  count = "${var.create && !var.use_lb_cert ? 1 : 0}"

  byte_length = 4
  prefix      = "vault-http-8200-"
}

resource "aws_lb_target_group" "vault_http_8200" {
  count = "${var.create && !var.use_lb_cert ? 1 : 0}"

  name     = "${random_id.vault_http_8200.hex}"
  vpc_id   = "${var.vpc_id}"
  port     = 8200
  protocol = "HTTP"
  tags     = "${merge(var.tags, map("Name", format("%s-vault-http-8200", var.name)))}"

  health_check {
    interval = 15
    timeout  = 5
    protocol = "HTTP"
    port     = "traffic-port"
    path     = "/v1/sys/health?standbyok=true"
    matcher  = "200,429"

    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "vault_80" {
  count = "${var.create && !var.use_lb_cert ? 1 : 0}"

  load_balancer_arn = "${aws_lb.vault.arn}"
  port              = "80"
  protocol          = "HTTP"

  action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
  }
}

resource "aws_iam_server_certificate" "vault" {
  count = "${var.create && var.use_lb_cert ? 1 : 0}"

  name              = "${random_id.vault_lb.hex}"
  certificate_body  = "${var.lb_cert}"
  private_key       = "${var.lb_private_key}"
  certificate_chain = "${var.lb_cert_chain}"
  path              = "/${var.name}-${random_id.vault_lb.hex}/"
}

resource "random_id" "vault_https_8200" {
  count = "${var.create && var.use_lb_cert ? 1 : 0}"

  byte_length = 4
  prefix      = "vault-https-8200-"
}

resource "aws_lb_target_group" "vault_https_8200" {
  count = "${var.create && var.use_lb_cert ? 1 : 0}"

  name     = "${random_id.vault_https_8200.hex}"
  vpc_id   = "${var.vpc_id}"
  port     = 8200
  protocol = "HTTPS"
  tags     = "${merge(var.tags, map("Name", format("%s-vault-https-8200", var.name)))}"

  health_check {
    interval = 15
    timeout  = 5
    protocol = "HTTPS"
    port     = "traffic-port"
    path     = "/v1/sys/health?standbyok=true"
    matcher  = "200,429"

    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "vault_443" {
  count = "${var.create && var.use_lb_cert ? 1 : 0}"

  load_balancer_arn = "${aws_lb.vault.arn}"
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = "${var.ext_cert_arn}"

  default_action {
    target_group_arn = "${aws_lb_target_group.vault_https_8200.arn}"
    type             = "forward"
  }
}

resource "aws_lb_listener" "vault_8200" {
  count = "${var.create ? 1 : 0}"

  load_balancer_arn = "${aws_lb.vault.arn}"
  port              = "8200"
  protocol          = "${var.use_lb_cert ? "HTTPS" : "HTTP"}"
  ssl_policy        = "${var.use_lb_cert ? var.lb_ssl_policy : ""}"
  certificate_arn   = "${var.use_lb_cert ? element(concat(aws_iam_server_certificate.vault.*.arn, list("")), 0) : ""}" # TODO: Workaround for issue #11210

  default_action {
    target_group_arn = "${var.use_lb_cert ? element(concat(aws_lb_target_group.vault_https_8200.*.arn, list("")), 0) : element(concat(aws_lb_target_group.vault_http_8200.*.arn, list("")), 0)}" # TODO: Workaround for issue #11210
    type             = "forward"
  }
}
