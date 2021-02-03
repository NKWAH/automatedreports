comp =  UserCompany.
        where.not(user_id: @test).
        distinct.
        pluck(:user_id)
demographics =  User.
                where(id: comp).
                left_joins(:work_detail).
                pluck(:id, :first_name, :middle_name, :last_name, :dob, :gender, "work_details.country", "work_details.state", "work_details.city", "work_details.company_name", "work_details.work_size", "work_details.industry", "work_details.role", "work_details.status")
evaluation_users =  User.
                    where(id: comp).
                    pluck(:id)

require "csv"
header = ["User_ID", "First_Name", "Middle_Name", "Last_Name", "DOB", "Gender", "Country", "State", "City", "Company_Name", "Work_Size", "Industry", "Role", "Status"]
CSV.open("#{Rails.root.join('tmp').to_s}/AssessDemographics.csv", 'w') do |writer|
writer << header
demographics.each do |user|
writer << user
end
end

#All completed evaluations with 24 valid answers
completed_evaluations = Evaluation.
                        joins(:user_assess_answers, completed_yn: true).
                        where(user_id: evaluation_users).
                        where.not(user_assess_answers: {deleted_yn: true}).
                        group(:id).
                        having("COUNT(*) = 24").
                        pluck(:id)
valid_evaluations = Evaluation.
                    where(id: completed_evaluations).
                    group(:user_id).
                    pluck("MAX(id)")

#Rating - How helpful people found the assessment
Evaluation.where(id: valid_evaluations).group(:rating).order(:rating).count

scores =    Evaluation.
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

cd Documents/InkBlot\ Therapy/Analytics/Assess/Benchmarks/
mkdir 2021-01-13/
cd 2021-01-13/
#CAD
rsync -azP --stats deploy@162.248.180.58:/data/web/api.inkblotpractice.com/current/tmp/AssessDemographics.csv .
rsync -azP --stats deploy@162.248.180.58:/data/web/api.inkblotpractice.com/current/tmp/AssessResponses.csv .
#US
rsync -azP --stats deploy-inkblot-us-prod-1.medstack.net:~/medapi.inkblottherapy.com/current/tmp/AssessDemographics.csv .
rsync -azP --stats deploy-inkblot-us-prod-1.medstack.net:~/medapi.inkblottherapy.com/current/tmp/AssessResponses.csv .
