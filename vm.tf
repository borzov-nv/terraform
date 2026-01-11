# ОБРАЗ
data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2204-lts"
}

# БАСТИОН
resource "yandex_compute_instance" "bastion" {
  name        = "bastion"
  hostname    = "bastion"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    cores         = 2
    memory        = 2
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.public.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.bastion_sg.id, yandex_vpc_security_group.basic_sg.id]
  }

  service_account_id = var.servacc_id

  metadata = {
    install-cloud-backup = "yes"
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }

  scheduling_policy {
    preemptible = var.vm_preemptible
  }
}

# ВЕБСЕРВЕРЫ
resource "yandex_compute_instance" "web" {
  count       = 2
  name        = "web-${count.index + 1}"
  hostname    = "web-${count.index + 1}"
  zone        = count.index == 0 ? "ru-central1-a" : "ru-central1-b"
  platform_id = "standard-v3"

  resources {
    cores         = 2
    memory        = 2
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
    }
  }

  network_interface {
    subnet_id          = count.index == 0 ? yandex_vpc_subnet.private-1.id : yandex_vpc_subnet.private-2.id
    security_group_ids = [yandex_vpc_security_group.web_sg.id, yandex_vpc_security_group.basic_sg.id]
  }

  service_account_id = var.servacc_id
  
  metadata = {
    install-cloud-backup = "yes"
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }

  scheduling_policy {
    preemptible = var.vm_preemptible
  }
}

# ZABBIX
resource "yandex_compute_instance" "zabbix" {
  name        = "zabbix"
  hostname    = "zabbix"
  zone        = "ru-central1-a"
  platform_id = "standard-v3"

  resources {
    cores  = 2
    memory = 4
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.public.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.zabbix_sg.id, yandex_vpc_security_group.basic_sg.id]
  }

  service_account_id = var.servacc_id
  
  metadata = {
    install-cloud-backup = "yes"
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }

  scheduling_policy {
    preemptible = var.vm_preemptible
  }
}

# KIBANA
resource "yandex_compute_instance" "kibana" {
  name        = "kibana"
  hostname    = "kibana"
  zone        = "ru-central1-a"
  platform_id = "standard-v3"

  resources {
    cores  = 2
    memory = 4
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.public.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.kibana_sg.id, yandex_vpc_security_group.basic_sg.id]
  }

  service_account_id = var.servacc_id
  
  metadata = {
    install-cloud-backup = "yes"
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }

  scheduling_policy {
    preemptible = var.vm_preemptible
  }
}

# ELASTICSEARCH
resource "yandex_compute_instance" "elasticsearch" {
  name        = "elasticsearch"
  hostname    = "elasticsearch"
  zone        = "ru-central1-a"
  platform_id = "standard-v3"

  resources {
    cores  = 4
    memory = 8
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.private-1.id
    security_group_ids = [yandex_vpc_security_group.elastic_sg.id, yandex_vpc_security_group.basic_sg.id]
  }

  service_account_id = var.servacc_id
  
  metadata = {
    install-cloud-backup = "yes"
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }

  scheduling_policy {
    preemptible = var.vm_preemptible
  }
}

# ЦЕЛЕВАЯ ГРУППА
resource "yandex_alb_target_group" "web_targets" {
  name = "web-target-group"

  dynamic "target" {
    for_each = yandex_compute_instance.web
    content {
      subnet_id  = target.value.network_interface.0.subnet_id
      ip_address = target.value.network_interface.0.ip_address
    }
  }
}

# БЭКЕНД
resource "yandex_alb_backend_group" "web_backends" {
  name = "web-backend-group"

  http_backend {
    name             = "http-backend"
    weight           = 1
    port             = 80
    target_group_ids = [yandex_alb_target_group.web_targets.id]
    
    load_balancing_config {
      panic_threshold = 50
    }    
    healthcheck {
      timeout             = "10s"
      interval            = "60s"
      healthcheck_port = 80
      healthy_threshold   = 2
      unhealthy_threshold = 3

      http_healthcheck {
        path = "/"
      }
    }
  }
}

# РОУТЕР
resource "yandex_alb_http_router" "web_router" {
  name = "web-http-router"
}

# ХОСТ
resource "yandex_alb_virtual_host" "web_vhost" {
  name           = "web-virtual-host"
  http_router_id = yandex_alb_http_router.web_router.id
  route {
    name = "root-route"
    http_route {
      http_match {
        path {
          prefix = "/"
        }
      }
      http_route_action {
        backend_group_id = yandex_alb_backend_group.web_backends.id
        timeout          = "60s"
      }
    }
  }
}

# БАЛАНСИРОВЩИК
resource "yandex_alb_load_balancer" "main_alb" {
  name               = "main-load-balancer"
  network_id         = yandex_vpc_network.main.id
  security_group_ids = [yandex_vpc_security_group.alb_sg.id]

  allocation_policy {
    location {
      zone_id   = "ru-central1-a"
      subnet_id = yandex_vpc_subnet.public.id
    }
    location {
      zone_id   = "ru-central1-b"
      subnet_id = yandex_vpc_subnet.private-2.id 
    }
  }

  listener {
    name = "web-listener"
    endpoint {
      address {
        external_ipv4_address {}
      }
      ports = [80]
    }
    http {
      handler {
        http_router_id = yandex_alb_http_router.web_router.id
      }
    }
  }
}

# БЭКАПЫ
resource "yandex_backup_policy" "netology_backup_policy" {
  name = "netology-backup-policy"

  scheduling {
    enabled = true
    backup_sets {
      execute_by_time {
        type = "DAILY"
        repeat_at = ["00:00"]
        }
    }
  }

  retention {
    after_backup = false
    rules {
      max_count = 7
    }
  }

  reattempts {}
  vm_snapshot_reattempts {}
}

resource "yandex_backup_policy_bindings" "netology_bindings" {
for_each = merge(
    { for i, v in yandex_compute_instance.web : v.name => v.id },
    {
      "bastion"       = yandex_compute_instance.bastion.id,
      "elasticsearch" = yandex_compute_instance.elasticsearch.id,
      "kibana"        = yandex_compute_instance.kibana.id,
      "zabbix"        = yandex_compute_instance.zabbix.id
    }
  )

  policy_id   = yandex_backup_policy.netology_backup_policy.id
  instance_id = each.value
}

# ИНВЕНТАРЬ ДЛЯ АНСИБЛА
resource "local_file" "ansible_inventory" {
  content = templatefile("hosts.tftpl",
    {
      bastion_ip     = yandex_compute_instance.bastion.network_interface.0.nat_ip_address
      zabbix_ip      = yandex_compute_instance.zabbix.network_interface.0.nat_ip_address
      bastion        = yandex_compute_instance.bastion.fqdn
      web_nodes      = yandex_compute_instance.web[*]
      zabbix         = yandex_compute_instance.zabbix.fqdn
      kibana         = yandex_compute_instance.kibana.fqdn
      elasticsearch  = yandex_compute_instance.elasticsearch.fqdn
    }
  )
  filename = "ansible/hosts.ini" 
}

# АДРЕСА
resource "local_file" "IPs" {
  filename = "${path.module}/IPs"
  content  = <<EOT
=== PUBLIC IPs ===
Bastion SSH:  ${yandex_compute_instance.bastion.network_interface.0.nat_ip_address}
Zabbix Web:   http://${yandex_compute_instance.zabbix.network_interface.0.nat_ip_address}
Kibana Web:   http://${yandex_compute_instance.kibana.network_interface.0.nat_ip_address}:5601
Website URL:  http://${yandex_alb_load_balancer.main_alb.listener.0.endpoint.0.address.0.external_ipv4_address.0.address}

=== SSH JUMP COMMANDS ===
%{ for instance in concat(
    yandex_compute_instance.web[*],
    [yandex_compute_instance.elasticsearch],
    [yandex_compute_instance.kibana],
    [yandex_compute_instance.zabbix]
  ) ~}
${format("%-15s", instance.name)}: ssh -J ubuntu@${yandex_compute_instance.bastion.network_interface.0.nat_ip_address} ubuntu@${instance.network_interface.0.ip_address}
%{ endfor ~}
EOT
}