require(ggrepel)
require(dplyr)
require(gridExtra)
require(ggforce)
require(ggplot2)
require(scales)
require(eeptools)
require(forcats)

#Demographics functions
#Age from DOB
age_na <- function(x) {
  if (!is.na(x)) {
    if (Sys.time() > as.POSIXlt(x)) {
      return(floor(age_calc(x, units = "years")))
    }
    else {
      return(NA)
    }
  }
  else {
    return(NA)
  }
}

#Chooses correct colours for graphs based on number of groupings
num_colours <- function(x) {
  switch(x,
         "#D7191C",
         c("#2B83BA", "#D7191C"),
         c("#2B83BA", "#D7191C", "#ABDDA4"),
         c("#2B83BA", "#D7191C", "#FDAE61", "#ABDDA4"),
         c("#2B83BA", "#D7191C", "#FDAE61", "#FFFF99", "#ABDDA4"),
         c("#2B83BA", "#D7191C", "#FDAE61", "#FFFF99", "#ABDDA4", "#5E4FA2"))
}

#ORS
#Formats scores for ORS severity graph - uses get_ors_domains and get_ors_average
get_ors <- function(data, group) {
  ors_domains <- get_ors_domains(data, group)
  ors_average <- get_ors_average(ors_domains, group)
  ors <- rbind(ors_domains, ors_average)
  ors$Question.Text <- factor(ors$Question.Text, levels = c("Individual", "Interpersonal", "Social", "Overall", "Average"))
  return(ors)
}

#Finds average values of the ORS domains based on grouping
get_ors_domains <- function(data, group) {
  group <- syms(c("Question.ID", "Question.Text", group))
  return(data %>%
           group_by(!!!group) %>%
           filter(Question.ID < 5) %>%
           summarise(Average = mean(ors_flip)) %>%
           arrange(Question.ID) %>%
           ungroup())
}

#Finds overall average of all domains based on grouping
get_ors_average <- function(data, group) {
  if (length(group) != 0) {
    group <- syms(group)
    data <- data %>%
      group_by(!!!group) 
  }
    average <- data %>%
      summarise(Average = mean(Average)) 
  average$Question.ID <- 5
  average$Question.Text <- "Average"
  return(average)
}

#Finds percentage of employees reporting symptoms of each psychological domain based on grouping
get_psych_symptoms <- function(data, group) {
  first_group = c("component", "User_ID", group)
  second_group = c("component", group)
  psych_symptoms <- data %>%
    filter(category == "Psychological") %>%
    mutate(affected = case_when(Normalized < 3 ~ 1, TRUE ~ 0)) %>%
    group_by(!!!syms(first_group)) %>%
    summarise(affected = if_else(sum(affected) > 0, 1, 0)) %>%
    ungroup() %>%
    group_by(!!!syms(second_group), .drop = FALSE) %>%
    summarise(Percent = sum(affected)/n()) %>%
    arrange(!!!syms(second_group))
  return(psych_symptoms)
}

#Finds workplace mental health scores for each domain based on grouping
get_workplace <- function(data, group) {
  group <- c("component", group)
  data %>%
    filter(category == "Workplace") %>%
    group_by(!!!syms(group)) %>%
    mutate(Percent = Normalized/3) %>%
    summarise(Percent = mean(Percent)) %>%
    arrange(component)
}

#Combines benchmark data with regular company data into one data frame
add_bm <- function(data, benchmarks, company_name) {
  data$Group <- company_name
  new_data <- rbind(data, benchmarks)
  new_data$Group <- factor(new_data$Group, levels = c(company_name, "Benchmark"))
  return(new_data)
}


#General graph functions for title and saving
graph_title <- function(title) {
  ggplot() +
    ggtitle(title) +
    geom_point() +
    theme_void() +
    theme(plot.title = element_text(size = 20, hjust = .5, vjust = -0.5))
}

graph_xlab <- function(xlab) {
  ggplot() +
  ggtitle(xlab) +
  geom_point() +
  theme_void() +
  theme(plot.title = element_text(size = 15, hjust = 0.5, vjust = -0.5))
}

generate_graph <- function(title, graph_title, graph, graph_xlab, width = 1000, height = 693, res = 120) {
  png(paste(title, ".png", sep = ""), width = width, height = height, res = res)
  grid.arrange(
    graph_title, graph, graph_xlab,
    ncol = 1, heights = c(1/10, 8/10, 1/10)
  )
  dev.off()
}

#Converts demographic data into percentages and coordinates for pie graphs
get_pie_data <- function(data, group, threshold = 0.1) {
  pie_graph_data <- data %>%
    filter(!is.na(group), group != "") %>%
    group_by_at(group) %>%
    summarise(count = n_distinct(User_ID)) %>%
    ungroup() %>% 
    mutate(percent = count/sum(count),
           cs = rev(cumsum(rev(percent))),
           ypos = percent/2 + lead(cs, 1),
           ypos = 1 - ifelse(is.na(ypos), percent/2, ypos),
           xpos = ifelse(percent > threshold, 1.7, 1.3),
           xn = ifelse(percent > threshold, 0, 0.5))
  pie_graph_data[,1] <- forcats::fct_rev(pull(pie_graph_data, group))
  return(pie_graph_data)
}

#Creates the pie_graph image (exported by generate_pie_graph)
get_pie_graph <- function(data, group, num_fill, threshold = 0.1) {
  ggplot(data, aes_string(x = 1, y = "percent", fill = group)) +
    geom_bar(width = 1 , stat = "identity", colour = "black") +
    coord_polar("y" , start = 0, clip = "off") + 
    theme_minimal() +
    theme(axis.text.x = element_blank(),
          axis.title.x = element_blank(),
          axis.text.y = element_blank(),
          axis.title.y = element_blank(),
          panel.border = element_blank(),
          panel.grid = element_blank(),
          legend.title = element_text(size = 22.5),
          legend.text = element_text(size = 19.5),
          legend.box.margin = margin(c(0,0,0,30))) +
    labs(fill = group) +
    guides(fill = guide_legend(reverse = TRUE)) +
    scale_fill_manual(values = rev(num_colours(num_fill))) +
    geom_segment(aes(x = ifelse(percent<threshold,1, xpos), xend = xpos, y = ypos, yend = ypos)) + 
    geom_text(aes(x = xpos, y = ypos, label = ifelse(percent>threshold,percent(percent, accuracy = 0.1),"")), hjust = "outward", nudge_x  = -0.15, size = 7.5) + 
    geom_text_repel(aes(x = xpos, y = ypos, label = ifelse(percent<threshold, percent(percent, accuracy = 0.1), "")), nudge_x  = 0.5, size = 7.5)
}

#Like generate_graph but doesn't need xlab
generate_pie_graph <- function(file_name, title, graph, width = 1300, height = 1000, res = 120) {
  png(paste(file_name, ".png", sep = ""), width = width, height = height, res = res)
  grid.arrange(
    title, graph,
    ncol = 1, heights = c(1/10, 8/10, 1/10)
  )
  dev.off()
}

#Graphs
#Severity graph
get_severity_graph <- function(data, fill, num_groups) {
  return(ggplot(data, aes_string(y = "Average", x = "Question.Text", fill = fill)) +
           geom_bar(stat = "identity", position = "dodge", width = 0.8) +
           theme_minimal() +
           theme(axis.text.x = element_text(size = 11.5), 
                 axis.text.y = element_text(size = 11.5),
                 axis.title.x = element_blank(),
                 axis.title.y = element_blank(),
                 legend.title = element_text(size = 14),
                 legend.text = element_text(size = 11.5)) +
           ylab("Severity") +
           labs(fill = fill) +
           #geom_text(aes(label = round(Average, 2), vjust = -0.5), size = 3.25) +
           scale_y_continuous(breaks = c(0:4), labels = c("Low severity", rep("", 3), "High severity")) +
           coord_cartesian(ylim = c(0.15,4)) +
           scale_fill_manual(values = num_colours(num_groups)))
}

#Psych symptoms graph
get_psych_symptoms_graph <- function(data, fill, num_groups, labels = FALSE) {
  graph <- ggplot(data, aes_string(x = "component", y = "Percent", fill = fill)) +
    geom_bar(stat = "identity", position = "dodge") +
    theme_minimal() +
    theme(axis.text.x = element_text(size = 11.5, angle = 45, hjust = 1), 
          axis.text.y = element_text(size = 11.5),
          axis.title.x = element_blank(),
          axis.title.y = element_text(size = 15, margin = margin(t = 0, r = 10, b = 0, l = 0)),
          legend.title = element_text(size= 14),
          legend.text = element_text(size = 11.5)) +
    ylab("Percent of Employees") +
    labs(fill = fill) +
    scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
    scale_fill_manual(values = num_colours(num_groups)) +
    scale_x_discrete(labels = c("Anxiety", "Low Mood", "Stress", "Addiction"))
  if (labels) {
    graph <- graph + 
      geom_text(aes(label = percent(Percent, accuracy = 0.1), vjust = -0.5), position = position_dodge(width = 1), size = 3.25)
  }
  return(graph)
}

get_workplace_graph <- function(data, fill, num_groups, labels = FALSE) {
  graph <- ggplot(data, aes_string(x = "component", y = "Percent", fill = fill)) +
    geom_bar(stat = "identity", position = "dodge") +
    theme_minimal() +
    theme(axis.text.x = element_text(size = 13, angle = 45, hjust = 1), 
          axis.text.y = element_text(size = 13),
          axis.title.x = element_blank(),
          axis.title.y = element_text(size = 15, margin = margin(t = 0, r = 10, b = 0, l = 0))) +
    ylab("Percent Score") +
    scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
    scale_fill_manual(values = num_colours(num_groups))
  if (labels) {
    graph <- graph + 
      geom_text(aes(label = percent(Percent, accuracy = 1), vjust = -0.5), position = position_dodge(width = 1), size = 3.25)
  }
  return(graph)
}
