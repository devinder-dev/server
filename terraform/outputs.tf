output "public_ips" {
  description = "Public IPv4 address by VM name. Empty when no VMs are configured."
  value       = { for name, vm in oci_core_instance.vm : name => vm.public_ip }
}

output "s3_endpoint" {
  description = "Path-style S3-compatible endpoint in the commercial OCI realm."
  value       = "https://${data.oci_objectstorage_namespace.server.namespace}.compat.objectstorage.${var.region}.oci.customer-oci.com"
}

output "photos_app_user" {
  description = "The user that owns the photos bucket's S3 customer secret key. Create the key for this user in the Console."
  value       = oci_identity_user.photos_app.name
}

output "bucket_names" {
  description = "Object Storage bucket names by purpose."
  value       = { for purpose, bucket in oci_objectstorage_bucket.server : purpose => bucket.name }
}
