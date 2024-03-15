
#' @title Launch an RStudio addin which allows to schedule an Rscript interactively.
#' @description Launch an RStudio addin which allows to schedule an Rscript interactively.
#' 
#' @param RscriptRepository path to the folder where R scripts will be copied to and launched. Defaults to the extdata folder in the taskscheduleR R library
#' @param debug passed on to \code{\link{taskscheduler_create}}
#' @return the return of \code{\link[shiny]{runGadget}}
#' @export
#' @examples 
#' \dontrun{
#' taskschedulerAddin()
#' }
taskschedulerAddin <- function(RscriptRepository, 
                               debug = TRUE) {
  requireNamespace("shiny")
  requireNamespace("miniUI")
  current_repo <- file.path(system.file("extdata", package="taskscheduleR"), "RscriptRepository.rds")
  if(missing(RscriptRepository)){
    if(file.exists(current_repo)){
      RscriptRepository <- readRDS(file = current_repo)
    }else{
      RscriptRepository <- system.file("extdata", package="taskscheduleR")
      saveRDS(RscriptRepository, file = current_repo)
    }
  }
  local_dateformat <- file.path(system.file("extdata", package="taskscheduleR"), "dateformat.rds")
  if(file.exists(local_dateformat)){
    datefmt <- readRDS(file = local_dateformat)
  }else{
    datefmt <- "%d/%m/%Y"
    saveRDS(datefmt, file = local_dateformat)
  }
  
  check <- NULL
  
  ui <- miniUI::miniPage(
    # Shiny fileinput resethandler
    shiny::tags$script('
                       Shiny.addCustomMessageHandler("resetFileInputHandler", function(x) {
                       var id = "#" + x + "_progress";
                       var idBar = id + " .bar";
                       $(id).css("visibility", "hidden");
                       $(idBar).css("width", "0%");
                       });
                       '),
    
    miniUI::gadgetTitleBar("Schedule your Rscript fast and easy"),
    
    ## Your UI items go here.
    miniUI::miniTabstripPanel(
      miniUI::miniTabPanel(title = 'Upload and create', icon = shiny::icon("cloud-upload"),
                           miniUI::miniContentPanel(
                             shiny::fillCol(flex = c(1, 1, 3),
                                     shiny::fillRow(
                                       shiny::uiOutput('fileSelect'),
                                       miniUI::miniContentPanel(padding = 0, shiny::strong("Task checking: does the task already exist?"), shiny::textOutput("text"))
                                     ),
                                     shiny::fillRow(flex = 1,
                                                    shiny::textInput('rscript_repository', label = "Rscript repo: location where Rscripts will be copied to schedule + location of logs", value = RscriptRepository)),
                                     shiny::fillRow(flex = c(3, 3), 
                                                    shiny::radioButtons('task', label = "Schedule:", choices = c( 'ONCE', 'MONTHLY', 'WEEKLY', 'DAILY', 'HOURLY', 'MINUTE', 'ONLOGON', 'ONIDLE')),
                                             shiny::fillCol(
                                               shiny::dateInput('date', label = "Start date:", startview = "month", weekstart = 1, min = Sys.Date()),
                                               shiny::textInput('hour', label = "Hour start", value = format(Sys.time() + 122, "%H:%M")),
                                               shiny::textInput('rscript_args', label = "Additional arguments to Rscript", value = ""),
                                               shiny::textInput('date_fmt', label = "Date format of your locale", value = datefmt)
                                             ))
                             )
                           ),
                           miniUI::miniButtonBlock(border = "bottom",
                                                   shiny::actionButton('create', "Create task", icon = shiny::icon("play-circle"))
                           )
      ),
      miniUI::miniTabPanel(title = 'Stop or Delete', icon = shiny::icon("table"),
                           miniUI::miniContentPanel(
                             shiny::uiOutput("getFiles")
                           ),
                           miniUI::miniButtonBlock(border = "bottom",
                                                   shiny::actionButton('Stop', "Stop task", icon = shiny::icon("stop")),
                                                   shiny::actionButton('Delete', "Delete task", icon = shiny::icon("remove"))
                           )
      )
    )
    )
  
  # Server code for the gadget.
  server <- function(input, output, session) {
    
    # Ui element for fileinput
    output$fileSelect <- shiny::renderUI({
      shiny::fileInput(inputId = 'file', 'Choose your Rscript',
                accept = c("R-bestand"),
                multiple = FALSE)
    })
    
    # When file has been uploaded check if it already exists
    shiny::observeEvent(input$file, {
      output$text <- shiny::renderText({
        # TRUE if script already has a task
        # FALSE if script has no tasks
        if(input$file$name %in% list.files(RscriptRepository, pattern = ".R$|.r$")){
          check <<- TRUE
          sprintf("Rscript %s already exists. \n Continuing will overwrite and make a new task schedule",
                  input$file$name)
        } else {
          check <<- FALSE
          sprintf("Schedulingtask for Rscript %s does not exist yet",
                  input$file$name)
        }
      })
    })
    
    # When path to Rscript repository has been changed
    shiny::observeEvent(input$rscript_repository, {
      RscriptRepository <<- normalizePath(input$rscript_repository, winslash = "/")
      output$text <- shiny::renderText({
        if(file.exists(RscriptRepository) && file.info(RscriptRepository)$isdir == TRUE){
          saveRDS(RscriptRepository, file = current_repo)
        } else {
          sprintf("RscriptRepository %s does not exist, make sure this is an existing directory without spaces", RscriptRepository)
        }
      })
    })
    # When date format has been changed
    shiny::observeEvent(input$date_fmt, {
      datefmt <<- input$date_fmt
      saveRDS(datefmt, file = local_dateformat)
    })
    
    ###########################
    # CREATE / OVERWRITE
    ###########################
    shiny::observeEvent(input$create, {
      shiny::req(input$task)
      shiny::req(input$file)
      
      if(input$task == "MONTHLY" ){
        days <- format(input$date, "%d")
      }
      else if(input$task == "WEEKLY"){
        weekdays <- c("MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN")
        idx <- as.integer(format(input$date, "%w"))
        days <- weekdays[ifelse(idx == 0, 7, idx)]
      }
      else {
        # get default value by setting days to null.
        days <- NULL
      }
      starttime <- input$hour
      rscript_args <- input$rscript_args
      
      ##
      ## Copy the uploaded file from the webapp to the main folder to store the scheduled rscripts.
      ##
      if(length(grep(" ", RscriptRepository)) > 0){
        stop(sprintf("Make sure the RscriptRepository does not contain spaces, change argument %s to another location on your drive which contains no spaces", RscriptRepository))
      }
      myscript <- paste0(RscriptRepository, "/", input$file$name)
      done <-  file.copy(input$file$datapath, myscript, overwrite = TRUE)
      if(!done){
        stop(sprintf('Copying file %s to %s failed. Do you have access rights to %s?', file.path(input$file$datapath, input$file$name), myscript, dirname(myscript)))
      }
      ##
      ## Make schedule task
      ##
      if(check){
        taskscheduler_delete(taskname = input$file$name)
        taskscheduler_create(taskname = input$file$name, rscript = myscript, schedule = input$task, startdate = format(input$date, input$date_fmt), starttime = starttime, days = days, rscript_args = rscript_args, debug = debug)
      } else {
        taskscheduler_create(taskname = input$file$name, rscript = myscript, schedule = input$task, startdate = format(input$date, input$date_fmt), starttime = starttime, days = days, rscript_args = rscript_args, debug = debug)
      }
      
      # Reset ui inputs
      shiny::updateDateInput(session, inputId = 'date', value = Sys.Date())
      shiny::updateRadioButtons(session, inputId = 'task', selected = "ONCE")
      shiny::updateSelectInput(session, inputId = "days", selected = "*")
      shiny::updateTextInput(session, inputId = "hour", value = format(Sys.time() + 122, "%H:%M"))
      shiny::updateTextInput(session, inputId = "rscript_args", value = "")
      output$fileSelect <- shiny::renderUI({
        shiny::fileInput(inputId = 'file', 'Choose your Rscript',
                  accept = c("R-bestand"),
                  multiple = FALSE)
      })
      shiny::updateSelectInput(session, inputId="getFiles", choices = list.files(RscriptRepository, pattern = ".R$|.r$"))
      
      output$text <- shiny::renderText({""})
      
    })
    
    ###########################
    # Schedule list
    ###########################
    output$getFiles <- shiny::renderUI({
      shiny::selectInput(inputId = 'getFiles', "Select Task", choices = list.files(RscriptRepository, pattern = ".R$|.r$"))
    })
    
    ###########################
    # STOP
    ###########################
    shiny::observeEvent(input$Stop, {
      shiny::updateSelectInput(session, inputId="getFiles", choices = list.files(RscriptRepository, pattern = ".R$|.r$"))
      taskscheduler_stop(taskname = input$getFiles)
    })
    
    ###########################
    # DELETE
    ###########################
    shiny::observeEvent(input$Delete, {
      taskscheduler_delete(taskname = input$getFiles)
      try(file.remove(file.path(RscriptRepository, input$getFiles)))
      shiny::updateSelectInput(session, inputId="getFiles", choices = list.files(RscriptRepository, pattern = ".R$|.r$"))
      
    })
    
    # Listen for the 'done' event. This event will be fired when a user
    # is finished interacting with your application, and clicks the 'done'
    # button.
    shiny::observeEvent(input$done, {
      # Here is where your Shiny application might now go an affect the
      # contents of a document open in RStudio, using the `rstudioapi` package.
      # At the end, your application should call 'stopApp()' here, to ensure that
      # the gadget is closed after 'done' is clicked.
      shiny::stopApp()
    })
  }
  
  # Use a modal dialog as a viewr.
  viewer <- shiny::dialogViewer("Task ScheduleR", width = 700, height = 600)
  shiny::runGadget(ui, server, viewer = viewer)
}

