# Source from the repository root. No network calls or installs on load.
if (dir.exists('.library')) .libPaths(c(normalizePath('.library'), .libPaths()))
dev_library <- Sys.getenv('WYB_DEV_LIBRARY')
if (nzchar(dev_library)) .libPaths(c(.libPaths(), dev_library))
for (f in sort(list.files('R', pattern = '\\.R$', recursive = TRUE, full.names = TRUE))) source(f)
