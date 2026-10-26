withr::local_dir(Sys.getenv('WYB_ROOT'))
projection_fixture <- function() {
  x<-normalize_bundle(readRDS('data/sample/bundle.rds'),'2024-25');id<-x$games$game_id[1]
  list(e=x$pbp_events[x$pbp_events$game_id==id,],p=merge(x$player_box_scores[x$player_box_scores$game_id==id,],x$players[c('player_id','name')],by='player_id'),g=x$games[x$games$game_id==id,])
}
testthat::test_that('licensed historical and modern regression games preserve source evidence', {
  cases<-readRDS('data/sample/phase3_recovery_cases.rds');h<-cases[['220215013']];m<-cases[['400974774']]
  a<-recovery_projection(h$e,h$p)
  testthat::expect_gt(length(reconstruct_possessions(h$e,h$g,h$p)$issues),0)
  testthat::expect_length(reconstruct_possessions(a$e,h$g,a$p)$issues,0L)
  testthat::expect_setequal(a$e$event_id,h$e$event_id)
  testthat::expect_identical(a$e$description[match(h$e$event_id,a$e$event_id)],h$e$description)
  a<-recovery_projection(m$e,m$p)
  testthat::expect_gt(length(reconstruct_lineups(m$e,m$g,m$p)$issues),0)
  testthat::expect_length(reconstruct_lineups(a$e,m$g,a$p)$issues,0L)
  testthat::expect_true(all(reconstruct_lineups(a$e,m$g,a$p)$checks$passed))
  testthat::expect_true(all(nchar(m$manifests$sha256)==64L))
})
testthat::test_that('complete numbered trips reorder only derived inputs and reject intervening ball events', {
  x<-projection_fixture();ix<-which(grepl('Free Throw - [12] of 2',x$e$event_type));groups<-split(ix,paste(x$e$period[ix],x$e$clock[ix],x$e$player_id[ix]));ix<-Filter(function(z)length(z)==2L && diff(z)==1L,groups)[[1]]
  original<-x$e;x$e[ix,]<-x$e[rev(ix),];x$e$event_order<-original$event_order
  a<-recovery_projection(x$e,x$p)
  testthat::expect_identical(a$e$event_id,original$event_id)
  testthat::expect_identical(a$e$event_order,original$event_order)
  testthat::expect_identical(x$e$event_id[ix],rev(original$event_id[ix]))
  testthat::expect_true(any(a$audit$rule=='complete_numbered_same_clock_free_throw_trip'))
  testthat::expect_identical(recovery_projection(a$e,a$p)$e,a$e)
  bad<-x$e;bad$event_type[ix[1]]<-'Free Throw - Technical 2 of 2'
  testthat::expect_false(any(recovery_projection(bad,x$p)$audit$rule=='complete_numbered_same_clock_free_throw_trip'))
  bad<-x$e;bad$event_type[ix[1]]<-'Free Throw - 1 of 2'
  testthat::expect_false(any(recovery_projection(bad,x$p)$audit$rule=='complete_numbered_same_clock_free_throw_trip'))
})
testthat::test_that('explicit substitution names recover absent IDs and retain conflicting observations', {
  x<-projection_fixture();j<-which(grepl('Substitution',x$e$event_type))[1];original<-x$e$secondary_player_id[j]
  x$e$secondary_player_id[j]<-NA_character_;a<-recovery_projection(x$e,x$p)
  testthat::expect_identical(a$e$secondary_player_id[j],original)
  testthat::expect_true(any(a$audit$rule=='exact_roster_name_in_observed_substitution'))
  bad<-x$e;bad$player_id[j]<-original
  recovered<-recovery_projection(bad,x$p)
  testthat::expect_identical(recovered$e$player_id[j],x$e$player_id[j])
  testthat::expect_identical(recovered$e$secondary_player_id[j],original)
  bad<-x$e;bad$secondary_player_id[j]<-'espn:conflict'
  testthat::expect_identical(recovery_projection(bad,x$p)$e$secondary_player_id[j],'espn:conflict')
  bad<-x$e;bad$description[j]<-sub(' for .*',' for Unknown Player',bad$description[j])
  testthat::expect_true(is.na(recovery_projection(bad,x$p)$e$secondary_player_id[j]))
  bad<-x$p;bad$name[bad$player_id==original]<-'Unknown Player'
  testthat::expect_true(is.na(recovery_projection(x$e,bad)$e$secondary_player_id[j]))
})
testthat::test_that('explicit jump winners require an exact unique roster name', {
  x<-projection_fixture();j<-which(grepl('Jumpball|Jump Ball',x$e$event_type))[1];original<-x$e$tertiary_player_id[j]
  x$e$tertiary_player_id[j]<-NA_character_;a<-recovery_projection(x$e,x$p)
  testthat::expect_identical(a$e$tertiary_player_id[j],original)
  testthat::expect_true(any(a$audit$rule=='exact_roster_name_explicit_jump_winner'))
  bad<-x$e;bad$description[j]<-'Held ball; winner unavailable'
  testthat::expect_true(is.na(recovery_projection(bad,x$p)$e$tertiary_player_id[j]))
  bad<-x$p;winner<-bad$name[bad$player_id==original];bad$name[1:2]<-winner
  testthat::expect_true(is.na(recovery_projection(x$e,bad)$e$tertiary_player_id[j]))
})
testthat::test_that('missing starter flags use unique observed constraints and original minute bounds', {
  x<-projection_fixture();x$p$starter<-NA;a<-recovery_projection(x$e,x$p)
  testthat::expect_true(any(a$audit$rule=='unique_initial_five_missing_starter_flags'))
  testthat::expect_true(all(is.na(x$p$starter)))
  testthat::expect_length(reconstruct_lineups(a$e,x$g,a$p)$issues,0L)
  bad<-x$p;bad$starter<-FALSE
  testthat::expect_true(all(!recovery_projection(x$e,bad)$p$starter))
  bad<-a$p;bad$minutes[1]<-bad$minutes[1]+5
  testthat::expect_true(any(grepl('precision bounds',reconstruct_lineups(a$e,x$g,bad)$issues)))
})
