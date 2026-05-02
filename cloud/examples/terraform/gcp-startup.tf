# Example Terraform — GCP Managed Instance Group with CSW agent installed via startup-script.
#
# Pattern: a per-cluster startup script reads the agent package from GCS and
# the activation key from Secret Manager using the VM's service account.

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.20"
    }
  }
}

provider "google" {}

variable "project_id"            { type = string }
variable "region"                { type = string }
variable "zone"                  { type = string }
variable "subnetwork"            { type = string }
variable "csw_pkg_gcs_path"      { type = string description = "gs://bucket/path/to/tet-sensor.rpm" }
variable "csw_ca_gcs_path"       { type = string description = "gs://bucket/path/to/ca.pem" }
variable "csw_secret_id"         { type = string description = "secret resource ID for CSW activation key" }
variable "csw_cluster_endpoint"  { type = string }

resource "google_service_account" "csw_vm" {
  account_id   = "csw-vm-sa"
  display_name = "CSW VM service account"
}

resource "google_secret_manager_secret_iam_member" "csw_secret_access" {
  secret_id = var.csw_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.csw_vm.email}"
}

resource "google_storage_bucket_iam_member" "csw_pkg_read" {
  bucket = element(split("/", var.csw_pkg_gcs_path), 2)
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.csw_vm.email}"
}

resource "google_compute_instance_template" "app" {
  name_prefix  = "app-template-"
  machine_type = "e2-standard-2"
  region       = var.region

  disk {
    source_image = "projects/rhel-cloud/global/images/family/rhel-9"
    auto_delete  = true
    boot         = true
  }

  network_interface {
    subnetwork = var.subnetwork
    access_config {}
  }

  service_account {
    email  = google_service_account.csw_vm.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    startup-script = templatefile("${path.module}/../cloud-init/gcp-csw-rhel9.sh", {
      csw_pkg_gcs_path     = var.csw_pkg_gcs_path
      csw_ca_gcs_path      = var.csw_ca_gcs_path
      csw_secret_id        = var.csw_secret_id
      csw_cluster_endpoint = var.csw_cluster_endpoint
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_instance_group_manager" "app" {
  name               = "app-mig"
  base_instance_name = "app"
  zone               = var.zone
  target_size        = 3

  version {
    instance_template = google_compute_instance_template.app.id
  }

  update_policy {
    type                  = "PROACTIVE"
    minimal_action        = "REPLACE"
    max_surge_fixed       = 1
    max_unavailable_fixed = 0
    replacement_method    = "SUBSTITUTE"
  }
}
