#' Do fisher test for only one pathway from search result
#' clicked on highchart
#' @param pathwaydf a data frame resulting from rampFastPathFromMeta
#' @param total_metabolites number of metabolites analyzed in the experiment (e.g. background) (default is total number of metabolites that map to a pathway in RaMP, with assumption that analyte_type is "metabolite")
#' @param total_genes number of genes analyzed in the experiment (e.g. background) (default is 20000, with assumption that analyte_type is "genes")
#' @param analyte_type "metabolites" or "genes" (default is "metabolites")
#' @param conpass password for database access (string)
#' @param dbname name of the mysql database (default is "ramp")
#' @param username username for database access (default is "root")
#' @return a dataframe with pathway enrichment (based on Fisher's test) results
#' @export
runFisherTest <- function(pathwaydf,total_metabolites=NULL,total_genes=20000,
                              analyte_type="metabolites",conpass=NULL,
                              dbname="ramp",username="root"){
  print("Fisher Testing ......")
  if (!(analyte_type == "metabolites" | analyte_type == "genes")){
    stop("Please define the analyte_type variable to 'metabolites' or 'genes'")
  }
  if(is.null(conpass)) {
    stop("Please define the password for the mysql connection")
  }
  
  contingencyTb <- matrix(0,nrow = 2,ncol = 2)
  colnames(contingencyTb) <- c("In Pathway","Not In Pathway")
  rownames(contingencyTb) <- c("All Metabolites","User's Metabolites")
  
  # Get the total number of analytes in the input pathway:
  pid <- unique(pathwaydf$pathwayRampId);

  # Get the total number of metabolites that are mapped to pathways in RaMP (that's the default background)
   query <- "select distinct(rampId) from analytehaspathway"
   con <- DBI::dbConnect(RMySQL::MySQL(), user = username,
         password = conpass,
         dbname = dbname)
   allids <- DBI::dbGetQuery(con,query)
   DBI::dbDisconnect(con)

  if((analyte_type == "metabolites") && (is.null(total_metabolites))) {
	total_analytes <- length(grep("RAMP_C",allids[,"rampId"]))
  }

  # Retrieve the Ramp compound ids associated with the ramp pathway id and count them:
   query1 <- paste0("select rampId,pathwayRampId from analytehaspathway where pathwayRampId in (\"",
   pid,"\")")  
  
   con <- DBI::dbConnect(RMySQL::MySQL(), user = username,
         password = conpass,
         dbname = dbname)
   cids <- DBI::dbGetQuery(con,query1)#[[1]]
   DBI::dbDisconnect(con)

   # Loop through each pathway, build the contingency table, and calculate Fisher's Exact
   # test p-value
   pval=c()
   for (i in pid) {
	curpathcids <- unique(cids[which(cids[,"pathwayRampId"]==i),"rampId"])
	if(analyte_type=="metabolites") {
		tot_in_pathway <- length(grep("RAMP_C",cids))
	}else {
		tot_in_pathway <- length(grep("RAMP_G",cids))
	}
 	tot_out_pathway <- total_analytes - tot_in_pathway 
	  # fill the rest of the table out
	  user_in_pathway <- nrow(pathwaydf)
	  user_out_pathway <- total_analytes - user_in_pathway
	  contingencyTb[1,1] <- tot_in_pathway
	  contingencyTb[1,2] <- tot_out_pathway
	  contingencyTb[2,1] <- user_in_pathway
	  contingencyTb[2,2] <- user_out_pathway 
	  result <- stats::fisher.test(contingencyTb)
	  pval <- c(pval,round(result$p.value,4) )
  }
  fisher.adj.pval <- p.adjust(pval,method='fdr')

  # format output (retrieve pathway name for each unique source id first
  out <- data.frame(pathwayRampId=pid, Pval=pval,Adjusted.Pval=fisher.adj.pval)
  out2 <- merge(out,pathwaydf,by="pathwayRampId",all.x=TRUE)

  return(out2[,c("pathwayName", "Pval", "Adjusted.Pval", "pathwaysourceId", "pathwaysource")])
}

#' Reformat the result of query (get pathways from analyte(s)) for input into barplot
#' function
#' 
#' each pathway contains all metabolites inside that pathway
#' @param df A dataframe that has information for bar plot
#' @return a list with the analyte names for each pathway that is represented in the list
rampGenerateBarPlot <- function(df){
  path_meta_list <- list()
  for (i in 1:nrow(df)){
    if (length(path_meta_list)==0){
      path_meta_list[[df[i,]$pathwaysourceId]] <- data.frame(metabolite = df[i,]$rampId,stringsAsFactors = F)
    } else {
      path_meta_list[[df[i,]$pathwaysourceId]] <- 
		rbind(path_meta_list[[df[i,]$pathwaysourceId]],df[i,]$rampId)
      path_meta_list[[df[i,]$pathwaysourceId]] <- 
	unique(path_meta_list[[df[i,]$pathwaysourceId]])
    }
  }
  return(path_meta_list)
}

#' PathFromMetast search given a list of metabolites
#' @param analytes a vector of analytes (genes or metabolites) that need to be searched
#' @param find_synonym find all synonyms or just return same synonym (T/F)
#' @param conpass password for database access (string)
#' @param NameOrIds whether input is "names" or "ids" (default is "ids")
#' @param dbname name of the mysql database (default is "ramp")
#' @param username username for database access (default is "root")
#' @return a list contains all metabolits as name and pathway inside.
#' 
#' @export
rampFastPathFromMeta<- function(analytes,
	find_synonym = FALSE,
	conpass=NULL,
	dbname="ramp",
	username="root",
	NameOrIds = "ids"){

  if(is.null(conpass)) {
        stop("Please define the password for the mysql connection")
  }

  now <- proc.time()

  if(NameOrIds == "names"){
    synonym <- RaMP:::rampFindSynonymFromSynonym(synonym=analytes,
	find_synonym=find_synonym,
	conpass=conpass)
    colnames(synonym)[1]="commonName"
    synonym$commonName <- tolower(synonym$commonName)
    if(nrow(synonym)==0) {
	stop("Could not find any matches to the analytes entered.  If pasting, please make sure the names are delimited by end of line (not analyte per line)\nand that you are selecting 'names', not 'ids'");
    }
    # Get all unique RaMP ids and call it list_metabolite
    list_metabolite <- unique(synonym$rampId)
    list_metabolite <- sapply(list_metabolite,shQuote)
    list_metabolite <- paste(list_metabolite,collapse = ",")
  } else if (NameOrIds == "ids"){
    sourceramp <- RaMP:::rampFindSourceRampId(sourceId=analytes, conpass=conpass)
    if (nrow(sourceramp)==0) {
	stop("Make sure you are actually inputting ids and not names (you have NameOrIds set to 'ids'. If you are, then no ids were matched in the RaMP database.")
	}
    # get all unique RaMP ids and call it list_metabolite
    list_metabolite <- unique(sourceramp$rampId)
    #sourceIDTable <- list_metabolite
    #list_metabolite <- list_metabolite$rampId
    list_metabolite <- sapply(list_metabolite,shQuote)
    list_metabolite <- paste(list_metabolite,collapse = ",")
  } else {
	stop("Make sure NameOrIds is set to 'names' or 'ids'")
  }
  # Parse data to fit mysql
  # Can be simplified here
  if(list_metabolite=="") {
	stop("Unable to retrieve metabolites")
  }

  # Now using the RaMP compound id, retrieve associated pathway ids 
    query2 <- paste0("select pathwayRampId,rampId from analytehaspathway where 
                      rampId in (",
                     list_metabolite,");")
    con <- connectToRaMP(dbname=dbname,username=username,conpass=conpass)
    df2 <- DBI::dbGetQuery(con,query2)
    DBI::dbDisconnect(con)
  pathid_list <- df2$pathwayRampId
  pathid_list <- sapply(pathid_list,shQuote)
  pathid_list <- paste(pathid_list,collapse = ",")
  # With pathway ids, retrieve pathway information
  query3 <- paste0("select pathwayName,sourceId as pathwaysourceId,type as pathwaysource,pathwayRampId from pathway where pathwayRampId in (",
                    pathid_list,");")
  con <- connectToRaMP(dbname=dbname,username=username,conpass=conpass)
  df3 <- DBI::dbGetQuery(con,query3)
  DBI::dbDisconnect(con)
 
  #Format output
  mdf <- merge(df3,df2,all.x = T)
 
  # And with rampIds (list_metabolite), get common names when Ids are input
  if(NameOrIds == "ids"){
     list_analytes <- sapply(analytes,shQuote) 
     list_analytes <- paste(list_analytes,collapse = ",")
  query4 <-paste0("select sourceId,commonName,rampId from source where sourceId in (",list_analytes,");")

  con <- connectToRaMP(dbname=dbname,username=username,conpass=conpass)
  df4 <- DBI::dbGetQuery(con,query4)
  DBI::dbDisconnect(con)
  mdf <- merge(mdf,df4,,all.x = T,by.y = "rampId")
  mdf$commonName=tolower(mdf$commonName)
 } else{ # Just take on the name
  mdf <- merge(mdf,synonym,all.x = T,by.y = "rampId")
 }

  return(mdf[!duplicated(mdf),])
}

#' Generate data.frame from given files
#' 
#' identifing the file type, then it returns table output to 
#' shiny renderTable function as preview of searching data
#' 
#' @param infile a file object given from files 
#' @param NameOrIds whether to return "synonyms" or "ids" (default is "ids")
#' @param conpass password for database access (string)
#' @param dbname name of the mysql database (default is "ramp")
#' @param username username for database access (default is "root")
#' 
#' @return a data.frame either from multiple csv file
#' or search through by a txt file.
rampFileOfPathways <- function(infile,NameOrIds="ids",
	conpass=NULL,
	dbname="ramp",
	username="root"){
  name <- infile[[1,'name']]
    summary <- data.frame(pathway  = character(0),id = character(0),
                          source = character(0),metabolite = character(0))
    rampOut <- list()
    for (i in 1:length(infile[,1])){
      if(infile[[i,'type']]!="text/plain"){
        rampOut[[i]] <- utils::read.table(infile[[i,'datapath']])
        name <- infile[[i,'name']]
        print(infile[[i,'type']])
        rampOut[[i]]$new.col <- substr(name,1,nchar(name) - 4)
        colnames(rampOut[[i]]) <- c("pathway","id","source","metabolite")
        summary <- rbind(summary,rampOut[[i]])
      } else {
        rampOut <- readLines(infile[[i,'datapath']])
        summary <- RaMP:::rampFastPathFromMeta(rampOut,NameOrIds=NameOrIds,
		conpass=.conpass,username=username,dbname=dbname
		)
      }
    }
    return(summary)
}

#' highchart output for RaMP and fisher test.
#' 
#' Based on given x,y data, type and click event, it returns a highcharter object
#' to highchartOutput function to display bar plot.
#' 
#' @param x_data vector contains data for categorical x-axis
#' @param y_data vector contains frequency of each pathway
#' @param type plot's type of this highcharter object
#' @param event_func Javascript code that define the click event
#' @return highcharter object
rampHcOutput <- function(x_data,y_data,type = 'column',event_func){
  fomatterFunc <- highcharter::JS("function(){
                        html = '<strong> Pathway ' + this.x +' has frequency: ' + this.y +'. metabolites are :'
                        '+this.y.detail+'</strong>;'
                        return html;
                     }")
  hc<-highcharter::highchart() %>%
    highcharter::hc_chart(type = type,
             # options3d = list(enabled = TRUE, beta = 15, alpha = 15),
             borderColor = '#ceddff',
             borderRadius = 10,
             borderWidth = 2,
             zoomType = "x",
             backgroundColor = list(
               linearGradient = c(0, 0, 500, 500),
               stops = list(
                 list(0, 'rgb(255, 255, 255)'),
                 list(1, 'rgb(219, 228, 252)')
               ))) %>%
    highcharter::hc_title(text = "<strong>Search result from given metabolites</strong>",
             margin = 20,align = "left",
             style = list(color = "black",useHTML = TRUE)) %>%
    highcharter::hc_xAxis(categories = x_data) %>%
    highcharter::hc_yAxis(allowDecimals = FALSE,
             title = list(
               text = "Frequency"
             )) %>%
    highcharter::hc_add_series(data = y_data,
                  name = "pathway"
                  ) %>%
    highcharter::hc_plotOptions(
      series = list(stacking = FALSE,
                    events = list(
                      click = event_func
                    ))) %>%
    highcharter::hc_tooltip(headerFormat = "<span>{point.key} has frequency {point.y}</span>
               <div style ='margin:0px;ma-xwidth:300px;overflow-y:hidden;'>",
               pointFormat = "<p class = 'tab3-tooltip-hc'>Metabolites: {point.detail}</p>",
               footerFormat = "</div>",
              # formatter = fomatterFunc,
               shared = TRUE,
               useHTML = TRUE) %>%
    highcharter::hc_exporting(enabled = TRUE)
  return(hc)
}
