context("taskscheduler-examples")

test_that("taskscheduleR examples can be scheduled as expected", {
  skip_on_cran()

  myscript <- system.file("extdata", "helloworld.R", package = "taskscheduleR")
  
  ## run script once within 62 seconds
  expect_warning(taskscheduler_create(taskname = "myfancyscript", rscript = myscript, 
                       schedule = "ONCE", starttime = format(Sys.time() + 62, "%H:%M")), NA)
  
  ## get a data.frame of all tasks
  expect_warning({
    tasks <- taskscheduler_ls()
  })

  ## delete the tasks
  expect_warning(taskscheduler_delete(taskname = "myfancyscript"), NA)
})



test_that("taskscheduler_ls returns a data.frame", {
  skip_on_cran()
  expect_is(suppressWarnings({taskscheduler_ls()}), "data.frame")
})