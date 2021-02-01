load "nick_reporting/test_data.rb"
load "nick_reporting/access_reports/access_report_methods.rb"
load "nick_reporting/company_users.rb"
load "nick_reporting/session_questionnaires.rb"

start = ARGV[0].to_date.beginning_of_day
if ARGV[6] == "stub"
    if start.day <= 15
        report_start = start.beginning_of_month
    else
        report_start = start.beginning_of_month + 1.months
    end
else
    report_start = start
end
@quarters = [
  {label: 1, min: start, max: (report_start + 3.months - 1.days).end_of_day},
  {label: 2, min: (report_start + 3.months).beginning_of_day, max: (report_start + 6.months - 1.days).end_of_day},
  {label: 3, min: (report_start + 6.months).beginning_of_day, max: (report_start + 9.months - 1.days).end_of_day},
  {label: 4, min: (report_start + 9.months).beginning_of_day, max: (report_start + 12.months - 1.days).end_of_day}
]
if ARGV[1] == "0"
    stop = @quarters[quarter - 1][:max]
else
    stop = ARGV[1].to_date.end_of_day
end
quarter = ARGV[2].to_i
id = Company.
      where.not(suspended_yn: true).
      find_by(name: ARGV[3]).
      id
contract_start = Company.find(id).contract_detail.contract_start.beginning_of_day
years_since_start = get_age(stop, contract_start)
if years_since_start > 0
    if contract_start.day <= 15
        contract_year_start = contract_start.beginning_of_month + years_since_start.years
    else
        contract_year_start = contract_start.beginning_of_month + 1.months + years_since_start.years
    end
else
    contract_year_start = contract_start
end

total_onboarded = Company.
                  find(id).
                  user_companies.
                  where.not(
                      deleted_yn: true,
                      user_id: @test).
                  distinct.
                  pluck(:user_id)

#1) Number of unique users accessing sessions
#Have to be "used up" - completed, late cancelled or absent
#We'll copy this for counsellors later
completed_sessions =    Appointment.
                        completed.
                        joins(:users).
                        where(
                            client_covered_yn: true,
                            users: {id: total_onboarded}).
                        where("start_date BETWEEN ? AND ?", contract_year_start, stop).
                        where.not(id: @testapp).
                        distinct.
                        pluck(:id)
late_cancel_sessions =  Cancellation.
                        joins(:appointment).
                        where(
                            user_id: total_onboarded,
                            appointments: {client_covered_yn: true}).
                        where("EXTRACT (EPOCH FROM start_date - cancellations.created_at) < 43200").
                        where("start_date BETWEEN ? AND ?", contract_year_start, stop).
                        where.not(appointment_id: @testapp).
                        distinct.
                        pluck(:appointment_id)         
absent_counselling_sessions =   AppointmentAbsence.
                                joins(:appointment).
                                where(
                                    user_id: total_onboarded,
                                    appointments: {client_covered_yn: true}).
                                    where("start_date BETWEEN ? AND ?", contract_year_start, stop).  
                                where.not(appointment_id: @testapp).
                                distinct.
                                pluck(:appointment_id)
all_sessions = completed_sessions + late_cancel_sessions + absent_counselling_sessions
first_range_access_users =  Appointment.
                            joins(:users).
                            where(
                                id: all_sessions,
                                users: {id: total_onboarded}
                                ).
                            group("users.id").
                            where("start_date BETWEEN ? AND ?", contract_year_start, stop).
                            having("MIN(start_date) BETWEEN ? AND ?", start, stop).
                            pluck("users.id", "MIN(start_date)").to_h
first_all_time_access_users =   Appointment.
                                joins(:users).
                                where(
                                    id: all_sessions,
                                    users: {id: total_onboarded}
                                    ).
                                where("start_date <= ?", stop).
                                group("users.id"). 
                                pluck("users.id", "MIN(start_date)").to_h

#Users accessing paid sessions
coverage_users =  CompanyUsedMinute.
            joins(:appointment).
            where.not(
                deleted_yn: true,
                appointment_id: @testapp).
            where(
                company_id: id,
                user_id: total_onboarded).
            group(:user_id).
            where("start_date BETWEEN ? AND ?", contract_year_start, stop).
            having("MIN(start_date) BETWEEN ? AND ?", start, stop).
            pluck(:user_id, "MIN(start_date)").to_h

sale_users =  Appointment.
        joins(:payments).
        where(
            client_covered_yn: true,
            payments: {
                user_id: total_onboarded, 
                payment_type: "sale",
                refund_id: nil}).
        where.not(
            id: @testapp,
            payments: {transaction_id: nil}).
        group(:user_id).
        where("start_date BETWEEN ? AND ?", contract_year_start, stop).
        having("MIN(start_date) BETWEEN ? AND ?", start, stop).
        pluck(:user_id, "MIN(start_date)").to_h

first_paid_users = coverage_users.merge(sale_users) {|key, oldval, newval| [newval, oldval].min}

quarter_users = [[], [], [], []]

first_range_access_users.each do |user, date|
    temp_quarter = get_quarter(date)
    if temp_quarter
        quarter_users[temp_quarter-1] << user
    end
end

quarter_users_count = []
for i in 0..3
    quarter_users_count << quarter_users[i].size
end
total_users_count = quarter_users_count.flatten.sum

quarter_paid_users = [[], [], [], []]

first_paid_users.each do |user, date|
    temp_quarter = get_quarter(date)
    if temp_quarter
        quarter_paid_users[temp_quarter-1] << user
    end
end
  
quarter_paid_users_count = []
for i in 0..3
    quarter_paid_users_count << quarter_paid_users[i].size
end
total_paid_users_count = quarter_paid_users_count.flatten.sum

workplace_stress_coding = {
        "High Workload": {assess_codes: "work_demand", direction: "negative", match_codes: "work1", type: "both"},
        "Lack of Control": {assess_codes: "work_influence", direction: "positive", match_codes: "work2", type: "both"},
        "Poor Management": {assess_codes: ["work_theytrust", "work_youtrust"], direction: "positive", match_codes: "work6", type: "both"},
        "High Conflict": {assess_codes: ["work_conflict", "work_relationship"], direction: "positive", match_codes: "work7", type: "both"},
        "Job Uncertainty": {assess_codes: "work_security", direction: "positive", match_codes: "work8", type: "both"},
        "Work-Life Balance": {assess_codes: "work_balance", direction: "negative", match_codes: "work9", type: "both"},
        "Harassment": {assess_codes: ["work_bully", "work_sex"], direction: "negative", match_codes: ["work10", "work11"], type: "both"},
        "Discrimination": {assess_codes: nil, direction: nil, match_codes: ["work12", "work13"], type: "match"},
        "Not Appreciated": {assess_codes: nil, direction: nil, match_codes: ["work4"], type: "match"},
        "Unfair Treatment": {assess_codes: "work_fairness", direction: "negative", match_codes: "work5", type: "both"},
        "Not Meaningful": {assess_codes: "work_meaningful", direction: "negative", match_codes: "work3", type: "both"}
}

personal_stress_coding = {
    "Stress": {assess_codes: ['dass3', 'dass7'], direction: "negative", match_codes: {present_codes: nil, int_codes: ['dass3', 'dass7']}, type: "both"},
    "Depression":  {assess_codes: ['dass1', 'dass5'], direction: "negative", match_codes: {present_codes: ['dx1', 'dx4'], int_codes: ['dass1', 'dass5']}, type: "both"},
    "Anxiety":  {assess_codes: ['dass2', 'dass6'], direction: "negative", match_codes: {present_codes: 'dx2', int_codes: ['dass2', 'dass6']}, type: "both"},
    "Grief & Loss":  {assess_codes: nil, direction: nil, match_codes: {present_codes: 'stress4', int_codes: nil}, type: "match"},
    "Loneliness":  {assess_codes: nil, direction: nil, match_codes: {present_codes: 'stress1', int_codes: nil}, type: "match"},
    "Personal": {assess_codes: nil, direction: nil, match_codes: {present_codes: ['stress7', 'stress8', 'stress15', 'stress16'], int_codes: nil}, type: "match"},
    "Substance Use": {assess_codes: ['dass4'], direction: "negative", match_codes: {present_codes: ['dx3'], int_codes: ['dass4']}, type: "both"},
    "Trauma": {assess_codes: nil, direction: nil, match_codes: {present_codes: 'dx10', int_codes: nil}, type: "match"},
    "Abuse": {assess_codes: nil, direction: nil, match_codes: {present_codes: 'stress9', int_codes: nil}, type: "match"},
    "Marital/relationships": {assess_codes: nil, direction: nil, match_codes: {present_codes: 'stress2', int_codes: nil}, type: "match"},
    "Family": {assess_codes: nil, direction: nil, match_codes: {present_codes: ['stress3', 'stress5'], int_codes: nil}, type: "match"}, 
    "Health": {assess_codes: nil, direction: nil, match_codes: {present_codes: ['stress6', 'stress17'], int_codes: nil}, type: "match"},
    "Financial": {assess_codes: nil, direction: nil, match_codes: {present_codes: 'stress10', int_codes: nil}, type: "match"},
    "Legal": {assess_codes: nil, direction: nil, match_codes: {present_codes: 'stress11', int_codes: nil}, type: "match"},
    "Parenting": {assess_codes: nil, direction: nil, match_codes: {present_codes: 'stress12', int_codes: nil}, type: "match"}
}

deps = CompanyDependant.
        where.not(user_id: @test).
        pluck(:user_id)
if ARGV[4] == "large"
    quarter_status = []
    quarter_gender = []
    quarter_age = []
    quarter_gen = []
    quarter_personal_stressors = []
    quarter_workplace_stressors = []
    quarter_custom1 = []
    quarter_custom2 = []
    quarter_custom3 = []
    quarter_custom4 = []
    for i in 1..quarter
        users = quarter_users[i-1]
        quarter_status << get_quarter_status(users, deps, id)
        quarter_gender << get_quarter_gender(users)
        quarter_age << get_quarter_age(users, first_range_access_users)
        quarter_gen << get_quarter_gen(users)
        quarter_personal_stressors << generate_personal_stressors(users, personal_stress_coding, first_range_access_users)
        quarter_workplace_stressors << generate_workplace_stressors(users, workplace_stress_coding, first_range_access_users)
        quarter_custom1 << get_custom_fields(users, 1)
        quarter_custom2 << get_custom_fields(users, 2)
        quarter_custom3 << get_custom_fields(users, 3)
        quarter_custom4 << get_custom_fields(users, 4)
    end
else
    ytd_users = quarter_users.flatten
    quarter_status = get_quarter_status(ytd_users, deps, id)
    quarter_gender = get_quarter_gender(ytd_users)
    quarter_age = get_quarter_age(ytd_users, first_range_access_users) #I found a faster but more complicated way to do it that I'm going to try to implement later but it requires making temporary tables to run rails queries
    quarter_gen = get_quarter_gen(ytd_users)
    quarter_personal_stressors = generate_personal_stressors(ytd_users, personal_stress_coding, first_range_access_users).sort_by{ |issue, count| [-count, issue] }.to_h
    quarter_workplace_stressors = generate_workplace_stressors(ytd_users, workplace_stress_coding, first_range_access_users).sort_by{ |issue, count| [-count, issue] }.to_h
    quarter_custom1 = get_custom_fields(ytd_users, 1)
end

#Usage
#Number using full allotment
if ARGV[5] == "plus"
    user_types = {}
    user_types[:"employee"] = total_onboarded - deps
    user_types[:"dependant"] = total_onboarded & deps

    employee_bite_limit = Company.find(id).company_minute.video_bite_employee_minutes
    employee_access_limit = Company.find(id).company_minute.video_access_employee_minutes
    dependant_bite_limit = Company.find(id).company_minute.video_bite_dependant_minutes
    dependant_access_limit = Company.find(id).company_minute.video_access_dependant_minutes

    employee_full_bite = accessed_coverage_limit(user_types[:employee], "bite", employee_bite_limit, contract_year_start, stop)
    employee_full_access = accessed_coverage_limit(user_types[:employee], "access", employee_access_limit, contract_year_start, stop)
    dependant_full_bite = accessed_coverage_limit(user_types[:dependant], "bite", dependant_bite_limit, contract_year_start, stop)
    dependant_full_access = accessed_coverage_limit(user_types[:dependant], "access", dependant_access_limit, contract_year_start, stop)
end

#This uses start instead of contract_start. So it can be misaligned
#If contract start is within range, it could seem like someone is using more hours without hitting limit
#If contract start is before range, it could seem like someone is hitting limit with fewer hours
#Bite usage
bite =  CompanyUsedMinute.
        joins(:appointment).
        where.not(
                deleted_yn: true,
                appointment_id: @testapp).
            where(
                minute_type: "bite",
                company_id: id).
            where("appointments.start_date BETWEEN ? AND ?", start, stop).
            pluck("SUM(minutes)")[0].to_f / 60

#Access usage
access =    CompanyUsedMinute.
            joins(:appointment).
            where.not(
                minute_type: "bite",
                deleted_yn: true,
                appointment_id: @testapp).
            where(company_id: id).
            where("appointments.start_date BETWEEN ? AND ?", start, stop).
            pluck("SUM(minutes)")[0].to_f / 60

#Sale usage
sale =  Appointment.
        joins(:payments).
        where(
            client_covered_yn: true,
            payments: {
                user_id: total_onboarded, 
                payment_type: "sale",
                refund_id: nil}).
        where("appointments.start_date BETWEEN ? AND ?", start, stop).
        where.not(
            id: @testapp,
            payments: {transaction_id: nil}).
        pluck("SUM(amount) / 75")[0].to_f
#This assumes everyone pays $75/hour, but the reality is some people have discounts or different pricing. 

#ORS
#The first completed match for any given user
first_matches = get_first_match_hash(total_onboarded)
#Users with three or more completed appointments before stop date
three_app_users = get_three_app_users(first_matches.keys, stop, true)
#Filter out pre-session assessments that are all 5s
real_ors_asses = get_real_asses(stop, total_onboarded, "ors")
#Find the valid assessment associated with the user's third appointment, or most recent after that if not available (up to 5th).
third_user_asses = get_third_valid_asses(three_app_users, stop, real_ors_asses)
ors = get_ors(third_user_asses, first_matches, false) #true/false to check individual user change

#SRS
#Filter out post-session assessments that are all 5s
real_srs_asses = get_real_asses(stop, total_onboarded, "srs")
#Users who had a valid assessment
real_srs_users =    Assessment.
                    where(id: real_srs_asses).
                    distinct.
                    pluck(:user_id)
#The average of all assessments
first = get_srs_by_assessments(real_srs_asses)
#The average of all users' average
second = get_srs_by_user(real_srs_users, real_srs_asses, false) #true/false to check individual user change
#Consolidates the difference by taking the average of the two definitions
srs = "#{((first + second[:srs]) * 10 /2).round(2)}%"

average_hours_per_user = "#{((bite + access + sale)/total_paid_users_count).round(2)}"

require "csv"
country = "cad"
CSV.open("#{Rails.root.join('tmp').to_s}/access_report_#{country}.csv", 'w') do |writer|
    writer << [ARGV[3]]
    writer << ["Start of contract year", contract_year_start]
    writer << ["Report Dates", "#{start.year}-#{start.month}-#{start.day} - #{stop.year}-#{stop.month}-#{stop.day}"]
    writer << ["Title Dates", "#{report_start.year}-#{report_start.month}-#{report_start.day} - #{stop.year}-#{stop.month}-#{stop.day}"]
    writer << ["Group", "Q1", "Q2", "Q3", "Q4", "YTD"]
    writer << ["Accessing Users", quarter_users_count, total_users_count].flatten
    writer << ["Paid Users",quarter_paid_users_count, total_paid_users_count].flatten
    if ARGV[5] == "plus"
        writer << ["Employees accessing full bite", employee_full_bite]
        writer << ["Employees accessing full access", employee_full_access]
        writer << ["Dependants accessing full bite", dependant_full_bite]
        writer << ["Dependants accessing full access", dependant_full_access]
    end
    writer << ["Total", bite + access + sale]
    writer << ["Bite usage", bite]
    writer << ["Access usage", access]
    writer << ["Sale usage", sale]
    writer << ["Average hours per user", average_hours_per_user]
    writer << ["ors", ors[:percent]]
    writer << ["srs", srs] 
    writer << ["Total Population", company_users(start, stop, ARGV[3]).size]
    if ARGV[4] == "large"
        writer << ["Group", "Q1", "Q2", "Q3", "Q4", "YTD", "%"]
    else
        writer << ["Group", "YTD", "%"]
    end
    writer << ["Status"]
    array_from_hash(normalize_hash(quarter_status), quarter, total_users_count).each do |metric|
        writer << metric
    end
    writer << ["Gender"]
    array_from_hash(normalize_hash(quarter_gender), quarter, total_users_count).each do |metric|
        writer << metric
    end
    writer << ["Age"]
    array_from_hash(quarter_age, quarter, total_users_count).each do |metric|
        writer << metric
    end
    writer << ["Generation"]
    array_from_hash(quarter_gen, quarter, total_users_count).each do |metric|
        writer << metric
    end
    writer << ["Custom1"]
    array_from_hash(normalize_hash(quarter_custom1), quarter, total_users_count).each do |metric|
        writer << metric
    end
    if ARGV[4] == "large"
        writer << ["Custom2"]
        array_from_hash(normalize_hash(quarter_custom2), quarter, total_users_count).each do |metric|
            writer << metric
        end
        writer << ["Custom3"]
        array_from_hash(normalize_hash(quarter_custom3), quarter, total_users_count).each do |metric|
            writer << metric
        end
        writer << ["Custom4"]
        array_from_hash(normalize_hash(quarter_custom4), quarter, total_users_count).each do |metric|
            writer << metric
        end
    end
    writer << ["Personal Stressors"]
    array_from_hash(quarter_personal_stressors, quarter, total_users_count).each do |metric|
        writer << metric
    end
    writer << ["Workplace Stressors"]
    array_from_hash(quarter_workplace_stressors, quarter, total_users_count).each do |metric|
        writer << metric
    end
end

#cd Downloads
#rsync -azP --stats deploy@162.248.180.58:/data/web/api.inkblotpractice.com/current/tmp/access_report_cad.csv .
#rsync -azP --stats deploy-inkblot-us-prod-1.medstack.net:~/medapi.inkblottherapy.com/current/tmp/access_report_us.csv .
