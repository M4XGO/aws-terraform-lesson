resource "aws_instance" "ec2" {
  ami = data.aws_ami.ubuntu.id
  instance_type = "t4g.nano"

  iam_instance_profile = aws_iam_instance_profile.instance_profile.name

  subnet_id = data.aws_subnet.subnet.id
  vpc_security_group_ids = [data.aws_security_group.security_group.id]
  associate_public_ip_address = false
  metadata_options {
    http_tokens               = "required"
    http_endpoint             = "enabled"
    http_put_response_hop_limit = 1
  }
  ebs_block_device {
    device_name           = "/dev/xvdf"
    volume_size           = 10
    volume_type           = "gp3"
    delete_on_termination = true
  }
  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y nginx

              # Ensure SSM Agent is installed and running for Session Manager
              snap install amazon-ssm-agent --classic
              systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
              systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service
              systemctl enable nginx
              systemctl start nginx

              # Prepare additional EBS volume
              DEVICE=/dev/xvdf
              MOUNT_POINT=/data

              # Wait for the device to be attached
              for i in {1..10}; do
                if lsblk | grep -q "xvdf"; then
                  break
                fi
                sleep 2
              done

              if ! blkid $DEVICE; then
                mkfs.ext4 $DEVICE
              fi

              mkdir -p $MOUNT_POINT
              if ! grep -qs "$MOUNT_POINT " /etc/fstab; then
                echo "$DEVICE $MOUNT_POINT ext4 defaults,nofail 0 2" >> /etc/fstab
              fi
              mount -a

              echo "EBS data volume is mounted on $MOUNT_POINT" > $MOUNT_POINT/test.txt

              mkdir -p /var/log/web
              echo "Web server started at $(date)" >> /var/log/web/startup.log
              EOF
  
  tags = {
    Name = "esgi-ec2-ssm"
  }
}

resource "aws_iam_instance_profile" "instance_profile" {
  name = "esgi-ec2-ssm-instance-profile"
  role = aws_iam_role.role.name
}