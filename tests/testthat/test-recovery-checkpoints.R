withr::local_dir(Sys.getenv('WYB_ROOT'))
testthat::test_that('checkpoint keys ignore incidental row names and diagnostic attributes, not evidence', {
  x<-data.frame(id=c('a','b'),value=c(1,2));a<-terminal_checkpoint_key(x,x,x,x,x,'m')
  y<-x;rownames(y)<-c('100','300');attr(y,'player_links')<-data.frame(order=c(2,1))
  testthat::expect_identical(terminal_checkpoint_key(y,y,y,y,y,'m'),a)
  y$value[1]<-3;testthat::expect_false(identical(terminal_checkpoint_key(y,x,x,x,x,'m'),a))
  testthat::expect_false(identical(terminal_checkpoint_key(x,x,x,x,x,'different-method'),a))
})
