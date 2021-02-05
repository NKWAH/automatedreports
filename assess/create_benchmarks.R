company = "Benchmarks"
date = "2021-01-13"
folder = paste("~/Documents/InkBlot Therapy/Analytics/Assess/", company, "/", date, sep = "")
setwd(folder)
require(dplyr)

scores <- read.csv("AssessResponses.csv", stringsAsFactors = FALSE, strip.white = TRUE)

#Rescore questions based on negative or positive ask
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
  mutate(Normalized = case_when(direction == "negative" & type == "assess" ~ (3 - as.numeric(Value)), TRUE ~ as.numeric(Value))) %>%
  mutate(ors_flip = case_when(Question.ID < 5 ~ 5- Normalized, TRUE ~ 0)) %>%
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
                               Question.ID %in% workload ~ "Acceptable Workload")) %>%
  mutate(category = case_when(Question.ID %in% workplace ~ "Workplace", Question.ID %in% psych ~ "Psychological", Question.ID %in% ors_id ~ "ORS"))


#ORS
ors_components <- scores %>%
  group_by(Question.ID, Question.Text) %>%
  filter(Question.ID < 5) %>%
  summarise(Average = mean(ors_flip)) %>%
  arrange(Question.ID) %>%
  ungroup()

ors_average <- scores %>%
  filter(Question.ID < 5) %>%
  summarise(Average = mean(ors_flip)) 

ors_average$Question.ID <- 5
ors_average$Question.Text <- "Average"

ors <- rbind(ors_components, data.frame(Question.ID = 5, Question.Text = "Average", Average = ors_average$Average[1])) %>%
  mutate(Group = "Benchmark")
ors$Question.Text <- factor(ors$Question.Text, levels = c("Individual", "Interpersonal", "Social", "Overall", "Average"))

#Psych
psych_symptoms <- scores %>%
  filter(category == "Psychological") %>%
  filter(Normalized < 3) %>%
  group_by(component) %>%
  summarise(Percent = n_distinct(User_ID)/length(unique(scores$User_ID))) %>%
  arrange(component) %>%
  mutate(Group = "Benchmark")

#Workplace
workplace_stats <- scores %>%
  filter(category == "Workplace") %>%
  group_by(component) %>%
  mutate(Percent = Normalized/3) %>%
  summarise(Percent = mean(Percent)) %>%
  mutate(Group = "Benchmark")

write.csv(ors, "bm_ors.csv", row.names = FALSE)
write.csv(psych_symptoms, "bm_psych.csv", row.names = FALSE)
write.csv(workplace_stats, "bm_workplace.csv", row.names = FALSE)
