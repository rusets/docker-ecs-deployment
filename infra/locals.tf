############################################
# Local paths & hashes for Lambda packages
############################################
locals {
  wake_zip_path = "${path.module}/wake.zip"
  wake_zip_hash = try(filebase64sha256(local.wake_zip_path), "")

  sleep_zip_path = "${path.module}/sleep.zip"
  sleep_zip_hash = try(filebase64sha256(local.sleep_zip_path), "")
}
