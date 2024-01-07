{{- $clusterName := .ClusterName}}
{{- $clusterHash := .ClusterHash}}

{{- if eq $.ClusterType "K8s" }}
variable "gcp_storage_disk_name" {
  default = "storage-disk"
  type    = string
}
{{- end }}

{{- range $i, $nodepool := .NodePools }}
{{- range $node := $nodepool.Nodes }}
resource "google_compute_instance" "{{ $node.Name }}" {
  provider                  = google.nodepool_{{ $nodepool.NodePool.Region }}
  zone                      = "{{ $nodepool.NodePool.Zone }}"
  name                      = "{{ $node.Name }}"
  machine_type              = "{{ $nodepool.NodePool.ServerType }}"
  description   = "Managed by Claudie for cluster {{ $clusterName }}-{{ $clusterHash }}"
  allow_stopping_for_update = true

  provisioning_model        = "{{- if $nodepool.NodePool.Spot -}}SPOT{{- else -}}STANDARD{{- end -}}"
  preemptible               = {{- if $nodepool.NodePool.Spot -}}true{{- else -}}false{{- end -}}
  automatic_restart         = {{- if $nodepool.NodePool.Spot -}}false{{- else -}}true{{- end -}}


  network_interface {
    subnetwork = google_compute_subnetwork.{{ $nodepool.Name }}_subnet.self_link
    access_config {}
  }

  metadata = {
    ssh-keys = "root:${file("./public.pem")}"
  }

  labels = {
    managed-by = "claudie"
    claudie-cluster = "{{ $clusterName }}-{{ $clusterHash }}"
  }

{{- if eq $.ClusterType "LB" }}
  boot_disk {
    initialize_params {
      size = "50"
      image = "{{ $nodepool.NodePool.Image }}"
    }
  }
  metadata_startup_script = "echo 'PermitRootLogin without-password' >> /etc/ssh/sshd_config && echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config && service sshd restart"
{{- end }}

{{- if eq $.ClusterType "K8s" }}
  boot_disk {
    initialize_params {
      size = "100"
      image = "{{ $nodepool.NodePool.Image }}"
    }
  }

  metadata_startup_script = <<EOF
  #!/bin/bash
  set -euxo pipefail
# Allow ssh as root
echo 'PermitRootLogin without-password' >> /etc/ssh/sshd_config && echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config && service sshd restart  
# Create longhorn volume directory
mkdir -p /opt/claudie/data
    {{- if and (not $nodepool.IsControl) (gt $nodepool.NodePool.StorageDiskSize 0) }}
# Mount managed disk only when not mounted yet
sleep 50
disk=$(ls -l /dev/disk/by-id | grep "google-${var.gcp_storage_disk_name}" | awk '{print $NF}')
disk=$(basename "$disk")
if ! grep -qs "/dev/$disk" /proc/mounts; then
  if ! blkid /dev/$disk | grep -q "TYPE=\"xfs\""; then
    mkfs.xfs /dev/$disk
  fi
  mount /dev/$disk /opt/claudie/data
  echo "/dev/$disk /opt/claudie/data xfs defaults 0 0" >> /etc/fstab
fi
    {{- end }}
EOF

  {{- if and (not $nodepool.IsControl) (gt $nodepool.NodePool.StorageDiskSize 0) }}
  # As the storage disk is attached via google_compute_attached_disk,
  # we must ignore attached_disk property.
  lifecycle {
    ignore_changes = [attached_disk]
  }
  {{- end }}

{{- end }}
}

{{- if eq $.ClusterType "K8s" }}
    {{- if and (not $nodepool.IsControl) (gt $nodepool.NodePool.StorageDiskSize 0) }}
resource "google_compute_disk" "{{ $node.Name }}_disk" {
  provider = google.nodepool_{{ $nodepool.NodePool.Region }}
  name     = "{{ $node.Name }}-disk"
  type     = "pd-ssd"
  zone     = "{{ $nodepool.NodePool.Zone }}"
  size     = {{ $nodepool.NodePool.StorageDiskSize }}

  labels = {
    managed-by = "claudie"
    claudie-cluster = "{{ $clusterName }}-{{ $clusterHash }}"
  }
}

resource "google_compute_attached_disk" "{{ $node.Name }}_disk_att" {
  provider    = google.nodepool_{{ $nodepool.NodePool.Region }}
  disk        = google_compute_disk.{{ $node.Name }}_disk.id
  instance    = google_compute_instance.{{ $node.Name }}.id
  zone        = "{{ $nodepool.NodePool.Zone }}"
  device_name = var.gcp_storage_disk_name
}
    {{- end }}
{{- end }}

{{- end }}

output "{{ $nodepool.Name }}" {
  value = {
  {{- range $node := $nodepool.Nodes }}
    "${google_compute_instance.{{ $node.Name }}.name}" = google_compute_instance.{{ $node.Name }}.network_interface.0.access_config.0.nat_ip
  {{- end }}
  }
}
{{- end }}
