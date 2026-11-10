variable "REPOSITORY" {
  default = "smtoznc/toolbox"
}

variable "VERSION" {
  default = "dev"
}

# Local build, loaded into the Docker daemon for testing and scanning.
target "default" {
  context    = "."
  dockerfile = "Dockerfile"
  target     = "toolbox"
  platforms  = ["linux/amd64"]
  args = {
    TOOLBOX_VERSION = VERSION
  }
  tags   = ["${REPOSITORY}:${VERSION}"]
  output = ["type=docker"]
}

# Release build. gzip and a plain manifest without attestations stay readable by every
# registry and scanner, including older ones an image may be mirrored to.
target "release" {
  inherits = ["default"]
  tags     = ["${REPOSITORY}:${VERSION}", "${REPOSITORY}:latest"]
  output   = ["type=registry,compression=gzip,compression-level=9,force-compression=true,oci-mediatypes=false"]
  attest   = ["type=provenance,disabled=true", "type=sbom,disabled=true"]
}

# Lite variant: Kubernetes and OpenShift clients, the shell, network and database clients from Ubuntu,
# and Python 3.14 with the browser terminal. Leaves out the largest tools and the other Pythons, which
# makes the image less than half the size and quicker to pull and scan.
variable "LITE_EXCLUDE" {
  default = "argocd,cosign,oras,crane,dive,rclone,duckdb,mongosh,mongodb-database-tools,gh,git-lfs,grpcurl,websocat,xh,miller,node,npm,python3.11,python3.12,python3.13"
}

target "lite" {
  inherits = ["default"]
  args = {
    TOOLBOX_VERSION = "${VERSION}-lite"
    TOOLBOX_EXCLUDE = LITE_EXCLUDE
  }
  tags = ["${REPOSITORY}:${VERSION}-lite"]
}

target "release-lite" {
  inherits = ["lite"]
  tags     = ["${REPOSITORY}:${VERSION}-lite", "${REPOSITORY}:lite"]
  output   = ["type=registry,compression=gzip,compression-level=9,force-compression=true,oci-mediatypes=false"]
  attest   = ["type=provenance,disabled=true", "type=sbom,disabled=true"]
}
