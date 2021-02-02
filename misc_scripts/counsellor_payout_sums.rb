#load "nick_reporting/test_data.rb"
fake = User.where("email ilike any (array[?])", ["%inkblottherapy.com%", "%+test%", "%@test%"]).pluck(:id)
destroyed = Array(1..User.last.id) - User.pluck(:id)
@test = (fake + destroyed).uniq
@testapp = User.where(id: @test).joins(:appointments).pluck("appointments.id").uniq
@testmatch = User.where(id: @test).joins(:matches).pluck("matches.id").uniq

start = "2020-01-01".to_date.beginning_of_day
stop = start + 1.years - 1.seconds
sums =  ProviderPayout.
        joins("INNER JOIN users on provider_payouts.provider_user_id = users.id").
        where(:stripe_charged_at => start..stop).
        where(stripe_charged_result: "succeeded").
        where.not(appointment_id: @testapp).
        group("first_name || ' ' || last_name", "email").
        pluck("first_name || ' ' || last_name", "email", "CAST (SUM(stripe_transfer_amount) AS FLOAT)")
pp sums
