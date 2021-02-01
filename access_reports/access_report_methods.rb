#For a given date, find out what quarter it's in based on a quarters array
def get_quarter(date)
    @quarters.each do |quarter|
        range = quarter[:min]..quarter[:max]
        if range.cover?(date)
            return quarter[:label]
            break
        end
    end
    return false
end

#Gets someone's age on a given date based on dob
def get_age(date, dob)
    if dob.nil?
        return nil
    else
        year_diff = date.year - dob.year
        ((dob + year_diff.years) > date) ? (year_diff - 1) : year_diff
    end
end

#Creates a hash of age groups from an array of arrays, with each subarray being a user's dob and the date they had their first access
def age_group(dates)
    age_hash = {"20 and under" => 0, "21 - 30" => 0, "31 - 40" => 0, "41 - 50" => 0, "51 - 60" => 0, "61+" => 0, "nil" => 0}
    dates.each do |date|
      age = get_age(date[0], date[1])
      case age
        when 0..20
          age_hash["20 and under"] += 1
        when 21..30
          age_hash["21 - 30"] += 1
        when 31..40
          age_hash["31 - 40"] += 1
        when 41..50
          age_hash["41 - 50"] += 1
        when 51..60
          age_hash["51 - 60"] += 1
        when 61..999
          age_hash["61+"] += 1
        else
          age_hash["nil"] += 1
      end
    end
    return age_hash
end

#stress_coding will be looped through, with instructions in each sub-hash on what to query
workplace_stress_coding = {
        "High Workload": {assess_codes: "work_demand", direction: "negative", match_codes: "work1", type: "both"},
        "Lack of Control": {assess_codes: "work_influence", direction: "positive", match_codes: "work2", type: "both"},
        "Poor Management": {assess_codes: ["work_theytrust", "work_youtrust"], direction: "positive", match_codes: "work6", type: "both"},
        "High Conflict": {assess_codes: ["work_conflict", "work_relationship"], direction: "positive", match_codes: "work7", type: "both"},
        "Job Uncertainty": {assess_codes: "work_security", direction: "positive", match_codes: "work8", type: "both"},
        "Work-Life Balance": {assess_codes: "work_balance", direction: "negative", match_codes: "work9", type: "both"},
        "Harassment": {assess_codes: ["work_bully", "work_sex"], direction: "negative", match_codes: ["work10", "work11"], type: "both"},
        "Discrimination": {assess_codes: nil, direction: nil, match_codes: ["work12", "work13"], type: "match"},
        "Not Appreciated": {assess_codes: "work_recognition", direction: nil, match_codes: ["work4"], type: "match"},
        "Unfair Treatment": {assess_codes: "work_fairness", direction: "negative", match_codes: "work5", type: "both"},
        "Not Meaningful": {assess_codes: "work_meaningful", direction: "negative", match_codes: "work3", type: "both"}
    }
school_stress_coding = {
    "Workload": {assess_codes: "school_demand", direction: "negative", match_codes: "school1", type: "both"},
    "Adjustment": {assess_codes: "school_trust", direction: "positive", match_codes: "school2", type: "both"},
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

def generate_workplace_stressors(users, stress_coding, first_range_access_users)
    #For every user, gets their most recent assessment (match or assess) and their last match
    #There are many questions that are match only, but none that are assess only
    most_recent_matches = []
    most_recent_assessments = []
    last_matches = []
    last_assessments = []
    users.each do |user|
        most_recent = most_recent(user, first_range_access_users)
        if most_recent.class.to_s == "Match"
            most_recent_matches << most_recent.id
            last_matches << most_recent.id
            assessment = last_assessment(user, first_range_access_users)&.id #In case they didn't complete an assessment
            if !assessment.nil?
                last_assessments << assessment
            end
            last_assessments << most_recent.id
        elsif most_recent.class.to_s == "Evaluation"
            most_recent_assessments << most_recent.id
            last_assessments << most_recent.id
            match = last_match(user, first_range_access_users)&.id #In case they didn't complete a match
            if !match.nil?
                last_matches << match
            end
        else
            next
        end
    end

    stressors = {}
    stress_coding.each do |key, value|
        assess_stressor_users = [] #Have some variable so it doesn't throw an error if it's not created by value[:type] == "both"
        if value[:type] == "both"
            assess_stressor_users = get_int_stressor_users(value[:assess_codes], value[:direction], most_recent_assessments, "assess")
            match_present_stressor_users = get_present_match_stressor_users(value[:match_codes], most_recent_matches)
        elsif value[:type] == "match"
            match_present_stressor_users = get_present_match_stressor_users(value[:match_codes], last_matches)
        elsif value[:type] = "assess"
            assess_stressor_users = get_int_stressor_users(value[:assess_codes], value[:direction], most_recent_assessments, "assess")
        end
        stressors[key] = (assess_stressor_users + match_present_stressor_users).uniq.size
    end
    stressors
end

#stress_coding will be looped through, with instructions in each sub-hash on what to query
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

def generate_personal_stressors(users, stress_coding, first_range_access_users)
    #For every user, gets their most recent assessment (match or assess) and their last match
    #There are many questions that are match only, but none that are assess only
    most_recent_matches = []
    most_recent_assessments = []
    last_matches = []
    last_assessments = []
    users.each do |user|
        most_recent = most_recent(user, first_range_access_users)
        if most_recent.class.to_s == "Match"
            most_recent_matches << most_recent.id
            last_matches << most_recent.id
            assessment = last_assessment(user, first_range_access_users)&.id #In case they didn't complete an assessment
            if !assessment.nil?
                last_assessments << assessment
            end
            
        elsif most_recent.class.to_s == "Evaluation"
            most_recent_assessments << most_recent.id
            last_assessments << most_recent.id
            match = last_match(user, first_range_access_users)&.id #In case they didn't complete a match
            if !match.nil?
                last_matches << match
            end
            
        else
            next
        end
    end
 
    stressors = {}
    stress_coding.each do |key, value|
        assess_stressor_users = [] #Have some variable so it doesn't throw an error if it's not created by value[:type] == "both"
        match_int_stressor_users = []
        if value[:type] == "both"
            assess_stressor_users = get_int_stressor_users(value[:assess_codes], value[:direction], most_recent_assessments, "assess")
            match_int_stressor_users = get_int_stressor_users(value[:match_codes][:int_codes], "negative", most_recent_matches, "match")
            match_present_stressor_users = get_present_match_stressor_users(value[:match_codes][:present_codes], most_recent_matches)
        elsif value[:type] == "match"
            match_present_stressor_users = get_present_match_stressor_users(value[:match_codes][:present_codes], last_matches)
        elsif value[:type] == "assess"
            assess_stressor_users = get_int_stressor_users(value[:assess_codes], value[:direction], last_assessments, "assess")
        end
        stressors[key] = (assess_stressor_users + match_int_stressor_users + match_present_stressor_users).uniq.size
    end
    stressors
end

#deprecated version I'm holding on to for a bit
def old_get_assessment_answers(codes, direction, type)
    if type == "match"
        answers =   MatchAnswer.
                    joins(:match_question).
                    where(match_questions: {code: codes})
    elsif type == "assess"
        answers =   AssessAnswer.
                    joins(:assess_question).
                    where(assess_questions: {code: codes})
    end
    if direction == "positive"
        return  answers.
                where(value: "0").
                pluck(:id)
    elsif direction == "negative"
        return  answers.
                where.not(value: "0").
                pluck(:id)
    end
end

#Gets the answer ids basen the question code. for either match or assess
def get_assessment_answers(codes, direction, type)
    if direction == "positive"
        int = "3"
    elsif direction == "negative"
        int = "0"
    end
    if type == "match"
        return  MatchAnswer.
                joins(:match_question).
                where(match_questions: {code: codes}).
                where.not(value: int).
                pluck(:id)
    elsif type == "assess"
        return  AssessAnswer.
                joins(:assess_question).
                where(assess_questions: {code: codes}).
                where.not(value: int).
                pluck(:id)      
    end                 
end

#For questions that are answered on a scale, this gets the users that answered above a certain threshold, based on get_assessment_answers
def get_int_stressor_users(codes, direction, assessment_ids, type)
    answers = get_assessment_answers(codes, direction, type)        
    if type == "match"
        return  UserAnswer.
                where(
                    match_id: assessment_ids,
                    match_answer_id: answers).
                distinct.
                pluck(:user_id)
    elsif type == "assess"
        return  UserAssessAnswer.
                    where(
                        evaluation_id: assessment_ids,
                        assess_answer_id: answers).
                    distinct.
                    pluck(:user_id)
    end
end

#For questions that are binary and detected just by their presence 
def get_present_match_stressor_users(match_codes, match_ids)
    match_answers = MatchAnswer.
                    where(value: match_codes).
                    pluck(:id)
    match_users =   UserAnswer.
                    where(
                        match_id: match_ids,
                        match_answer_id: match_answers).
                    distinct.
                    pluck(:user_id)
    return match_users
end

# Returns either the last_match or last_assessment of a user depending on which is most recent
def most_recent(user, first_range_access_users)
    last_assessment = last_assessment(user, first_range_access_users)
    last_match = last_match(user, first_range_access_users)

    return nil if last_match.blank? && last_assessment.blank?
    return last_assessment if last_match.blank?
    return last_match if last_assessment.blank?

    last_assessment.updated_at > last_match.updated_at ? last_assessment : last_match
end

#Returns the last match that a user completed before their first access
def last_match(user, first_range_access_users)
    User.
    find(user).
    matches.
    complete.
    where('matches.created_at < ?', first_range_access_users[user]).
    order(:created_at).
    last
end

#Returns the last assessment that a user completed before their first access
def last_assessment(user, first_range_access_users)
    User.
    find(user).
    evaluations.
    complete.
    where('evaluations.created_at < ?', first_range_access_users[user]).
    order(:created_at).
    last
end

#Returns the last people assessment that a user completed before their first access
def last_people_assessment(user, first_range_access_users)
    User.
    find(user).
    people_assessments.
    complete.
    where('people_assessments.created_at < ?', first_range_access_users[user]).
    order(:created_at).
    last
end 

def get_custom_fields(users, custom_field_number)
        custom =    WorkDetail.
                    where(user_id: users).
                    group(:"custom_field_#{custom_field_number}").
                    count
        valid_num = custom.values.sum
        if !custom[nil].nil?
            custom[nil] += (users.size - valid_num)
        end
    return custom
end

def get_quarter_status(users, deps, id)
    account_type = {}
    num_employees = (users - deps).size #if there's no CompanyDependant record they're an employee
    account_type["Employee"] = num_employees
    num_dependants =    CompanyDependant.
                        where(
                            user_id: users,
                            company_id: id).
                        where.not(deleted_yn: true).
                        group(:relationship).
                        order(relationship: :desc).
                        count
    account_type = account_type.merge(num_dependants).transform_keys {|k| k.to_s.capitalize}
    return account_type
end

def get_quarter_gender(users)
    gender = {}
    male =  User.
            where(id: users).
            where("gender ilike 'male'").
            size
    female =    User.
                where(id: users).
                where("gender ilike 'female'").
                size
    other = User.
            where(id: users).
            where.not("gender ilike any (array[?])", ['male', 'female']).
            size
    gender["Male"] = male
    gender["Female"] = female
    gender["Other"] = other
    gender["NA"] = users.size - male - female - other #some people have nil gender

    return gender
end

def get_quarter_age(users, first_range_access_users)
    booking_and_dob = []
    users.each do |user|
        first_date = first_range_access_users[user]
        dob = User.find(user).dob
        booking_and_dob << [first_date, dob]
    end
    return age_group(booking_and_dob)
end

def get_quarter_gen(users)
    gen_hash = {"Gen Z" => 0, "Millennials" => 0, "Gen X" => 0, "Baby Boomer" => 0, "nil" => 0}
    users.each do |user|
        birthyear = User.find(user).dob&.year
        if birthyear.nil?
          gen_hash["nil"] += 1
          next
        end
        case birthyear
        when 1946..1965
            gen_hash["Baby Boomer"] += 1
        when 1966..1980
            gen_hash["Gen X"] += 1
        when 1981..1995
            gen_hash["Millennials"] += 1
        when 1996..2015
            gen_hash["Gen Z"] += 1
        else
            gen_hash["nil"] += 1
        end
    end
    return gen_hash
end

def get_quarter_advisory(users, type, start, stop)
    AdditionalService.
    where(
        user_id: users,
        type_of: type).
    where("created_at BETWEEN ? AND ?", start, stop).
    group(:category).
    count
end

def get_unique_quarter_advisory(users, type, start, stop)
    AdditionalService.
    where(
        user_id: users,
        type_of: type).
    where("created_at BETWEEN ? AND ?", start, stop).
    group(:category).
    pluck(:category, "COUNT(DISTINCT(user_id))").to_h
end

#Converts the hashes within an array into arrays themselves so they get be written as csv
def array_from_hash(array_of_normalized_hashes, quarter, total_users_count)
    new_hash = {}
    total_users_count = total_users_count.to_f
    if array_of_normalized_hashes.is_a?(Array)
        for i in 0..array_of_normalized_hashes.size - 1
            new_hash = new_hash.merge(array_of_normalized_hashes[i]) {|key, oldval, newval|[oldval, newval].flatten }
        end
#If it's an array, it should be quarter based, and we're adding extra empty quarters to get 4
        new_hash.each do |k,v|
            add_nil = Array.new(4 - quarter, nil)
            ytd = [v].flatten.compact.sum
            percent = "#{(ytd/total_users_count * 100).round(2)}%"
            new_hash[k] = [v, add_nil, ytd, percent].flatten
        end
        return new_hash.to_a.flatten.each_slice(7).to_a
#If it's a hash, should be YTD based and we're only adding percent
    elsif array_of_normalized_hashes.is_a?(Hash)
        array_of_normalized_hashes.each do |k,v|
            percent = "#{(v/total_users_count * 100).round(2)}%"
            new_hash[k] = [v, percent].flatten
        end
        return new_hash.to_a.flatten.each_slice(3).to_a
    end
end


#If any grouped items amount to 0 in a rails query, they don't show up. This can mess with the order if hashes are different lengths
#This method takes the longest hash and makes sure the other ones have the same length
#Might also easier to do this at the point of query e.g. when calculating quarter_status, just add missing values
def normalize_hash(array_of_hashes)
  if array_of_hashes.is_a?(Hash)
    return array_of_hashes
  elsif array_of_hashes.is_a?(Array)
    zero_hash = create_zero_hash(array_of_hashes)
    normalized_hashes = []
    for i in 0..array_of_hashes.size - 1
      normalized_hashes[i] = zero_hash.merge(array_of_hashes[i])
    end
    return normalized_hashes
  end
end

#Finds the longest hash in an array - derepcated. Replaced by all_hash_keys
def longest_hash_params(array_of_hashes)
    max_length = 0
    for i in 0..array_of_hashes.size - 1
        new_length = array_of_hashes[i].size
        if new_length > max_length
            max_length = new_length
            array_index = i
        end
    end
    return {array_index: array_index, max_length: max_length}
end

#Gets a list of all unique keys in an array of hashes
def all_hash_keys(array_of_hashes)
    if array_of_hashes.is_a?(Hash)
        return array_of_hashes
    elsif array_of_hashes.is_a?(Array)
        params = []
        array_of_hashes.each do |hash|
            params << hash.keys
        end
        return params.flatten.uniq
    end
end

#Creates a hash with all the keys of the longest hash, but all values are 0. Used for merging
def create_zero_hash(array_of_hashes)
    keys = all_hash_keys(array_of_hashes)
    values = Array.new(keys.size, 0)
    zero_hash = Hash[keys.zip values]
    if zero_hash[nil]
        zero_hash.delete(nil)
        zero_hash = zero_hash.sort.to_h
        zero_hash[nil] = 0
    end
    return zero_hash
end

#Users that have hit their coverage limit since contract year
def accessed_coverage_limit(users, minute_type, limit, contract_year_start, stop)
    CompanyUsedMinute.
    joins(:appointment).
    where(
        user_id: users,
        minute_type: minute_type).
    where.not(
        deleted_yn: true, 
        appointment_id: @testapp).
    where("appointments.start_date BETWEEN ? AND ?", contract_year_start, stop).
    group(:user_id).
    having("SUM(minutes) >= ?", limit).
    pluck(:user_id).
    size
end

#book of business average
def fix_hash(hash, stressor, employees)
  temp_hash = hash.dup
  count = temp_hash.values.sum
  if stressor & employees
      stressor_hash = hash.dup
      stressor_hash.each do |key, value|
          stressor_hash[key] = value.to_f/employees * 100
      end
  end
  temp_hash[:"count"] = count
  temp_hash.each do |key, value|
      temp_hash[key] = value.to_f/temp_hash[:"count"] * 100
  end
  if stressor
      return {original: temp_hash, stressor: stressor_hash}
  else
      return temp_hash
  end
end


def allotment_distrib(id, start, stop)
    distrib =   CompanyUsedMinute.
                joins(:appointment).
                where(company_id: id).
                where("appointments.start_date BETWEEN ? AND ?", start, stop).
                where.not(
                    appointment_id: @testapp,
                    deleted_yn: true).
                group(:user_id).
                pluck("SUM(minutes)")

    hash = Hash.new(0)
    distrib.each{|key| hash[key] += 1}
    hash.sort_by{ |minutes, count| minutes}.to_h
end