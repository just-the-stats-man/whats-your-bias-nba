archive_revision <- '13f2e6ac8aed3cb6cfea6e81a0db088006357e95'
file_sha256 <- function(path) {
  # Read directly: Windows managed filesystems can report file.access() == -1
  # for readable OneDrive files, which digest(file=...) rejects.
  digest::digest(readBin(path, 'raw', n=file.info(path)$size),algo='sha256',serialize=FALSE)
}
season_label <- function(end_year) sprintf('%d-%02d', end_year - 1L, end_year %% 100L)
season_end <- function(season) {
  if (length(season) != 1L || !grepl('^[0-9]{4}-[0-9]{2}$', season)) stop('Use season YYYY-YY')
  end <- as.integer(substr(season, 1, 4)) + 1L
  if (season_label(end) != season) stop('Invalid season mapping')
  end
}
normalize_name <- function(x) tolower(iconv(x, from = 'UTF-8', to = 'ASCII//TRANSLIT'))

fetch_cached <- function(url, path, refresh = FALSE, perform = httr2::req_perform) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(path) && !refresh) return(path)
  req <- httr2::request(url) |>
    httr2::req_user_agent('whats-your-bias-nba/0.1 (research archive client)') |>
    httr2::req_timeout(120) |>
    httr2::req_retry(max_tries = 5, max_seconds = 180) # exponential backoff, Retry-After/429
  etag_path <- paste0(path, '.etag')
  if (file.exists(path) && file.exists(etag_path)) req <- httr2::req_headers(req, 'If-None-Match' = readLines(etag_path, warn = FALSE)[1])
  response <- perform(req)
  if (httr2::resp_status(response) == 304L) return(path)
  tmp <- tempfile(tmpdir = dirname(path))
  on.exit(unlink(tmp), add = TRUE)
  writeBin(httr2::resp_body_raw(response), tmp)
  # Parse before replacing a valid cache entry.
  arrow::read_parquet(tmp, as_data_frame = FALSE)
  if (!file.copy(tmp, path, overwrite = TRUE)) stop('Cache write failed')
  etag <- httr2::resp_header(response, 'etag')
  if (!is.null(etag)) writeLines(etag, etag_path)
  Sys.sleep(0.25)
  path
}

fetch_season <- function(season, revision = archive_revision, refresh = FALSE) {
  year <- season_end(season)
  specs <- c(schedules = 'nba_schedule', player_box = 'player_box', team_box = 'team_box', pbp = 'play_by_play')
  out <- lapply(names(specs), function(kind) {
    filename <- paste0(specs[[kind]], '_', year, '.parquet')
    url <- sprintf('https://raw.githubusercontent.com/sportsdataverse/hoopR-nba-data/%s/nba/%s/parquet/%s', revision, kind, filename)
    path <- file.path('data/raw', revision, filename)
    fetch_cached(url, path, refresh)
    list(data = as.data.frame(arrow::read_parquet(path)), path = path, url = url, revision = revision)
  })
  stats::setNames(out, names(specs))
}

fetch_game <- function(game_id, season, ...) {
  # Archive is partitioned by season. Cache reuse guarantees no repeated season download.
  bundle <- fetch_season(season, ...)
  lapply(bundle, function(item) {item$data <- item$data[as.character(item$data$game_id) == as.character(game_id), , drop = FALSE]; item})
}
