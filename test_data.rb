fake = User.where("email ilike any (array[?])", ["%inkblottherapy.com%", "%+test%", "%@test%"]).pluck(:id)
destroyed = Array(1..User.last.id) - User.pluck(:id)
@test = (fake + destroyed).uniq
@testapp = User.where(id: @test).joins(:appointments).pluck("appointments.id").uniq
@testmatch = User.where(id: @test).joins(:matches).pluck("matches.id").uniq