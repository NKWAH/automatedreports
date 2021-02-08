load "nick_reporting/test_data.rb"
start = "2020-12-01".to_date.beginning_of_day
stop = start + 1.months - 1.seconds

efap =  Company.
        where(efap_yn: true).
        pluck(:id)
additional_efap =   Company.
                    where(name: ["Uber", "Maple Leaf Foods", "Afilias"]).
                    pluck(:id)
total_efap = efap + additional_efap

pp CompanyUsedMinute.
joins(:company, :appointment).
where(company_id: total_efap).
where("start_date BETWEEN ? AND ?", start, stop).
group("name", :minute_type).
order("name", :minute_type).
pluck("name", :minute_type, "COUNT(DISTINCT(appointments.id))", "SUM(minutes)")

