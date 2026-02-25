# TP5: Haute disponibilité ALB public, ASG privé, health checks

resource "aws_launch_template" "web" {
  name_prefix   = "esgi-lt-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t4g.nano"

  iam_instance_profile {
    name = aws_iam_instance_profile.instance_profile.name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [data.aws_security_group.app.id]
  }

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y nginx

              snap install amazon-ssm-agent --classic
              systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
              systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service

              INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
              echo "<h1>ESGI AWS Training</h1><p>Instance: $INSTANCE_ID</p>" > /var/www/html/index.html

              systemctl enable nginx
              systemctl start nginx
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "esgi-asg-instance"
    })
  }

  tags = merge(local.common_tags, {
    Name = "esgi-launch-template"
  })
}

resource "aws_lb" "alb" {
  name               = "esgi-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [data.aws_security_group.web.id]
  subnets            = [data.aws_subnet.public_1.id, data.aws_subnet.public_2.id]

  tags = merge(local.common_tags, {
    Name = "esgi-alb"
  })
}

resource "aws_lb_target_group" "web" {
  name     = "esgi-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = local.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200"
  }

  tags = merge(local.common_tags, {
    Name = "esgi-target-group"
  })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }

  tags = merge(local.common_tags, {
    Name = "esgi-listener-http"
  })
}

resource "aws_autoscaling_group" "web" {
  name                = "esgi-asg"
  desired_capacity    = 1
  max_size            = 2
  min_size            = 1
  vpc_zone_identifier = [data.aws_subnet.private_1.id, data.aws_subnet.private_2.id]
  target_group_arns   = [aws_lb_target_group.web.arn]

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "esgi-asg-instance"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = local.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}
