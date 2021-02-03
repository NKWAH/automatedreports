load "nick_reporting/test_data.rb"
load "nick_reporting/company_users.rb"
comp_name = "Pelmorex"
total_life_adds = Company.find_by_name(comp_name).user_companies.where.not(deleted_yn: true).where.not(user_id: @test).distinct.pluck(:user_id)

#Have to check which dates roughly match with dates of administration
pp Evaluation.where(user_id: total_life_adds).order(:created_at).pluck(:created_at)
start = "2020-12-15".to_date&.beginning_of_day
stop = "2021-01-20".to_date&.end_of_day

all_users = company_users(start, stop, comp_name)

#Filter out dependants
#They should never have access to Assess anyway, but could affect response rates
deps = UserCompany.joins(user: :company_dependant).distinct.pluck(:id)
employees = all_users - deps

#Pulling demographic data for employees
demographics =  User.
                where(id: employees).
                left_joins(:work_detail).
                pluck(:id, :first_name, :middle_name, :last_name, :dob, :gender, "work_details.country", "work_details.state", "work_details.city", "work_details.company_name", "work_details.work_size", "work_details.industry", "work_details.role", "work_details.status")

require "csv"
header = ["User_ID", "First_Name", "Middle_Name", "Last_Name", "DOB", "Gender", "Country", "State", "City", "Company_Name", "Work_Size", "Industry", "Role", "Status"]
CSV.open("#{Rails.root.join('tmp').to_s}/AssessDemographics.csv", 'w') do |writer|
writer << header
demographics.each do |user|
writer << user
end
end


#Evaluations that are marked as completed and have 24 valid answers total
completed_evaluations = Evaluation.
                        joins(:user_assess_answers).
                        where(user_id: employees, completed_yn: true).
                        where("evaluations.created_at BETWEEN ? AND ?", start, stop).
                        where.not(user_assess_answers: {deleted_yn: true}).
                        group(:id).
                        having("COUNT(*) = 24").
                        pluck(:id)
#The last completed evaluation per user                  
valid_evaluations = Evaluation.
                    where(id: completed_evaluations).
                    group(:user_id).
                    pluck("MAX(id)")

scores =  Evaluation.
          joins(user_assess_answers: [assess_answer: :assess_question]).
          where(id: valid_evaluations).
          where.not(user_assess_answers: {deleted_yn: true}).
          pluck(:user_id, :id, "assess_questions.id", "assess_questions.text", :value)

require "csv"
header = ["User_ID", "Evaluation_ID", "Question ID", "Question Text", "Value" ]
CSV.open("#{Rails.root.join('tmp').to_s}/AssessResponses.csv", 'w') do |writer|
writer << header
scores.each do |user_score|
writer << user_score
end
end

#Rating
rating_order = {1 => 0, 2 => 0, 3 => 0, 4 => 0, 5 => 0, nil => 0}
rating_order.merge(Evaluation.where(id: valid_evaluations).group(:rating).order(:rating).count)

#Update the folder for the company
cd Documents/InkBlot\ Therapy/Analytics/Assess/
mkdir Pelmorex
mkdir Pelmorex/2020-12-15\ -\ 2021-01-20
cd Pelmorex/2020-12-15\ -\ 2021-01-20

#CAD
rsync -azP --stats deploy@162.248.180.58:/data/web/api.inkblotpractice.com/current/tmp/AssessDemographics.csv .
rsync -azP --stats deploy@162.248.180.58:/data/web/api.inkblotpractice.com/current/tmp/AssessResponses.csv .
rsync -azP --stats deploy@162.248.180.58:/data/web/api.inkblotpractice.com/current/tmp/AssessReports.csv .
#US
rsync -azP --stats deploy-inkblot-us-prod-1.medstack.net:~/medapi.inkblottherapy.com/current/tmp/AssessDemographics.csv .
rsync -azP --stats deploy-inkblot-us-prod-1.medstack.net:~/medapi.inkblottherapy.com/current/tmp/AssessResponses.csv .
rsync -azP --stats deploy-inkblot-us-prod-1.medstack.net:~/medapi.inkblottherapy.com/current/tmp/AssessReports.csv .
