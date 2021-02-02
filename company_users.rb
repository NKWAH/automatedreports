def company_users(start, stop, comp_name, employees_only = true)
    removed_users = UserCompany.
                    where(company: Company.where.not(suspended_yn: true).find_by_name(comp_name)).
                    not_deleted.
                    removed.
                    where.not(user_id: @test).
                    where('started_at < ?', stop).
                    where('removed_at > ?', start)
    not_removed_users = UserCompany.
                        where(company: Company.where.not(suspended_yn: true).find_by_name(comp_name)).
                        not_deleted.
                        not_removed.
                        where.not(user_id: @test).
                        where('started_at < ?', stop)
    total = (removed_users + not_removed_users).pluck(:user_id).uniq
    if employees_only
        deps = CompanyDependant.distinct.pluck(:user_id)
        return total - deps
    end
    return total
end

#cumulative so it doesn't matter if they were ever removed
def cumulative_company_users(stop, company)
    users = UserCompany.
            where(company: company).
            where.not(user_id: @test).
            where('started_at < ?', stop).
            pluck(:user_id).
            uniq
end

#Based on user id. You can combine total onboarded users for multiple companies
#Requires prefiltering of companies for suspended and deleted
def user_id_company_users(start, stop, users)
    removed_users = UserCompany.
                    where(user_id: users).
                    not_deleted.
                    removed.
                    where.not(user_id: @test).
                    where('started_at < ?', stop).
                    where('removed_at > ?', start)
    not_removed_users = UserCompany.
                        where(user_id: users).
                        not_deleted.
                        not_removed.
                        where.not(user_id: @test).
                        where('started_at < ?', stop)
    (removed_users + not_removed_users).pluck(:user_id).uniq
end