terraform {
  required_version = ">= 1.10"

  required_providers {
    vsphere = {
      source  = "vmware/vsphere"
      version = "~> 2.16"
    }
  }

  # Remote state on Wasabi (S3-compatible). The bucket pre-exists (created
  # out-of-band before `init`). Credentials come from AWS_ACCESS_KEY_ID /
  # AWS_SECRET_ACCESS_KEY in the environment (mapped from wasabi-homeoffice-k8s.creds).
  # use_lockfile = native S3 conditional-write locking (no DynamoDB). The skip_*
  # flags + skip_s3_checksum are required for non-AWS S3 endpoints like Wasabi.
  backend "s3" {
    bucket = "homeoffice-k8s-tfstate"
    key    = "homeoffice-k8s/terraform.tfstate"
    region = "us-east-1"

    endpoints                   = { s3 = "https://s3.us-east-1.wasabisys.com" }
    use_lockfile                = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
  }
}
