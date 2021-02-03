load "nick_reporting/test_data.rb"
load "nick_reporting/pc_reports/pc_dashboard_methods.rb"
load "nick_reporting/session_questionnaires.rb"
load "nick_reporting/company_users.rb"

#ARGV = ["2021-01-01", "2021-01-31", "MNP LLP"]

start = ARGV[0].to_date.beginning_of_day
stop = ARGV[1].to_date.end_of_day
company_id =    Company.
                where.not(suspended_yn: true).
                find_by_name(ARGV[2]).
                id

total_onboarded =   Company.
                    find(company_id).
                    user_companies.
                    where("user_companies.created_at < ?", stop).
                    where.not(deleted_yn: true, user_id: @test).
                    distinct.
                    pluck(:user_id)

all_completed_sessions =    Appointment.
                            completed.
                            joins(:users).
                            where(
                                client_covered_yn: true,
                                users: {id: total_onboarded}).
                            where("start_date BETWEEN ? AND ?", start, stop).
                            where.not(id: @testapp).
                            distinct.
                            pluck(:id)
all_late_cancel_sessions =  Cancellation.
                            joins(:appointment).
                            where(
                                user_id: total_onboarded,
                                appointments: {client_covered_yn: true}).
                            where("EXTRACT (EPOCH FROM start_date - cancellations.created_at) < 43200").
                            where("start_date BETWEEN ? AND ?", start, stop).
                            where.not(appointment_id: @testapp).
                            distinct.
                            pluck(:appointment_id)         
all_absent_counselling_sessions =   AppointmentAbsence.
                                    joins(:appointment).
                                    where(
                                        user_id: total_onboarded,
                                        appointments: {client_covered_yn: true}).
                                    where("start_date BETWEEN ? AND ?", start, stop).  
                                    where.not(appointment_id: @testapp).
                                    distinct.
                                    pluck(:appointment_id)
all_sessions = all_completed_sessions + all_late_cancel_sessions + all_absent_counselling_sessions
first_range_access_users =  Appointment.
                            joins(:users).
                            where(
                                id: all_sessions,
                                users: {id: total_onboarded}
                                ).
                            group("users.id").
                            pluck("users.id", "MIN(start_date)").to_h

#Number of employees registering/logging in for first time
#Only works post sign-in tracking, August 29, 2019
#Missed some email-link related ones before October 14, 2020
first_auth_log_sigin = AuthLog.where(type_of: "sign_in").order(:created_at).first.created_at
first_auth_log_signup = AuthLog.where(type_of: "sign_up").order(:created_at).first.created_at

imported = ["marchel", "import", "assess"]
all_auth_users =    AuthLog.
                    where(user_id: total_onboarded).
                    distinct.
                    pluck(:user_id)

#cumulative registrations
sign_ups =  User.
            where.not(source: imported).
            where(id: total_onboarded).
            where("created_at <= ?", stop).
            distinct.
            pluck(:id)
import_logins = AuthLog.
                joins(:user).
                where(user_id: total_onboarded, result: "success", users: {source: imported}, deleted_yn: false).
                group(:user_id).
                having("MIN(auth_logs.created_at) <= ?",  stop).
                distinct.
                pluck(:user_id)
#For users created before proper tracking, if they don't have an AuthLog record, we'll assume they registered at their created_at date
#I think this is overall best, but we may inaccurately move some people to a later registration date if they sign in later
pre_sign_up_tracking =  User.
                        where(id: total_onboarded, source: imported, password_change_yn: false).
                        where.not(id: all_auth_users).
                        where("created_at < ?", first_auth_log_signup).
                        where("created_at <= ?", stop).
                        distinct.
                        pluck(:id)

cumulative_registrations = sign_ups + import_logins + pre_sign_up_tracking

#new registrations
sign_ups =  User.
            where.not(source: imported).
            where(id: total_onboarded).
            where("created_at BETWEEN ? AND ?", start, stop).
            distinct.
            pluck(:id)
import_logins = AuthLog.
                joins(:user).
                where(user_id: total_onboarded, result: "success", users: {source: imported}, deleted_yn: false).
                group(:user_id).
                having("MIN(auth_logs.created_at) BETWEEN ? AND ?", start, stop).
                distinct.
                pluck(:user_id)
#For users created before proper tracking, if they don't have an AuthLog record, we'll assume they registered at their created_at date
#I think this is overall best, but we may inaccurately move some people to a later registration date if they sign in later
pre_sign_up_tracking =  User.
                        where(id: total_onboarded, source: imported, password_change_yn: false).
                        where.not(id: all_auth_users).
                        where("created_at < ?", first_auth_log_signup).
                        where("created_at <= ?", stop).
                        distinct.
                        pluck(:id)

new_registrations = sign_ups + import_logins + pre_sign_up_tracking

#Population
pop_id =    CompanyPopulation.
            where(company_id: company_id, deleted_yn: false).
            where("start_date < ?", stop).
            order(start_date: :desc).
            first&.
            id
if pop_id.nil?
    pop_id =    CompanyPopulation.
                where(company_id: company_id, deleted_yn: false).
                where("start_date >= ?", stop).
                order(:start_date).
                first&.
                id
end
if pop_id.nil?
    population = company_users(stop.beginning_of_day, stop, ARGV[2]).size.to_f
    pop_warning = nil
else
    population = CompanyPopulation.find(pop_id).population
    pop_date = CompanyPopulation.find(pop_id).start_date.beginning_of_day
    pop_warning = nil
    if (pop_date + 1.months < stop) | (pop_date >= stop)
        pop_warning = "Current month's population was not used"
    end
end

#Utilization Rate
#calculating full years that passed
year_diff = stop.year - start.year
year_diff = ((start + year_diff.years) > stop) ? (year_diff - 1) : year_diff
#calculating fraction of final year that has passed based on number of seconds between the start date and one year after the start date
#this accounts for leap years and even leap SECONDS
final_year_start = start + year_diff.years
final_year_as_seconds = final_year_start + 1.years - final_year_start
full_day_stop = (stop + 1.days).beginning_of_day #Something about the way ruby stores dates doesn't work properly if you only add 1 second
final_year_add = (full_day_stop - start) / final_year_as_seconds
report_duration = year_diff + final_year_add
utilization_rate = "#{(cumulative_registrations.size * 100.0 / population / report_duration).round(2)}%"

#Account Types
zero_account_types = {"Employee/Member" => 0, "Spouse" => 0, "Dependent" => 0, "People Leader" => 0}
#Cumulative
cumulative_account_types = PeopleCareDetail.
                joins(:people_care_status).
                where(user_id: cumulative_registrations, deleted_yn: false).
                group("people_care_statuses.status").
                count
employee_add = cumulative_registrations.size - cumulative_account_types.values.sum
cumulative_account_types = zero_account_types.merge(cumulative_account_types) {|key, oldval, newval| newval}
cumulative_account_types["Employee/Member"] += employee_add

#Number using knowledge base
virtual_counselling_articles = ["Virtual counselling after interim report", "Virtual counselling after final report", "Virtual counselling from /virtual_counselling"]
kb =    UserClick.
        where(user_id: total_onboarded).
        where.not(article_name: virtual_counselling_articles).
        where("user_clicks.created_at BETWEEN ? AND ?", start, stop).
        distinct.
        pluck(:user_id)

#kb Utilization
kb_utilization = "#{(kb.size * 100.0 / cumulative_registrations.size).round(2)}%"

#Numbers of users starting assessments
started_assessment_users =  PeopleAssessment.
                            where(user_id: total_onboarded).
                            where("people_assessments.created_at BETWEEN ? AND ?", start, stop).
                            distinct.
                            pluck(:user_id)

#Number of users completing assessments
new_finished_assessments =  PeopleAssessment.
                            where(user_id: total_onboarded).
                            where("interim_completed_at BETWEEN ? AND ? OR final_completed_at BETWEEN ? AND ?", start, stop, start, stop).
                            distinct.
                            pluck(:id)
old_finished_assessments =  PeopleAssessment.
                            where(
                                user_id: total_onboarded, 
                                completed_yn: true,
                                interim_completed_at: nil,
                                final_completed_at: nil).
                            where("updated_at BETWEEN ? AND ?", start, stop).
                            distinct.
                            pluck(:id)
finished_assessments = new_finished_assessments + old_finished_assessments
finished_assessment_users = PeopleAssessment.
                            where(id: finished_assessments).
                            distinct.
                            pluck(:user_id)

#Percent accessing virtual counselling after assessment
#Legacy - Before a certain date where tracking was properly implemented, we'll look at people completing the first matching question after coming from assessment
#There is some overlap depending on dates but for the most part I don't think there will be double counting so we're taking unique users
first_match_question_id = 19
first_match_answers = MatchQuestion.find(first_match_question_id).match_answers.pluck(:id)
#Account for those that took place before timestamps were implemented
first_continued = Match.where(continued_from_source_yn: true).order(:continued_from_source_at).first.continued_from_source_at
match_after_assessment =    UserAnswer.
                            joins(:match, [user: :people_assessments]).
                            where(  user_id: finished_assessment_users, 
                                    match_answer_id: first_match_answers,
                                    people_assessments: {completed_yn: true}).
                            where("matches.created_at < ?", first_continued).
                            where("user_answers.created_at BETWEEN ? AND ?", start, stop).
                            where("user_answers.created_at > people_assessments.updated_at OR user_answers.created_at > people_assessments.interim_completed_at OR user_answers.created_at > people_assessments.final_completed_at").
                            distinct.
                            pluck("users.id")
#continued from match
continued_match =   Match.
                    joins(users: :people_assessments).
                    where(source: ["people_care"], people_assessments: {id: finished_assessments}).
                    where("matches.continued_from_source_at BETWEEN ? AND ?", start, stop).
                    where("matches.continued_from_source_at > people_assessments.updated_at OR matches.continued_from_source_at > people_assessments.interim_completed_at OR matches.continued_from_source_at > people_assessments.final_completed_at").
                    distinct.
                    pluck("users.id")
new_match = Match.
            joins(users: [:people_assessments, :user_answers]).
            where(people_assessments: {id: finished_assessments}).
            where.not(source: ["people_care", "practice", "assess", nil]).
            where("matches.created_at BETWEEN ? AND ? OR user_answers.created_at BETWEEN ? AND ?", start, stop, start, stop).
            where("matches.created_at > people_assessments.updated_at OR matches.created_at > people_assessments.interim_completed_at OR matches.created_at > people_assessments.final_completed_at
            OR user_answers.created_at > people_assessments.updated_at OR user_answers.created_at > people_assessments.interim_completed_at OR user_answers.created_at > people_assessments.final_completed_at").
            distinct.
            pluck("users.id")
combined_matches = (match_after_assessment + continued_match + new_match).uniq
counselling_after_assessment = "#{(combined_matches.size.to_f/finished_assessment_users.size * 100).round(2)}%"

#Number who accessed counselling:
utilized_counselling =  Appointment.
                        joins(:users).
                        where(id: all_sessions, users: {id: total_onboarded}).
                        distinct.
                        pluck("users.id")

#Number of sessions completed
completed_sessions =    Appointment.
                        joins(:users).
                        where(users: {id: total_onboarded}, id: all_completed_sessions).
                        distinct.
                        pluck(:id)

#ORS
first_matches = get_first_match_hash(total_onboarded)
three_app_users = get_three_app_users(first_matches.keys, stop, true)
real_ors_asses = get_real_asses(stop, total_onboarded, "ors")
third_user_asses = get_third_valid_asses(total_onboarded, stop, real_ors_asses)
ors = get_ors(third_user_asses, first_matches, false)

#SRS
real_srs_asses = get_real_asses(stop, total_onboarded, "srs")
real_srs_users =    Assessment.
                    where(id: real_srs_asses).
                    distinct.
                    pluck(:user_id)
first = get_srs_by_assessments(real_srs_asses)
second = get_srs_by_user(real_srs_users, real_srs_asses, false)
srs = "#{((first + second[:srs]) * 10 /2).round(2)}%"

#Gender Breakdown
gender = get_quarter_gender(utilized_counselling).to_a.flatten.each_slice(3).to_a

#Age Breakdown
age = get_user_ages(stop, utilized_counselling).to_a.flatten.each_slice(3).to_a

workplace_stress_coding = {
        "High Workload": "work1",
        "Lack of Control": "work2",
        "Poor Management": "work6",
        "High Conflict": "work7",
        "Job Uncertainty": "work8",
        "Work-Life Balance": "work9",
        "Harassment": ["work10", "work11"],
        "Discrimination": ["work12", "work13"],
        "Not Appreciated": ["work4"],
        "Unfair Treatment": "work5",
        "Not Meaningful": "work3"
}
personal_stress_coding = {
        "Stress": {present_codes: nil, int_codes: ['dass3', 'dass7'], type: "both"},
        "Depression": {present_codes: ['dx1', 'dx4'], int_codes: ['dass1', 'dass5'], type: "both"},
        "Anxiety": {present_codes: 'dx2', int_codes: ['dass2', 'dass6'], type: "both"},
        "Grief & Loss":  {present_codes: 'stress4', int_codes: nil, type: "match"},
        "Loneliness":  {present_codes: 'stress1', int_codes: nil, type: "match"},
        "Personal": {present_codes: ['stress7', 'stress8', 'stress15', 'stress16'], int_codes: nil, type: "match"},
        "Substance Use": {present_codes: ['dx3'], int_codes: ['dass4'], type: "both"},
        "Trauma": {present_codes: 'dx10', int_codes: nil, type: "match"},
        "Abuse": {present_codes: 'stress9', int_codes: nil, type: "match"},
        "Marital/relationships": {present_codes: 'stress2', int_codes: nil, type: "match"},
        "Family": {present_codes: ['stress3', 'stress5'], int_codes: nil, type: "match"}, 
        "Health": {present_codes: ['stress6', 'stress17'], int_codes: nil, type: "match"},
        "Financial": {present_codes: 'stress10', int_codes: nil, type: "match"},
        "Legal": {present_codes: 'stress11', int_codes: nil, type: "match"},
        "Parenting": {present_codes: 'stress12', int_codes: nil, type: "match"}
}

#Personal Stressors
personal = generate_personal_stressors(utilized_counselling, personal_stress_coding, first_range_access_users)
personal = personal.sort_by {|k,v| [-v, k]}
min_count = personal[4][1]
personal = personal.select {|k,v| v >= [min_count, 1].max }

#Workplace Stressors
work = generate_workplace_stressors(utilized_counselling, workplace_stress_coding, first_range_access_users)
work = work.sort_by {|k,v| [-v, k]}
min_count = work[4][1]
work = work.select {|k,v| v >= [min_count, 1].max }

new_registrations.size
cumulative_registrations.size
population
utilization_rate
pp cumulative_account_types
kb.size
kb_utilization
started_assessment_users.size
finished_assessments.size
counselling_after_assessment
utilized_counselling.size
completed_sessions.size
pp gender
pp age
ors[:percent]
srs
pp personal
pp work

require "csv"
CSV.open("#{Rails.root.join('public/reports').to_s}/pc_client_dashboard.csv", 'w') do |writer|
    writer << ["Company Name", ARGV[2]]
    writer << ["Reporting Period", "#{start.year}-#{start.month}-#{start.day} - #{stop.year}-#{stop.month}-#{stop.day}"]
    writer << ["Number of new accounts created (reporting period)", new_registrations.size]
    writer << ["Number of accounts created (cumulative)", cumulative_registrations.size]
    writer << ["Population", population, pop_warning]
    writer << ["Utilization Rate (annualized)", utilization_rate]
    writer << ["Type of Account Created"]
    cumulative_account_types.to_a.each do |metric|
        writer << metric
    end
    writer << ["Number using knowledge base", kb.size]
    writer << ["Knowledge Base Utilization Rate", kb_utilization]
    writer << ["Number Starting Assessment", started_assessment_users.size]
    writer << ["Finished Assessments", finished_assessments.size]
    writer << ["Percent accessing virtual counselling after assessment", counselling_after_assessment]
    writer << ["Number who utilized counselling", utilized_counselling.size]
    writer << ["Number of sessions completed", completed_sessions.size]
    writer << ["Psychiatric consultations", 0]
    writer << ["Gender Breakdown"]
    gender.each do |metric|
        writer << metric
    end
    writer << ["Age Breakdown"]
    age.each do |metric|
        writer << metric
    end
    writer << ["Clinical symptom improvement score", ors[:percent]]
    writer << ["Client satisfaction score", srs]
    writer << ["Top 5 Personal Stressors"]
    personal.each do |metric|
        writer << metric
    end
    writer << ["Top 5 Workplace Stressors"]
    work.each do |metric|
        writer << metric
    end
end
