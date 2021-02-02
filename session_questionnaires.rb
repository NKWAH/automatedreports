load "nick_reporting/test_data.rb"
@pre_session_ors_answers =  AssessmentMetric.
                            where(name: ["Individual", "Interpersonal", "Social", "Overall"]).
                            where(assessment_type_id: 3).
                            pluck(:id)
@new_ors_answer_ids = Array(1..20)
@srs_metrics =  AssessmentMetric.
                where(assessment_type: AssessmentType.find_by_name("Post")).
                where(name: ["Therapist Relationship", "Goals and Topics", "Approach or Method", "Overall"]).
                pluck(:id)

#ORS
#The first completed match for any given user
def get_first_match_hash(users)
    return  Match.
            joins(:users).
            where(
                completed_yn: true, 
                users: {id: users}).
            where.not(id: @testmatch).
            group("users.id").
            pluck("users.id", "MIN(matches.id)").to_h
end

#Users with three or more completed appointments before stop date
def get_three_app_users(matches, stop, b2b)
    three_app_users =   Appointment.
                        completed.
                        joins(:users).
                        where("start_date <= ?", stop).
                        where.not(id: @testapp).
                        where(users: {id: matches})
    if b2b
        return  three_app_users.
                where(client_covered_yn: true).
                group("users.id").
                having("COUNT(*) >= 3").
                pluck("users.id")
    else
        return  threep_app_users.
                group("users.id").
                having("COUNT(*) >= 3").
                pluck("users.id")
    end
end

#Filter out pre/post session assessments that are all 5s
def get_real_asses(stop, users, type)
    if type == "ors"
        metric_ids = @pre_session_ors_answers
    elsif type == "srs"
        metric_ids = @srs_metrics
    else
        return "Choose a session questionnaire type"
    end
    real_asses =    AssessmentScore.
                    joins(assessment: :appointment).
                    where("start_date <= ?", stop).
                    where(assessment_metric_id: metric_ids).
                    where.not(
                        value: 5,
                        appointments: {id: @testsapp})             
    if users
       return   real_asses.
                where(user_id: users).
                distinct.
                pluck(:assessment_id)
    else
        return  real_asses.
                distinct.
                pluck(:assessment_id)
    end
end

#Find the valid assessment associated with the user's third appointment, or most recent after that if not available (up to 5th).
def get_third_valid_asses(users, stop, real_asses)
    valid_user_asses = {}
    users.each do |user|
        apps =  User.
                find(user).
                appointments.
                completed.
                where("start_date <= ?", stop).
                where.not(appointments: {id: @testapp}).
                order(:start_date)
        for i in 2..4
            assessment_id = apps[i]&.
                            assessments&.
                            find_by_assessment_type_id(3)&.
                            id
            if real_asses.include?(assessment_id)
                valid_user_asses[user] = assessment_id
                break
            end 
        end
    end
    return valid_user_asses
end

def get_last_valid_asses(users, stop, real_asses)
    valid_user_asses = {}
    users.each do |user|
        ass_id =    User.
                    find(user).
                    assessments.
                    joins(:appointment).
                    where("start_date <= ?", stop).
                    where(id: real_asses).
                    where.not(appointments: {id: @testapp}).
                    order("start_date")&.
                    last&.
                    id
        if ass_id
            valid_user_asses[user] = ass_id
        end
    end
    return valid_user_asses
end

#Get the ors from a specific assessment
def assessment_ors(assessment_id)
    return  Assessment.
            find(assessment_id).
            assessment_scores.
            where(assessment_metric_id: @pre_session_ors_answers).
            pluck("AVG(CAST (value AS FLOAT))")[0].
            to_f
end

#Get the ors from a user's legacy match
def get_legacy_match_ors(user_id)
    return  User.
            find(user_id).
            assessments.
            find_by(assessment_type_id: 1).
            assessment_scores.
            pluck(:value)
end

#Get the ors values from a user's nth appointment
def numbered_session_ors(user, n)
    return  User.
            find(user).
            appointments.
            completed.
            where.not(id: @testapp).
            order(:start_date)[n - 1].
            assessments.
            find_by_assessment_type_id(3).
            assessment_scores.
            where(assessment_metric_id: @pre_session_ors_answers).
            pluck(:value)
end

#Get a user's first legacy ors - accounting for their match or first session (if one of them is all 5s and thus not valid)
def first_ors_legacy(user, n)
    scores = get_legacy_match_ors(user)
    first_session_scores = numbered_session_ors(user, n)
    scores_check = nil
    first_scores_check = nil         
    if scores.uniq != [5]
        scores_check = scores.sum.to_f / scores.size
    end
    if first_session_scores.uniq != [5]
        first_scores_check = first_session_scores.sum.to_f / first_session_scores.size
    end
    return [scores_check, first_scores_check].compact.min
end

#Get the ors from a new match
def new_match_ors(match_id)
    return  UserAnswer.
            joins(:match_answer).
            where(match_id: match_id).
            where(match_answer_id: @new_ors_answer_ids).
            pluck("AVG(CAST (value as INT) - 1) * 2.5")[0].to_f    
end

def get_ors(third_user_asses, first_matches, check)
    initial = 0.to_f
    total = 0.to_f
    count = 0.to_f
    if !check
        third_user_asses.each do |user, assessment_id|
            last = assessment_ors(assessment_id)
            match_id = first_matches[user]
            match_type =    Match.
                            find(match_id).
                            match_type
            if match_type == "legacy"
                first = first_ors_legacy(user, 1)
                if first.nil?
                    next
                end
            elsif ["express", "comprehensive"].include?(match_type)
                first = new_match_ors(match_id)
            end
            initial += first
            total = total + last.to_f - first.to_f
            count += 1
        end
        ors = {count: count, initial: initial/count, change: total/count, percent: "#{(total/initial * 100).round(2)}%"}
    else
        ors_check = {}
        third_user_asses.each do |user, assessment_id|
            last = assessment_ors(assessment_id)
            match_id = first_matches[user]
            match_type =    Match.
                            find(match_id).
                            match_type
            if match_type == "legacy"
                first = first_ors_legacy(user, 1)
                if first.nil?
                    next
                end
            elsif ["express", "comprehensive"].include?(match_type)
                first = new_match_ors(match_id)
            end
            initial += first
            total = total + last.to_f - first.to_f
            count += 1
            ors_check[user] = {}
            ors_check[user][:initial] = first
            ors_check[user][:last] = last
            ors_check[user][:change] = last - first
        end
        ors = {count: count, initial: initial/count, change: total/count, percent: "#{(total/initial * 100).round(2)}%", check: ors_check}
    end
    return ors
end

def current_ors_diff(user, stop)
    match_id =  User.
                find(user).
                matches.
                where(completed_yn: true).
                where.not(id: @testmatch).
                order(:completed_at, :id).
                first.
                id
    match_type =    Match.
                    find(match_id).
                    match_type
    if match_type == "legacy"
        first = first_ors_legacy(user, 1)
        if first.nil?
            return "ORS not valid on first match"
        end
    elsif ["express", "comprehensive"].include?(match_type)
        first = new_match_ors(match_id)
    end
    last =  User.
            find(user).
            appointments.
            completed.
            where("start_date <= ?", stop).
            joins(assessments: :assessment_scores).
            where(assessment_scores: {assessment_metric_id: @pre_session_ors_answers}).
            where.not(assessment_scores: {value: 5}).
            order(:start_date).
            last.
            assessments.
            find_by_assessment_type_id(3).
            assessment_scores.
            where(assessment_metric_id: @pre_session_ors_answers).
            pluck("AVG(value)")[0].
            to_f               
    return last - first
end
    

#SRS - User satisfaction:
def get_user_srs(user, real_srs_asses)
    return  User.
            find(user).
            assessments.where(id: real_srs_asses).
            joins(:assessment_scores).
            where(assessment_scores: {assessment_metric_id: @srs_metrics}).
            pluck("AVG(value)")[0].to_f
end

def get_srs_by_user(real_srs_users, real_srs_asses, check)
    total = 0.to_f
    count = 0.to_f
    if !check
        real_srs_users.each do |user|
            average_srs = get_user_srs(user, real_srs_asses)
            total += average_srs
            count += 1    
        end
        srs_by_user = {srs: total/count}
    else
        srs_check = {}
        real_srs_users.each do |user|
            average_srs = get_user_srs(user, real_srs_asses)
            total += average_srs
            count += 1    
            srs_check[user] = {}
            srs_check[user][:srs] = average_srs
            srs_check[user][:count] =   User.
                                        find(user).
                                        assessments.
                                        where(id: real_srs_asses).
                                        size
        end
        srs_by_user = {srs: total/count, check: srs_check}
    end
    return srs_by_user
end

def get_srs_by_assessments(real_srs_asses)
    return  Assessment.
            where(id: real_srs_asses).
            joins(:assessment_scores).
            pluck("AVG(value)")[0].
            to_f
end


