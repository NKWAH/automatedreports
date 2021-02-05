#import relevant modules
setwd("~/Documents/InkBlot Therapy/Analytics/Assess/")
source("assess_functions.R")

#Benchmark
#Loads in benchmark data from all companies
date = "2021-01-13"
folder = paste("~/Documents/InkBlot Therapy/Analytics/Assess/Benchmarks/", date, sep = "")
setwd(folder)
bm_ors <- read.csv("bm_ors.csv")
bm_psych <- read.csv("bm_psych.csv")
bm_workplace <- read.csv("bm_workplace.csv")
bm_ors$Group <- "Benchmark"
bm_psych$Group <- "Benchmark"
bm_workplace$Group <- "Benchmark"

#Change folder and load the company's data
company = "Fully Managed"
start = "2020-12-15"
end = "2021-01-15"
folder = paste("~/Documents/InkBlot Therapy/Analytics/Assess/", company, "/", start, " - ", end, sep = "")
setwd(folder)
demographics <- read.csv("AssessDemographics.csv", stringsAsFactors = FALSE, strip.white = TRUE)
scores <- read.csv("AssessResponses.csv", stringsAsFactors = FALSE, strip.white = TRUE)

#Converts the roles from the database to a nicer form for the report
#Most companies have the roles as listed as below, but occasionally companies label the, in a custom way
library(Hmisc)
unique(demographics$Role)
role_names = c("Employee", "Middle Management", "Manager", "Executive Management")
demographics <- demographics %>%
  mutate(Role = case_when(Role == "employee_memeber" ~ role_names[1], 
                          Role == "manager" ~ role_names[2],
                          Role == "middle_management" ~ role_names[3],
                          Role == "executive_management" ~ role_names[4],
                          TRUE ~ ""))
demographics$Role[demographics$Role == ""] <- NA
demographics$Role <- factor(demographics$Role, levels = role_names)

#Convert DOB to Age
demographics$DOB <- as.Date(substr(demographics$DOB, 1, 10), format = "%Y-%m-%d") #Proper date format
demographics$Age <- NA
today <- Sys.Date()
for (i in 1:nrow(demographics)) {
  demographics$Age[i] <- age_na(demographics$DOB[i])
}

#Gender
demographics$Gender <- capitalize(demographics$Gender)
demographics$Gender[demographics$Gender == ""] <- NA
binary_gender <- c("Male", "Female")
#If there are too many groupings, can lump them into "Unspecified" or "Non-Binary." In general requires manual annotation
#demographics$Gender[!demographics$Gender %in% c("Male", "Female") & !is.na(demographics$Gender)] <- "Unspecified"
non_binary_genders <- sort(unique(demographics$Gender[!demographics$Gender %in% binary_gender & !is.na(demographics$Gender)])) #Finds genders  other than Male and Female
gender_factors <- c(binary_gender, non_binary_genders)
demographics$Gender <- factor(demographics$Gender, levels = gender_factors)

#Age
#Puts Age into buckets
demographics$Age <- cut(demographics$Age, breaks = c(0, 19, 29, 39, 49, 59, 69, 79, 999))
levels(demographics$Age) <- c("0 - 19", "20 - 29", "30 - 39", "40 - 49", "50 - 59", "60 - 69", "70 - 79", "80+")

#Generation
#Groups employees into generations by their DOB
demographics$Generation <- cut(as.numeric(substr(demographics$DOB, 1, 4)), breaks = c(0, 1945, 1965, 1980, 1995, 2015), right = FALSE)
levels(demographics$Generation) <- c("Silent", "Baby Boomer", "Gen X", "Millennials", "Gen Z")
#re-ordering the factors
num_factors <- length(levels(demographics$Generation))
demographics$Generation <- factor(demographics$Generation, levels = levels(demographics$Generation)[num_factors:1])

#Rescore questions based on negative or positive direction
#Also categorize question types
positive <- c(1, 2, 3, 4, 13, 14, 15, 16, 17, 19, 20, 21)
#ORS
ors_id <- c(1,2,3,4)
#Psych
stress <- c(9,10)
anxiety <- c(7,8)
depression <- c(5,6)
substance <- c(11)
psych <- c(stress, anxiety, depression, substance)
#Workplace
engagement <- c(13,14)
conflict_safety <- c(23,24)
satisfaction <- c(22)
environment <- c(17)
values <- c(16,19)
security <- c(18)
leadership <- c(20)
organization <- c(15,21)
workload <- c(12)
workplace <- c(engagement, conflict_safety, satisfaction, environment, values, security, leadership, organization, workload)
scores <- scores %>%
  mutate(type = case_when(Question.ID <= 4 ~ "ors", Question.ID >= 5 ~ "assess")) %>%
  mutate(direction = case_when(Question.ID %in% positive ~ "positive", !Question.ID %in% positive ~ "negative")) %>%
  mutate(Normalized = case_when(direction == "negative" & type == "assess" ~ (3 - as.numeric(Value)), TRUE ~ as.numeric(Value))) %>% #normalize values so higher is positive
  mutate(ors_flip = case_when(Question.ID < 5 ~ 5 - Normalized, TRUE ~ 0)) %>% #ORS is exception - higher value = higher severity
  mutate(component = case_when(Question.ID %in% ors_id ~ "ORS",
                               Question.ID %in% stress ~ "Stress",
                               Question.ID %in% anxiety ~ "Anxiety",
                               Question.ID %in% depression ~ "Depression",
                               Question.ID %in% substance ~ "Substance Abuse",
                               Question.ID %in% engagement ~ "Engagement",
                               Question.ID %in% conflict_safety ~ "Safety",
                               Question.ID %in% satisfaction ~ "Satisfaction",
                               Question.ID %in% environment ~ "Environment",
                               Question.ID %in% values ~ "Values",
                               Question.ID %in% security ~ "Security",
                               Question.ID %in% leadership ~ "Leadership",
                               Question.ID %in% organization ~ "Organization",
                               Question.ID %in% workload ~ "Acceptable Workload")) %>% #Individual domains within the three main evaluations
  mutate(category = case_when(
    Question.ID %in% workplace ~ "Workplace", 
    Question.ID %in% psych ~ "Psychological", 
    Question.ID %in% ors_id ~ "ORS")) #Broad categories of the three main evaluations

#Merge scores with demographic info
scores <- merge(scores, demographics)

#In situations where there are too few of any given demographic group, we omit them
min_employees = 4
real_age <- levels(scores$Age)[table(scores$Age)/24 >= min_employees]
real_gen <- levels(scores$Generation)[table(scores$Generation)/24 >= min_employees]
real_gender <- levels(scores$Gender)[table(scores$Gender)/24 >= min_employees]
real_country <- levels(scores$Country)[table(scores$Country)/24 >= min_employees]
#Special one for Role. If any of the three management group are too small, we can group them into one general "Manager" role
role_count <- table(scores$Role)/24
if (any(role_count[2:4] < 4)) {
  scores <- scores %>%
    mutate(Role = factor(case_when(Role == "Employee" ~ "Employee", 
                                   Role == "Executive Management" ~ "Manager",
                                   Role == "Middle Management" ~ "Manager",
                                   Role == "Manager" ~ "Manager",
                                   TRUE ~ ""), levels = c("Employee", "Manager")))
}
real_role <- levels(scores$Role)[table(scores$Role)/24 >= min_employees]

#Creating data sets that omit the groups that don't have enough employees
gen_trunc_scores <- scores %>%
  filter(Generation %in% real_gen)
gen_trunc_scores$Generation <- factor(gen_trunc_scores$Generation, levels = real_gen)
age_trunc_scores <- scores %>%
  filter(Age %in% real_age)
age_trunc_scores$Age <- factor(age_trunc_scores$Age, levels = real_age)
role_trunc_scores <- scores %>%
  filter(Role %in% real_role)
role_trunc_scores$Role <- factor(role_trunc_scores$Role, levels = real_role)
gender_trunc_scores <- scores %>%
  filter(Gender %in% real_gender)
gender_trunc_scores$Gender <- factor(gender_trunc_scores$Gender, levels = real_gender)

#Number of unique factors for each demographic. Later fed into a function that decides which colours to use for graphs.
score_ages <- length(na.omit(unique(scores$Age)))
score_generations <- length(na.omit(unique(scores$Generation)))
score_roles <- length(na.omit(unique(scores$Role)))
score_genders <- length(na.omit(unique(scores$Gender)))
score_country <- length(na.omit(unique(scores$Country)))

#Number of unique factors for each demographic for the truncated datasets
trunc_score_ages <- length(unique(age_trunc_scores$Age))
trunc_score_generations <- length(unique(gen_trunc_scores$Generation))
trunc_score_roles <- length(unique(role_trunc_scores$Role))
trunc_score_genders <- length(unique(gender_trunc_scores$Gender))
trunc_score_country <- length(unique(country_trunc_scores$Country))

#Start of graphs
#Respondents Gender Breakdown
gender <- get_pie_data(scores, "Gender")
gender_title <- graph_title("Respondent Gender Breakdown")
gender_graph <- get_pie_graph(gender, "Gender", score_genders)
generate_pie_graph("Respondent Gender Breakdown", gender_title, gender_graph)

#Respondent Age Breakdown
age <- get_pie_data(scores, "Age")
age_title <- graph_title("Respondent Age Breakdown")
age_graph <- get_pie_graph(age, "Age", score_ages)
generate_pie_graph("Respondent Age Breakdown", age_title, age_graph)

#Respondent Generation Breakdown
gen <- get_pie_data(scores, "Generation")
gen_title <- graph_title("Respondent Generation Breakdown")
gen_graph <- get_pie_graph(gen, "Generation", score_generations)
generate_pie_graph("Respondent Generation Breakdown2", gen_title, gen_graph)

#ORS
#Severity - Isn't graphed but briefly reported on
ors_severity <- scores %>%
  group_by(User_ID) %>%
  filter(Question.ID < 5) %>%
  summarise(Average = mean(ors_flip)) %>%
  mutate(severity = case_when(Average <= 1 ~ "mild", Average > 1 & Average <= 2 ~ "moderate", Average > 2 ~ "severe")) %>%
  group_by(severity) %>%
  summarise(Count = n()) %>%
  ungroup() %>%
  mutate(Percent = Count/sum(Count))
ors_xlab <- graph_xlab("Mental Health Domain")

#ORS - Benchmark
ors <- get_ors(scores, c())
new_ors <- add_bm(ors, bm_ors, company)
ors_title <- graph_title("Mental Health Difficulty Severity Score")
ors_graph <- get_severity_graph(new_ors, "Group", 2)
generate_graph("Mental Health Difficulty Severity Score.png", ors_title, ors_graph, ors_xlab)
#ORS - Age
ors_age <- get_ors(age_trunc_scores, "Age")
ors_age_title <- graph_title("Average Severity by Age")
ors_age_graph <- get_severity_graph(ors_age, "Age", trunc_score_ages)
generate_graph("Average Severity by Age", ors_age_title, ors_age_graph, ors_xlab)
#ORS - Generation
ors_gen <- get_ors(gen_trunc_scores, "Generation")
ors_gen_title <- graph_title("Average Severity by Generation")
ors_gen_graph <- get_severity_graph(ors_gen, "Generation", trunc_score_generations)
generate_graph("Average Severity by Generation", ors_gen_title, ors_gen_graph, ors_xlab)
#ORS - Role
ors_role <- get_ors(role_trunc_scores, "Role")
ors_role_title <- graph_title("Average Severity by Role")
ors_role_graph <- get_severity_graph(ors_role, "Role", trunc_score_roles)
generate_graph("Average Severity by Role", ors_role_title, ors_role_graph, ors_xlab)

#Psychological - anyone who experiences some symptoms
psych_symptoms_xlab <- graph_xlab("Mental Health Symptom")
#Psych - Benchmarks
psych_symptoms <- get_psych_symptoms(scores, c())
new_psych_symptoms <- add_bm(psych_symptoms, bm_psych, company)
psych_symptoms_title <- graph_title("Mental Health Symptom Breakdown")
psych_symptoms_graph <- get_psych_symptoms_graph(new_psych, "Group", 2, TRUE)
generate_graph("Mental Health Symptom Breakdown", psych_symptoms_title, psych_symptoms_graph, psych_symptoms_xlab)
#Psychological by Age - anyone who experiences some symptoms
psych_symptoms_age <- get_psych_symptoms(age_trunc_scores, "Age")
psych_symptoms_age_title <- graph_title("Employee Mental Health by Age")
psych_symptoms_age_graph <- get_psych_symptoms_graph(psych_symptoms_age, "Age", trunc_score_ages)
generate_graph("Employee Mental Health by Age", psych_symptoms_age_title, psych_symptoms_age_graph, psych_symptoms_xlab)
#Psychological by Generation - anyone who experiences some symptoms
psych_symptoms_gen <- get_psych_symptoms(gen_trunc_scores, "Generation")
psych_symptoms_gen_title <- graph_title("Employee Mental Health by Generation")
psych_symptoms_gen_graph <- get_psych_symptoms_graph(psych_symptoms_gen, "Generation", trunc_score_generations)
generate_graph("Employee Mental Health by Generation", psych_symptoms_gen_title, psych_symptoms_gen_graph, psych_symptoms_xlab)
#Psychological by Role - anyone who experiences some symptoms
psych_symptoms_role <- get_psych_symptoms(role_trunc_scores, "Role")
psych_symptoms_role_title <- graph_title("Employee Mental Health by Role")
psych_symptoms_role_graph <- get_psych_symptoms_graph(psych_symptoms_role, "Role", trunc_score_roles)
generate_graph("Employee Mental Health by Role", psych_symptoms_role_title, psych_symptoms_role_graph, psych_symptoms_xlab)

#Workplace
workplace_xlab <- graph_xlab("Workplace Mental Health Component")
#Workplace - Benchmarks
workplace <- get_workplace(scores, c())
new_workplace <- add_bm(workplace, bm_workplace, company)
workplace_title <- graph_title("Workplace Mental Health")
workplace_graph <- get_workplace_graph(new_workplace, "Group", 2, TRUE)
generate_graph("Workplace Mental Health", workplace_title, workplace_graph, workplace_xlab)
#Workplace - Age
workplace_age <- get_workplace(age_trunc_scores, "Age")
workplace_age_title <- graph_title("Workplace Mental Health by Age")
workplace_age_graph <- get_workplace_graph(workplace_age, "Age", trunc_score_ages)
generate_graph("Workplace Mental Health by Age", workplace_age_title, workplace_age_graph, workplace_xlab)
#Workplace - Generation
workplace_gen <- get_workplace(gen_trunc_scores, "Generation")
workplace_gen_title <- graph_title("Workplace Mental Health by Generation")
workplace_gen_graph <- get_workplace_graph(workplace_gen, "Generation", trunc_score_generations)
generate_graph("Workplace Mental Health by Generation", workplace_gen_title, workplace_gen_graph, workplace_xlab)
#Workplace - Role
workplace_role <- get_workplace(role_trunc_scores, "Role")
workplace_role_title <- graph_title("Workplace Mental Health by Role")
workplace_role_graph <- get_workplace_graph(workplace_role, "Role", trunc_score_roles)
generate_graph("Workplace Mental Health by Role", workplace_role_title, workplace_role_graph, workplace_xlab)

#This portion isn't run to generate graph, I run it in-session line-by-line to see the differences between groups and fill out the document based on this
#{1=>0, 2=>1, 3=>4, 4=>11, 5=>3, nil=>14}
#December
if (FALSE) {
  #Completion
  (nrow(scores)/24)
  (nrow(scores)/24)/active_in_period
  
  #General severity
  average_severity = as.numeric(new_ors[5,3])
  new_ors %>% 
    filter(Group != "Benchmark") %>% 
    mutate(AboveHalf = case_when(Average >= 2 ~ 1, Average < 2 ~ 0, TRUE ~ -1),
           ComparedToAverage = (Average - average_severity)/average_severity * 100)
  ors_severity
  #Largest differences between Benchmark, including Average
  #Refer to this thread to fix https://stackoverflow.com/questions/49536016/dplyr-subtracting-values-group-wise-by-group-that-matches-given-condition/49536524?noredirect=1#comment110821460_49536524
  ors_diff <- new_ors %>% 
    group_by(Group) %>% mutate(
      diff = Average -  .[.$Group == 'Benchmark', 'Average'],
      diff_percent = 100 * diff/.[.$Group == 'Benchmark', 'Average']) %>% 
    arrange(diff)
  ors_diff
  #Largest differences in grouped severity
  ors_age %>% 
    group_by(Age) %>% 
    summarise(Mean = mean(Average)) %>% 
    mutate(PercentDiff = 100 * (Mean - min(Mean))/min(Mean))
  ors_generation %>% 
    group_by(Generation) %>% 
    summarise(Mean = mean(Average)) %>% 
    mutate(PercentDiff = 100 * (Mean - min(Mean))/min(Mean))
  ors_role %>% 
    group_by(Role) %>% 
    summarise(Mean = mean(Average)) %>% 
    mutate(PercentDiff = 100 * (Mean - min(Mean))/min(Mean))
  
  ors_group = "Role"
  if (ors_group == "Age") {
    ors_group_stats <- ors_age %>% 
      group_by(Question.Text) %>% 
      mutate(diff = max(Average) - min(Average)) %>% 
      arrange(diff)
  } else if (ors_group == "Generation") {
    ors_group_stats <- ors_generation %>% 
      group_by(Question.Text) %>% 
      mutate(diff = max(Average) - min(Average)) %>% 
      arrange(diff)
  } else if (ors_group == "Role") {
    ors_group_stats <- ors_role %>% 
      group_by(Question.Text) %>% 
      mutate(diff = max(Average) - min(Average)) %>% 
      arrange(diff)
  } else {
    print("Doesn't exist")
  }
  ors_group_stats %>% mutate(percent_diff = diff/min(Average))
  
  new_psych %>% 
    filter(Group != "Benchmark") %>% 
    mutate(AboveHalf = case_when(Percent >= 0.5 ~ 1, Percent < 0.5 ~ 0))
  new_psych %>% 
    group_by(Group) %>% 
    summarise(Mean = mean(Percent)) %>% 
    mutate(diff = (max(Mean) - min(Mean)) * 100)
  psych_diff <- new_psych %>% 
    group_by(Group) %>% mutate(
      diff = Percent -  .[.$Group == 'Benchmark', 'Percent'],
      diff_percent = diff/.[.$Group == 'Benchmark', 'Percent']) %>% 
    arrange(diff)
  psych_diff
  #Largest differences in percentages of employees reporting psychological symptoms
  psych_age_symptoms %>% 
    group_by(Age) %>% 
    summarise(Mean = mean(Percent)) %>% 
    mutate(diff = (max(Mean) - min(Mean)) * 100)
  psych_generation_symptoms %>% 
    group_by(Generation) %>% 
    summarise(Mean = mean(Percent)) %>% 
    mutate(diff = (max(Mean) - min(Mean)) * 100)
  psych_role_symptoms %>% 
    group_by(Role) %>% 
    summarise(Mean = mean(Percent)) %>% 
    mutate(diff = (max(Mean) - min(Mean)) * 100)
  psych_group = "Role"
  if (psych_group == "Age") {
    psych_group_stats <- psych_age_symptoms %>% 
      group_by(component) %>% 
      mutate(diff = max(Percent) - min(Percent)) %>% 
      arrange(diff)
  } else if (psych_group == "Generation") {
    psych_group_stats <- psych_generation_symptoms %>% 
      group_by(component) %>% 
      mutate(diff = max(Percent) - min(Percent)) %>% 
      arrange(diff)
  } else if (psych_group == "Role") {
    psych_group_stats <- psych_role_symptoms %>% 
      group_by(component) %>% 
      mutate(diff = max(Percent) - min(Percent)) %>% 
      arrange(diff)
  } else {
    print("Doesn't exist")
  }
  psych_group_stats
  
  new_workplace %>% 
    filter(Group != "Benchmark") %>% 
    mutate(AboveHalf = case_when(Average >= 0.5 ~ 1, Average < 0.5 ~ 0, TRUE ~ -1)) %>% 
    arrange(Average)
  new_workplace %>% 
    group_by(Group) %>% 
    summarise(Mean = mean(Average)) %>% 
    mutate(diff = (max(Mean) - min(Mean)) * 100)
  workplace_diff <- new_workplace %>% 
    group_by(Group) %>% mutate(
      diff = Average -  .[.$Group == 'Benchmark', 'Average'],
      diff_percent = diff/.[.$Group == 'Benchmark', 'Average']) %>% 
    arrange(diff)
  workplace_diff
  #Largest differences in grouped severity
  workplace_age_stats %>% 
    group_by(Age) %>% 
    summarise(Mean = mean(Percent)) %>% 
    mutate(diff = (max(Mean) - min(Mean)) * 100)
  workplace_generation_stats %>% 
    group_by(Generation) %>% 
    summarise(Mean = mean(Percent)) %>% 
    mutate(diff = (max(Mean) - min(Mean)) * 100)
  workplace_role_stats %>% 
    group_by(Role) %>% 
    summarise(Mean = mean(Percent)) %>% 
    mutate(diff = (max(Mean) - min(Mean)) * 100)
  workplace_group = "Role"
  if (workplace_group == "Age") {
    workplace_group_stats <- workplace_age_stats %>% group_by(component) %>% mutate(diff = max(Percent) - min(Percent)) %>% arrange(desc(diff))
  } else if (workplace_group == "Generation") {
    workplace_group_stats <- workplace_generation_stats %>% group_by(component) %>% mutate(diff = max(Percent) - min(Percent)) %>% arrange(desc(diff))
  } else if (workplace_group == "Role") {
    workplace_group_stats <- workplace_role_stats %>% group_by(component) %>% mutate(diff = max(Percent) - min(Percent)) %>% arrange(desc(diff))
  } else {
    print("Doesn't exist")
  }
  workplace_group_stats
}

