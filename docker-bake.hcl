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
